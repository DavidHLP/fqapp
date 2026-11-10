import 'dart:io';
import 'dart:convert';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

import 'linux_profile_ownership.dart';

class LinuxLibraryRestoreBlocked implements Exception {
  const LinuxLibraryRestoreBlocked();

  @override
  String toString() =>
      'Linux 恢复须从备份页保存待恢复操作，并在下次启动前执行。'
      '请保留源备份、现有资料及密钥；不能用空书架确认恢复成功。';
}

/// Cold-start recovery with retained raw snapshots; never a cross-box transaction.
/// The caller must stop backend/download writers and close Hive first, while
/// retaining the existing profile owner. Never call this from an active reader.
class LinuxLibraryRecovery {
  static bool _merging = false;
  static bool get isMerging => _merging;
  static File _pending(LinuxProfileOwnership owner) =>
      File('${owner.directory.path}/.fqapp-restore.json');

  static bool hasPending(LinuxProfileOwnership owner) =>
      _pending(owner).existsSync();

  // No key material is stored here. The security provider's unresolved marker
  // is independent and must still pass before this operation can be resumed.
  static void schedule(LinuxProfileOwnership owner, Uint8List bytes) {
    owner.requireHeld();
    if (hasPending(owner)) throw StateError('已有待恢复操作，请重启进入恢复诊断');
    final operation = owner.directory.parent.createTempSync('.fqapp-restore-');
    _command('chmod', ['700', operation.path]);
    File('${operation.path}/backup.json').writeAsBytesSync(bytes, flush: true);
    _command('sync', ['-f', operation.path]);
    _record(owner, {
      'version': 1,
      'operation': operation.path,
      'state': 'pending',
    });
  }

  static void _record(
    LinuxProfileOwnership owner,
    Map<String, dynamic> record,
  ) {
    final temporary = File('${_pending(owner).path}.tmp');
    temporary.writeAsStringSync(jsonEncode(record), flush: true);
    temporary.renameSync(_pending(owner).path);
    _command('sync', ['-f', owner.directory.path]);
  }

  /// Called only in a fresh process, before any business store or writer starts.
  /// Injection points are callbacks owned by tests, never environment switches.
  static Future<void> resume({
    required LinuxProfileOwnership owner,
    required Future<void> Function(Uint8List bytes) merge,
    Future<void> Function(String boundary)? boundary,
  }) async {
    owner.requireHeld();
    final record = Map<String, dynamic>.from(
      jsonDecode(_pending(owner).readAsStringSync()) as Map,
    );
    if (record['version'] != 1 ||
        !['pending', 'merging', 'complete'].contains(record['state'])) {
      throw const FormatException('未知恢复记录，保留资料并停止');
    }
    final operation = Directory(record['operation'] as String);
    if (operation.parent.absolute.path !=
            owner.directory.parent.absolute.path ||
        !operation.uri.pathSegments
            .where((e) => e.isNotEmpty)
            .last
            .startsWith('.fqapp-restore-') ||
        FileSystemEntity.isLinkSync(operation.path)) {
      throw const FormatException('恢复路径无效');
    }
    final source = File('${operation.path}/backup.json');
    if (FileSystemEntity.isLinkSync(source.path)) {
      throw const FormatException('恢复源不接受符号链接');
    }
    final bytes = source.readAsBytesSync();
    if (record['state'] == 'complete') return;
    if (record['snapshot'] == null) {
      final snapshot = preserveClosedProfile(owner: owner, sourceBackup: bytes);
      await boundary?.call('snapshot');
      record['snapshot'] = snapshot.path;
      record['state'] = 'merging';
      _record(owner, record);
    }
    final snapshot = Directory(record['snapshot'] as String);
    if (snapshot.parent.absolute.path != owner.directory.parent.absolute.path ||
        !File('${snapshot.path}/snapshot-ready').existsSync() ||
        FileSystemEntity.isLinkSync(snapshot.path)) {
      throw const FormatException('原始快照未确认，停止恢复');
    }
    await boundary?.call('pending');
    _merging = true;
    try {
      await merge(bytes);
      await boundary?.call('before-complete');
      record['state'] = 'complete';
      _record(owner, record);
      await boundary?.call('complete');
    } finally {
      _merging = false;
    }
  }

  static void acknowledge(LinuxProfileOwnership owner) {
    owner.requireHeld();
    final record = jsonDecode(_pending(owner).readAsStringSync()) as Map;
    if (record['state'] != 'complete') throw StateError('恢复尚未完成');
    _pending(owner).renameSync('${record['operation']}/receipt.json');
    _command('sync', ['-f', owner.directory.path]);
  }

  static Directory preserveClosedProfile({
    required LinuxProfileOwnership owner,
    required Uint8List sourceBackup,
  }) {
    owner.requireHeld();
    final source = owner.directory;
    // Inventory before creating any artifact. Refuse links rather than copying
    // files outside the owned profile or silently omitting user data.
    final entries = source.listSync(recursive: true, followLinks: false);
    for (final entry in entries) {
      if (entry is Link) {
        throw FileSystemException('快照不接受符号链接', entry.path);
      }
      if (entry is File && entry.path.endsWith('.hive')) {
        final name = entry.uri.pathSegments.last;
        if (Hive.isBoxOpen(name.substring(0, name.length - 5))) {
          throw StateError('必须停止写入并关闭 Hive 后才能保全原始资料');
        }
      }
    }
    // A sibling prevents recursive self-copy; createTemp never reuses an older
    // partial snapshot. Keep every partial artifact on failure for inspection.
    final snapshot = source.parent.createTempSync('.fqapp-before-restore-');
    _command('chmod', ['700', snapshot.path]);
    final files = Directory('${snapshot.path}/profile')..createSync();
    for (final entry in entries) {
      final relative = entry.path.substring(source.path.length + 1);
      if (relative == '.fqapp-writer.lock') continue;
      final target = '${files.path}/$relative';
      if (entry is Directory) {
        Directory(target).createSync(recursive: true);
      } else if (entry is File) {
        File(target).parent.createSync(recursive: true);
        entry.copySync(target);
      } else {
        throw FileSystemException('不支持的资料文件类型', entry.path);
      }
    }
    File(
      '${snapshot.path}/source-backup.json',
    ).writeAsBytesSync(sourceBackup, flush: true);
    // syncfs covers copied files and directory entries before publishing ready.
    // This is not VM power-loss durability evidence.
    _command('sync', ['-f', snapshot.path]);
    final marker = File('${snapshot.path}/snapshot-ready.tmp');
    marker.writeAsStringSync('fqapp.closed-profile-snapshot.v1\n', flush: true);
    marker.renameSync('${snapshot.path}/snapshot-ready');
    _command('sync', ['-f', snapshot.path]);
    return snapshot;
  }

  static void _command(String executable, List<String> arguments) {
    final result = Process.runSync(executable, arguments);
    if (result.exitCode != 0) {
      throw FileSystemException('$executable 失败，资料保全未确认');
    }
  }
}
