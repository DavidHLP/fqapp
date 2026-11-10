import 'dart:io';
import 'dart:typed_data';

import 'package:hive_ce/hive.dart';

import 'linux_profile_ownership.dart';

class LinuxLibraryRestoreBlocked implements Exception {
  const LinuxLibraryRestoreBlocked();

  @override
  String toString() =>
      'Linux 安全恢复暂不可用。'
      '请保留源备份、现有资料及密钥；不能用空书架确认恢复成功。';
}

/// Offline preservation only, not a cross-box transaction or a key backup.
/// The caller must stop backend/download writers and close Hive first, while
/// retaining the existing profile owner. Never call this from an active reader.
class LinuxLibraryRecovery {
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
