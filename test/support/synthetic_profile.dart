import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:hive_ce/hive.dart';

/// Business fixtures use real profile fencing and deterministic synthetic keys.
/// Security tests inject their own providers instead of using this helper.
Future<LinuxProfileOwnership?> syntheticProfile(Directory directory) async {
  final binding = TestWidgetsFlutterBinding.ensureInitialized();
  final owner = Platform.isLinux
      ? await LinuxProfileOwnership.acquire(
          directory,
          keyNamespaceDirectory: Directory(
            '${directory.path}/test-key-namespace',
          ),
        )
      : null;
  const channel = MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  final values = <String, String>{
    SecureKeyProvider.hiveBoxKeyName: base64Encode(List.filled(32, 17)),
    SecureKeyProvider.devicePoolKeyName: base64Encode(List.filled(32, 29)),
  };
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(channel, (call) async {
    final key = call.arguments['key'] as String;
    switch (call.method) {
      case 'read':
        return values[key];
      case 'write':
        values[key] = call.arguments['value'] as String;
        return null;
      case 'delete':
        values.remove(key);
        return null;
      default:
        throw UnsupportedError(call.method);
    }
  });
  addTearDown(
    () => binding.runAsync(() async {
      await Hive.close();
      await SecureKeyProvider.settlePendingOperations();
      await owner?.close();
      SecureKeyProvider.instance.resetForTest();
      messenger.setMockMethodCallHandler(channel, null);
    }),
  );
  return owner;
}

Future<void> initSyntheticHive(String path) async {
  await syntheticProfile(Directory(path));
  Hive.init(path);
}

/// Also usable inside runAsync before a widget fixture removes its directory.
Future<void> closeSyntheticProfile() async {
  await Hive.close();
  await SecureKeyProvider.settlePendingOperations();
  await LinuxProfileOwnership.current?.close();
}

/// Drain widget-originated writes before Flutter leaves the fake async zone.
void syntheticWidgetTest(
  String description,
  WidgetTesterCallback callback, {
  Timeout? timeout,
}) {
  testWidgets(description, (tester) async {
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        var closed = false;
        final closing = Hive.close().then((_) => closed = true);
        final deadline = DateTime.now().add(const Duration(seconds: 10));
        while (!closed && DateTime.now().isBefore(deadline)) {
          await tester.pump();
          await Future<void>.delayed(const Duration(milliseconds: 20));
        }
        await closing.timeout(const Duration(seconds: 1));
      });
    });
    await callback(tester);
  }, timeout: timeout);
}
