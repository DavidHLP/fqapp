import 'dart:async';
import 'dart:io';
import 'dart:convert';

import 'package:fqapp/services/linux_profile_ownership.dart';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/secure_key_provider.dart';

/// The bootstrap awaits this provider during startup, so a secure-storage
/// call that never resolves must degrade (null) instead of hanging startup
/// forever — a wedged Keystore, or an unmocked platform channel in widget
/// tests, both present as a Future that never completes.
void main() {
  late Directory directory;
  late LinuxProfileOwnership owner;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fqapp-key-test-');
    owner = await LinuxProfileOwnership.acquire(
      directory,
      keyNamespaceDirectory: directory,
    );
  });
  tearDown(() async {
    await owner.close();
    await directory.delete(recursive: true);
  });

  test(
    'late write retains A across providers and confirms before release',
    () async {
      final store = _DelayedStorage();
      SecureKeyProvider provider() => SecureKeyProvider(
        storage: store,
        strictLinux: true,
        ownership: owner,
        storageTimeout: const Duration(milliseconds: 20),
      );
      final first = provider();
      expect(await first.getOrCreateKey(), isNull);
      expect(await provider().getOrCreateKey(), isNull);
      expect(store.writes, 1);
      expect(
        owner.pendingMarker(SecureKeyProvider.hiveBoxKeyName).existsSync(),
        isTrue,
      );
      store.finish.complete();
      await SecureKeyProvider.settlePendingOperations();
      final key = await provider().getOrCreateKey();
      expect(
        base64Encode(key!),
        store.values[SecureKeyProvider.hiveBoxKeyName],
      );
      expect(store.writes, 1);
      expect(
        owner.pendingMarker(SecureKeyProvider.hiveBoxKeyName).existsSync(),
        isFalse,
      );
    },
  );

  test(
    'restart marker blocks even a nonempty key without calling provider',
    () async {
      await owner
          .pendingMarker(SecureKeyProvider.hiveBoxKeyName)
          .writeAsString('write', flush: true);
      await owner.close();
      owner = await LinuxProfileOwnership.acquire(
        directory,
        keyNamespaceDirectory: directory,
      );
      final store = _DelayedStorage();
      store.values[SecureKeyProvider.hiveBoxKeyName] = base64Encode(
        List.filled(32, 7),
      );
      final provider = SecureKeyProvider(
        storage: store,
        strictLinux: true,
        ownership: owner,
      );
      expect(await provider.getOrCreateKey(), isNull);
      expect(store.reads, 0);
      expect(store.writes, 0);
    },
  );

  test('malformed key is preserved and restored key can be retried', () async {
    final store = _MapStorage();
    store.values[SecureKeyProvider.hiveBoxKeyName] = 'malformed';
    final provider = SecureKeyProvider(
      storage: store,
      strictLinux: true,
      ownership: owner,
    );
    expect(await provider.getOrCreateKey(), isNull);
    expect(store.values[SecureKeyProvider.hiveBoxKeyName], 'malformed');
    final restored = base64Encode(List.filled(32, 7));
    store.values[SecureKeyProvider.hiveBoxKeyName] = restored;
    expect(base64Encode((await provider.getOrCreateKey())!), restored);
  });

  test('missing key with ciphertext refuses creation', () async {
    await File('${directory.path}/shelf_enc.hive').writeAsBytes([1, 2, 3]);
    final store = _MapStorage();
    final provider = SecureKeyProvider(
      storage: store,
      strictLinux: true,
      ownership: owner,
    );
    expect(await provider.getOrCreateKey(), isNull);
    expect(store.values, isEmpty);
  });

  test(
    'existing pool cannot recreate a missing key, restored key retries',
    () async {
      final store = _MapStorage();
      final provider = SecureKeyProvider(
        storage: store,
        strictLinux: true,
        ownership: owner,
      );
      expect(await provider.devicePoolKey(allowCreate: false), isNull);
      expect(store.values, isEmpty);
      store.values[SecureKeyProvider.devicePoolKeyName] = base64Encode(
        List.filled(32, 5),
      );
      expect(
        await provider.devicePoolKey(allowCreate: false),
        List.filled(32, 5),
      );
    },
  );

  test(
    'pending Hive purpose does not block confirmed device pool purpose',
    () async {
      final store = _DelayedStorage();
      store.values[SecureKeyProvider.devicePoolKeyName] = base64Encode(
        List.filled(32, 5),
      );
      final provider = SecureKeyProvider(
        storage: store,
        strictLinux: true,
        ownership: owner,
        storageTimeout: const Duration(milliseconds: 20),
      );
      expect(await provider.getOrCreateKey(), isNull);
      expect(await provider.devicePoolKey(), List.filled(32, 5));
      store.finish.complete();
      await SecureKeyProvider.settlePendingOperations();
    },
  );

  test('late read does not create B or permit protected writes', () async {
    final store = _DelayedReadStorage();
    final provider = SecureKeyProvider(
      storage: store,
      strictLinux: true,
      ownership: owner,
      storageTimeout: const Duration(milliseconds: 20),
    );
    expect(await provider.getOrCreateKey(), isNull);
    expect(await provider.getOrCreateKey(), isNull);
    expect(store.values, isEmpty);
    store.readResult.complete(base64Encode(List.filled(32, 9)));
    await SecureKeyProvider.settlePendingOperations();
    expect(await provider.getOrCreateKey(), List.filled(32, 9));
    expect(store.values, isEmpty);
  });

  test(
    'write error remains blocked and does not create another candidate',
    () async {
      final store = _DelayedStorage();
      final provider = SecureKeyProvider(
        storage: store,
        strictLinux: true,
        ownership: owner,
      );
      final pending = provider.getOrCreateKey();
      // Complete only after the fake has entered its write operation.
      await store.started.future.timeout(const Duration(seconds: 2));
      store.finish.completeError(StateError('write failed'));
      expect(await pending, isNull);
      expect(await provider.getOrCreateKey(), isNull);
      expect(store.writes, 1);
      expect(
        owner.pendingMarker(SecureKeyProvider.hiveBoxKeyName).existsSync(),
        isTrue,
      );
    },
  );

  test('confirmation mismatch retains durable block across retry', () async {
    final store = _DelayedStorage()..mismatch = true;
    store.finish.complete();
    final provider = SecureKeyProvider(
      storage: store,
      strictLinux: true,
      ownership: owner,
    );
    expect(await provider.getOrCreateKey(), isNull);
    expect(await provider.getOrCreateKey(), isNull);
    expect(store.writes, 1);
    expect(
      owner.pendingMarker(SecureKeyProvider.hiveBoxKeyName).existsSync(),
      isTrue,
    );
  });

  test('a never-resolving read degrades to null after the timeout', () async {
    final provider = SecureKeyProvider(
      storage: _HangingStorage(),
      storageTimeout: const Duration(milliseconds: 100),
    );
    final stopwatch = Stopwatch()..start();
    expect(await provider.getOrCreateKey(), isNull);
    expect(stopwatch.elapsedMilliseconds, lessThan(5000));
  });

  test('a failed load is cached: the next lookup returns null at once', () async {
    final provider = SecureKeyProvider(
      storage: _HangingStorage(),
      storageTimeout: const Duration(milliseconds: 100),
    );
    expect(await provider.getOrCreateKey(), isNull);
    final stopwatch = Stopwatch()..start();
    expect(await provider.getOrCreateKey(), isNull);
    // Would take another full timeout if the failure were not cached.
    expect(stopwatch.elapsedMilliseconds, lessThan(50));
  });

  test('a throwing store degrades to null', () async {
    final provider = SecureKeyProvider(
      storage: _ThrowingStorage(),
      storageTimeout: const Duration(milliseconds: 100),
    );
    expect(await provider.getOrCreateKey(), isNull);
  });

  test('a working store generates once and reuses the persisted key', () async {
    final storage = _MapStorage();
    final first = SecureKeyProvider(
      storage: storage,
      storageTimeout: const Duration(milliseconds: 100),
    );
    final key = await first.getOrCreateKey();
    expect(key, isNotNull);
    expect(key!.length, 32);
    expect(await first.getOrCreateKey(), same(key));

    // A fresh provider reads the persisted key instead of generating anew.
    final second = SecureKeyProvider(
      storage: storage,
      storageTimeout: const Duration(milliseconds: 100),
    );
    expect(await second.getOrCreateKey(), key);
  });
}

class _HangingStorage implements SecureKeyStorage {
  @override
  Future<String?> read(String key) => Completer<String?>().future;

  @override
  Future<void> write(String key, String value) =>
      Completer<void>().future;

  @override
  Future<void> delete(String key) => Completer<void>().future;
}

class _ThrowingStorage implements SecureKeyStorage {
  @override
  Future<String?> read(String key) async => throw StateError('no keystore');

  @override
  Future<void> write(String key, String value) async =>
      throw StateError('no keystore');

  @override
  Future<void> delete(String key) async => throw StateError('no keystore');
}

class _MapStorage implements SecureKeyStorage {
  final Map<String, String> values = {};

  @override
  Future<String?> read(String key) async => values[key];

  @override
  Future<void> write(String key, String value) async {
    values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    values.remove(key);
  }
}

class _DelayedStorage extends _MapStorage {
  final finish = Completer<void>();
  final started = Completer<void>();
  int writes = 0;
  int reads = 0;
  bool mismatch = false;
  @override
  Future<String?> read(String key) async {
    reads++;
    return values[key];
  }

  @override
  Future<void> write(String key, String value) async {
    writes++;
    started.complete();
    await finish.future;
    values[key] = mismatch ? 'wrong' : value;
  }
}

class _DelayedReadStorage extends _MapStorage {
  final readResult = Completer<String?>();
  @override
  Future<String?> read(String key) => readResult.future;
}
