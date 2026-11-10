import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/models/library_backup.dart';
import 'package:fqapp/services/library_backup_service.dart';
import 'package:fqapp/services/linux_library_recovery.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:hive_ce/hive.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory root;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('fqapp-recovery-');
  });
  tearDown(() async {
    debugDefaultTargetPlatformOverride = null;
    await Hive.close();
    await LinuxProfileOwnership.current?.close();
    await root.delete(recursive: true);
  });

  test(
    'Linux blocks both restore entry points before touching stores',
    () async {
      debugDefaultTargetPlatformOverride = TargetPlatform.linux;
      await LinuxProfileOwnership.acquire(root, keyNamespaceDirectory: root);
      final backup = LibraryBackup.capture(shelf: [], history: [], watched: {});
      final service = LibraryBackupService();
      await expectLater(
        service.restore(backup),
        throwsA(isA<LinuxLibraryRestoreBlocked>()),
      );
      await expectLater(
        service.restoreAi(backup),
        throwsA(isA<LinuxLibraryRestoreBlocked>()),
      );
      expect(
        root.listSync().whereType<File>().map((e) => e.uri.pathSegments.last),
        ['.fqapp-writer.lock'],
      );
    },
  );

  test(
    'open Hive and escaping links are refused without a ready snapshot',
    () async {
      final profile = Directory('${root.path}/profile');
      final owner = await LinuxProfileOwnership.acquire(
        profile,
        keyNamespaceDirectory: Directory('${root.path}/keys'),
      );
      Hive.init(profile.path);
      await Hive.openBox<dynamic>(
        'history_enc',
        encryptionCipher: HiveAesCipher(List.filled(32, 7)),
      );
      expect(
        () => LinuxLibraryRecovery.preserveClosedProfile(
          owner: owner,
          sourceBackup: Uint8List(0),
        ),
        throwsStateError,
      );
      await Hive.close();
      await Link('${profile.path}/outside').create(root.parent.path);
      expect(
        () => LinuxLibraryRecovery.preserveClosedProfile(
          owner: owner,
          sourceBackup: Uint8List(0),
        ),
        throwsA(isA<FileSystemException>()),
      );
      expect(root.listSync().whereType<Directory>().length, 2);
    },
  );

  test(
    'journal publication I/O failure retains source and never marks complete',
    () async {
      final profile = Directory('${root.path}/profile');
      final owner = await LinuxProfileOwnership.acquire(
        profile,
        keyNamespaceDirectory: Directory('${root.path}/keys'),
      );
      // Controlled filesystem obstacle, not a full disk or real permission test.
      Directory('${profile.path}/.fqapp-restore.json.tmp').createSync();
      final bytes = Uint8List.fromList([123, 125]);
      expect(
        () => LinuxLibraryRecovery.schedule(owner, bytes),
        throwsA(isA<FileSystemException>()),
      );
      expect(LinuxLibraryRecovery.hasPending(owner), isFalse);
      final operation = root.listSync().whereType<Directory>().singleWhere(
        (e) => e.path.contains('.fqapp-restore-'),
      );
      expect(File('${operation.path}/backup.json').readAsBytesSync(), bytes);
    },
  );

  String dartExecutable() => Platform.resolvedExecutable.contains('/bin/cache/')
      ? '${Platform.resolvedExecutable.split('/bin/cache/').first}/bin/cache/dart-sdk/bin/dart'
      : Platform.resolvedExecutable;

  test(
    'SIGKILL at ready boundary retains encrypted raw files and source; fresh process reads snapshot',
    () async {
      final arguments = [
        'test/support/library_recovery_process.dart',
        '${root.path}/profile',
        '${root.path}/keys',
        'snapshot',
      ];
      final process = await Process.start(dartExecutable(), arguments);
      final errors = process.stderr.transform(utf8.decoder).join();
      late String snapshot;
      try {
        snapshot = await process.stdout
            .transform(utf8.decoder)
            .transform(const LineSplitter())
            .first
            .timeout(const Duration(seconds: 20));
      } finally {
        process.kill(ProcessSignal.sigkill);
        await process.exitCode;
      }
      expect(await errors, isEmpty);
      expect(File('$snapshot/snapshot-ready').existsSync(), isTrue);
      expect(File('$snapshot/source-backup.json').readAsStringSync(), '{}');
      expect(
        File('$snapshot/profile/history_enc.hive').readAsBytesSync(),
        File('${root.path}/profile/history_enc.hive').readAsBytesSync(),
      );
      for (final path in ['${root.path}/profile', '$snapshot/profile']) {
        final read = await Process.run(dartExecutable(), [
          arguments.first,
          path,
          '${root.path}/keys',
          'read',
        ]);
        expect(read.exitCode, 0, reason: '${read.stderr}');
      }
    },
  );

  test(
    'controlled sync I/O failure preserves source and leaves snapshot unconfirmed',
    () async {
      final bin = Directory('${root.path}/bin')..createSync();
      final sync = File('${bin.path}/sync')
        ..writeAsStringSync('#!/bin/sh\nexit 28\n');
      await Process.run('chmod', ['700', sync.path]);
      final child = await Process.run(
        dartExecutable(),
        [
          'test/support/library_recovery_process.dart',
          '${root.path}/profile',
          '${root.path}/keys',
          'snapshot',
        ],
        environment: {'PATH': '${bin.path}:${Platform.environment['PATH']}'},
      );
      expect(child.exitCode, isNot(0));
      final snapshots = root
          .listSync()
          .whereType<Directory>()
          .where(
            (d) => d.uri.pathSegments
                .where((s) => s.isNotEmpty)
                .last
                .startsWith('.fqapp-before-restore-'),
          )
          .toList();
      expect(snapshots, hasLength(1));
      expect(
        File('${snapshots.single.path}/snapshot-ready').existsSync(),
        isFalse,
      );
      expect(
        File('${snapshots.single.path}/source-backup.json').readAsStringSync(),
        '{}',
      );
      expect(
        File('${root.path}/profile/history_enc.hive').existsSync(),
        isTrue,
      );
    },
  );
}
