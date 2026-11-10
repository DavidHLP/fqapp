import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:hive_ce/hive.dart';

import 'linux_profile_ownership.dart';

/// Minimal read/write surface over the platform secure store, kept as an
/// interface so tests can substitute an in-memory fake instead of driving a
/// MethodChannel.
abstract interface class SecureKeyStorage {
  Future<String?> read(String key);
  Future<void> write(String key, String value);
  Future<void> delete(String key);
}

/// Production backend: `flutter_secure_storage` (Android Keystore /
/// EncryptedSharedPreferences, iOS Keychain). The raw key bytes never touch
/// SharedPreferences or any other plaintext store.
class FlutterSecureKeyStorage implements SecureKeyStorage {
  const FlutterSecureKeyStorage([this._storage = const FlutterSecureStorage()]);

  final FlutterSecureStorage _storage;

  @override
  Future<String?> read(String key) => _storage.read(key: key);

  @override
  Future<void> write(String key, String value) =>
      _storage.write(key: key, value: value);

  @override
  Future<void> delete(String key) => _storage.delete(key: key);
}

/// In-memory fake for tests and for environments without a platform channel.
class InMemorySecureKeyStorage implements SecureKeyStorage {
  final Map<String, String> _values = {};

  @override
  Future<String?> read(String key) async => _values[key];

  @override
  Future<void> write(String key, String value) async {
    _values[key] = value;
  }

  @override
  Future<void> delete(String key) async {
    _values.remove(key);
  }
}

/// Owns the random 256-bit keys that encrypt local data at rest.
///
/// One key per purpose, all base64-encoded in secure storage:
/// - [hiveBoxKeyName]: the Hive `HiveAesCipher` key for every encrypted box
///   (see `EncryptedHive`);
/// - [devicePoolKeyName]: the Rust device-pool file key, handed to the core
///   via the `set_device_pool_key` FRB call at startup (P1-2). Sharing the
///   infrastructure but not the key material: compromising one store must not
///   open the other.
///
/// Linux production calls require profile ownership and durable confirmation.
/// A timeout bounds the caller only; the underlying operation remains owned.
class SecureKeyProvider {
  SecureKeyProvider({
    SecureKeyStorage? storage,
    this.storageTimeout = const Duration(seconds: 10),
    bool? strictLinux,
    this.ownership,
  }) : _storage = storage ?? const FlutterSecureKeyStorage(),
       strictLinux =
           strictLinux ??
           (Platform.isLinux &&
               (storage == null || storage is FlutterSecureKeyStorage));

  static final SecureKeyProvider instance = SecureKeyProvider();
  static const hiveBoxKeyName = 'fqapp_hive_encryption_key_v1';
  static const devicePoolKeyName = 'fqapp_device_pool_key_v1';
  final Duration storageTimeout;
  final SecureKeyStorage _storage;
  final bool strictLinux;
  final LinuxProfileOwnership? ownership;
  static final Object _productionScope = Object();
  static final Map<Object, Map<String, _KeyOperation>> _operations = {};
  Object get _scope =>
      _storage is FlutterSecureKeyStorage ? _productionScope : _storage;

  Future<Uint8List?> getOrCreateKey({
    String name = hiveBoxKeyName,
    bool allowCreate = true,
  }) {
    LinuxProfileOwnership? owner;
    if (strictLinux) {
      owner = ownership ?? LinuxProfileOwnership.requireCurrent();
      owner.requireHeld();
    }
    final operations = _operations.putIfAbsent(owner ?? _scope, () => {});
    final marker = owner?.pendingMarker(name);
    final existing = operations[name];
    if (existing != null) {
      final failure = existing.failedAt;
      if (failure == null ||
          DateTime.now().difference(failure) < const Duration(seconds: 30)) {
        return existing.result;
      }
      operations.remove(name);
    }
    final operation = _KeyOperation();
    operations[name] = operation;
    final underlying = _loadOrCreate(name, owner, allowCreate);
    operation.settled = underlying.then((key) {
      operation.result = Future.value(key);
      // A completed read failure is retryable; unresolved writes retain marker.
      if (key == null && !(marker?.existsSync() ?? false)) {
        if (owner != null) {
          operations.remove(name);
        } else {
          operation.failedAt = DateTime.now();
        }
      }
      return key;
    });
    owner?.trackKeyOperation(operation.settled);
    operation.result = operation.settled.timeout(
      storageTimeout,
      onTimeout: () => null,
    );
    return operation.result;
  }

  Future<Uint8List?> _loadOrCreate(
    String name,
    LinuxProfileOwnership? owner,
    bool allowCreate,
  ) async {
    final marker = owner?.pendingMarker(name);
    // After process loss, provider completion is unknown. Recovery requires an
    // isolated provider audit; even a nonempty read cannot prove no late write.
    if (marker?.existsSync() ?? false) return null;
    var writing = false;
    try {
      if (marker != null) await marker.writeAsString('read', flush: true);
      final stored = await _storage.read(name);
      if (stored != null) {
        Uint8List? bytes;
        try {
          final decoded = base64Decode(stored);
          if (decoded.length == 32) bytes = Uint8List.fromList(decoded);
        } catch (_) {
          /* Preserve malformed Linux entries for recovery. */
        }
        if (bytes != null) {
          if (marker != null) await marker.delete();
          return bytes;
        }
        if (owner != null) {
          if (marker != null) await marker.delete();
          return null;
        }
      }
      final existingHive =
          owner != null &&
          name == hiveBoxKeyName &&
          owner.directory
              .listSync(recursive: true, followLinks: false)
              .any(
                (entry) =>
                    entry is File &&
                    RegExp(r'_enc\.hive[c]?$').hasMatch(entry.path),
              );
      if (!allowCreate || existingHive) {
        if (marker != null) await marker.delete();
        return null;
      }
      writing = true;
      if (marker != null) await marker.writeAsString('write', flush: true);
      final fresh = Uint8List.fromList(Hive.generateSecureKey());
      final encoded = base64Encode(fresh);
      await _storage.write(name, encoded);
      // Await completion BEFORE read-back. A timeout never starts candidate B.
      if (await _storage.read(name) != encoded) return null;
      if (marker != null) await marker.delete();
      return fresh;
    } catch (_) {
      if (!writing && marker != null && marker.existsSync()) {
        await marker.delete();
      }
      return null;
    }
  }

  /// Shutdown hook: never release ownership while a key call is unresolved.
  static Future<void> settlePendingOperations() async {
    for (final scope in _operations.values.toList()) {
      await Future.wait(scope.values.map((operation) => operation.settled));
    }
  }

  /// Device-pool file key for the P1-2 FRB handoff. Same infrastructure as
  /// the Hive key, separate key material.
  Future<Uint8List?> devicePoolKey({bool allowCreate = true}) =>
      getOrCreateKey(name: devicePoolKeyName, allowCreate: allowCreate);

  @visibleForTesting
  void resetForTest() {
    _operations.remove(_scope);
  }
}

class _KeyOperation {
  DateTime? failedAt;
  late Future<Uint8List?> result;
  late Future<Uint8List?> settled;
}
