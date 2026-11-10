import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';

void main() {
  late Directory directory;
  setUp(() async {
    directory = await Directory.systemTemp.createTemp('fqapp-lock-test-');
  });
  tearDown(() => directory.delete(recursive: true));

  test('second process cannot own shared keys, crash releases lock', () async {
    final executable = Platform.resolvedExecutable;
    final dart = executable.contains('/bin/cache/')
        ? '${executable.split('/bin/cache/').first}/bin/cache/dart-sdk/bin/dart'
        : executable;
    final arguments = [
      'test/support/linux_profile_lock_process.dart',
      '${directory.path}/profile',
      '${directory.path}/namespace',
    ];
    final first = await Process.start(dart, [...arguments, 'hold']);
    try {
      expect(
        await first.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first,
        'owned',
      );
      final second = await Process.run(dart, arguments);
      expect(second.exitCode, 23);
      // Another profile still shares production keys and must also be blocked.
      final other = await Process.run(dart, [
        arguments[0],
        '${directory.path}/other',
        arguments[2],
      ]);
      expect(other.exitCode, 23);
    } finally {
      first.kill(ProcessSignal.sigkill);
      await first.exitCode;
    }
    final restarted = await Process.run(dart, arguments);
    expect(restarted.exitCode, 0);
    expect(restarted.stdout, contains('owned'));
    final written = await Process.run(dart, [...arguments, 'hive-write']);
    expect(written.exitCode, 0, reason: '${written.stderr}');
    final readback = await Process.run(dart, [...arguments, 'hive-read']);
    expect(readback.exitCode, 0, reason: '${readback.stderr}');
  });

  test('profile path guard rejects a different Hive directory', () async {
    final owner = await LinuxProfileOwnership.acquire(
      directory,
      keyNamespaceDirectory: directory,
    );
    try {
      owner.requireProfileDirectory(directory.path);
      expect(
        () => owner.requireProfileDirectory(directory.parent.path),
        throwsStateError,
      );
    } finally {
      await owner.close();
    }
  });

  test('same isolate collision does not release original owner', () async {
    final owner = await LinuxProfileOwnership.acquire(
      directory,
      keyNamespaceDirectory: directory,
    );
    try {
      await expectLater(
        LinuxProfileOwnership.acquire(
          directory,
          keyNamespaceDirectory: directory,
        ),
        throwsStateError,
      );
      owner.requireHeld();
    } finally {
      await owner.close();
    }
    final retry = await LinuxProfileOwnership.acquire(
      directory,
      keyNamespaceDirectory: directory,
    );
    await retry.close();
  });
}
