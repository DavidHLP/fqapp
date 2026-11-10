import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/services.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:fqapp/services/backend_transport.dart';

/// The bridge runtime is a process-wide one-shot: a successful load is reused,
/// but a load that fails must not be cached, or the app could never start the
/// core again after one bad native init.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(RustBackendTransport.resetRuntimeForTest);

  test(
    'existing pool with no key blocks transport without creating a key',
    () async {
      final root = await Directory.systemTemp.createTemp('fqapp-no-pool-key-');
      final owner = await LinuxProfileOwnership.acquire(
        root,
        keyNamespaceDirectory: Directory('${root.path}/keys'),
      );
      final pool = File('${root.path}/device_pool.json');
      final bytes = [1, 2, 3, 4];
      await pool.writeAsBytes(bytes);
      var writes = 0;
      const channel = MethodChannel(
        'plugins.it_nomads.com/flutter_secure_storage',
      );
      final messenger =
          TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
      messenger.setMockMethodCallHandler(channel, (call) async {
        if (call.method == 'write') writes++;
        return null;
      });
      RustBackendTransport.runtimeInitializer = () async {};
      final transport = RustBackendTransport();
      try {
        await expectLater(
          transport.start(
            configPath: 'unused',
            poolPath: pool.path,
            filterPath: 'unused',
            runtimeDir: root.path,
          ),
          throwsA(
            isA<StateError>().having(
              (error) => error.message,
              'message',
              contains('设备池密钥不可用'),
            ),
          ),
        );
        expect(writes, 0);
        expect(await pool.readAsBytes(), bytes);
      } finally {
        await transport.close();
        await owner.close();
        messenger.setMockMethodCallHandler(channel, null);
        await root.delete(recursive: true);
      }
    },
    skip: !Platform.isLinux,
  );

  test('Linux refuses runtime startup before acquiring ownership', () async {
    var calls = 0;
    RustBackendTransport.runtimeInitializer = () async {
      calls++;
    };
    final transport = RustBackendTransport();
    try {
      await expectLater(
        transport.start(
          configPath: 'unused',
          poolPath: 'unused',
          filterPath: 'unused',
          runtimeDir: 'unused',
        ),
        throwsStateError,
      );
      expect(calls, 0);
    } finally {
      await transport.close();
    }
  }, skip: !Platform.isLinux);

  test(
    'a failed bridge init is not cached and the next attempt runs again',
    () async {
      var attempts = 0;
      RustBackendTransport.runtimeInitializer = () async {
        attempts += 1;
        if (attempts == 1) {
          throw StateError('dlopen failed');
        }
      };

      await expectLater(RustBackendTransport.ensureRuntime(), throwsStateError);
      await RustBackendTransport.ensureRuntime();

      expect(attempts, 2);
    },
  );

  test('a successful bridge init stays cached for the process', () async {
    var attempts = 0;
    RustBackendTransport.runtimeInitializer = () async {
      attempts += 1;
    };

    await RustBackendTransport.ensureRuntime();
    await RustBackendTransport.ensureRuntime();

    expect(attempts, 1);
  });

  test('a half-initialized bridge is reset before the retry', () async {
    // RustLib.init 先写 FRB 的内部状态、再跑 Rust initializers：后一半失败时
    // 直接重试会被 FRB 以 "Should not initialize flutter_rust_bridge twice"
    // 拒绝。这里模拟那条路径，确认重试前先调用了 FRB 的 dispose()。
    var initialized = false;
    var resets = 0;
    var attempts = 0;
    RustBackendTransport.runtimeInitialized = () => initialized;
    RustBackendTransport.disposeRuntime = () {
      resets++;
      initialized = false;
    };
    RustBackendTransport.runtimeInitializer = () async {
      attempts++;
      if (initialized) {
        throw StateError('Should not initialize flutter_rust_bridge twice');
      }
      if (attempts == 1) {
        // 失败时 FRB 的状态已经落下，和真实的半初始化一致。
        initialized = true;
        throw StateError('executeRustInitializers failed');
      }
    };

    await expectLater(RustBackendTransport.ensureRuntime(), throwsStateError);
    expect(initialized, isFalse, reason: '失败后必须把 FRB 的半初始化状态复位');

    await RustBackendTransport.ensureRuntime();
    expect(attempts, 2);
    expect(resets, 1);
  });

  test(
    'an already initialized bridge is reused, never initialized twice',
    () async {
      var attempts = 0;
      var resets = 0;
      RustBackendTransport.runtimeInitialized = () => true;
      RustBackendTransport.disposeRuntime = () => resets++;
      RustBackendTransport.runtimeInitializer = () async => attempts++;

      await RustBackendTransport.ensureRuntime();
      await RustBackendTransport.ensureRuntime();

      expect(attempts, 0);
      expect(resets, 0);
    },
  );
}
