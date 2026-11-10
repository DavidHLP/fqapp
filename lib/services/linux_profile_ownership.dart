import 'dart:io';

/// One writer for both the profile directory and the shared Secret Service keys.
/// Acquire before runtime deployment/Hive.init; close only after backend/Hive and
/// outstanding key operations have stopped. Never unlink a live lock file.
/// Acquire only on the main isolate: Dart locks are process-scoped on Linux.
class LinuxProfileOwnership {
  LinuxProfileOwnership._(
    this.directory,
    this._namespace,
    this._locks,
    this._paths,
  );

  static LinuxProfileOwnership? current;
  static final Set<String> _held = {};
  final Directory directory;
  final Directory _namespace;
  final List<Future<Object?>> _keyOperations = [];
  bool _closing = false;
  final List<RandomAccessFile> _locks;
  final List<String> _paths;
  bool _closed = false;

  static Future<LinuxProfileOwnership> acquire(
    Directory directory, {
    Directory? keyNamespaceDirectory,
  }) async {
    // The production key names are shared even when the profile path changes.
    final home = Platform.environment['HOME'];
    if (keyNamespaceDirectory == null &&
        (home == null || !home.startsWith('/'))) {
      throw StateError('无法确定共享密钥命名空间目录');
    }
    final namespace =
        keyNamespaceDirectory ?? Directory('$home/.local/share/fqapp');
    final locks = <RandomAccessFile>[];
    final paths = <String>[];
    try {
      for (final dir in [namespace, directory]) {
        await dir.create(recursive: true);
        final canonical = await dir.resolveSymbolicLinks();
        final path = '$canonical/.fqapp-writer.lock';
        if (paths.contains(path)) continue;
        if (!_held.add(path)) throw StateError('fqapp 已有实例正在使用此资料');
        paths.add(path);
        final handle = await File(path).open(mode: FileMode.append);
        locks.add(handle);
        await handle.lock(FileLock.exclusive);
        // Hive may live in Documents; only our key namespace is private.
        final permissions = await Process.run('chmod', [
          if (identical(dir, namespace)) '700' else '600',
          if (identical(dir, namespace)) canonical else path,
        ]);
        if (permissions.exitCode != 0) {
          throw FileSystemException('资料目录权限设置失败', canonical);
        }
      }
      final owner = LinuxProfileOwnership._(
        Directory(await directory.resolveSymbolicLinks()),
        Directory(await namespace.resolveSymbolicLinks()),
        locks,
        paths,
      );
      current = owner;
      return owner;
    } catch (_) {
      for (final handle in locks.reversed) {
        await handle.close();
      }
      _held.removeAll(paths);
      rethrow;
    }
  }

  void requireHeld() {
    if (_closed || _closing) throw StateError('资料所有权已关闭');
  }

  void requireProfileDirectory(String path) {
    requireHeld();
    final actual = Directory(path).resolveSymbolicLinksSync();
    if (actual != directory.path && !actual.startsWith('${directory.path}/')) {
      throw StateError('资料路径不在已持锁目录内');
    }
  }

  File pendingMarker(String purpose) {
    requireHeld();
    if (!RegExp(r'^[a-zA-Z0-9_]+$').hasMatch(purpose)) {
      throw ArgumentError.value(purpose, 'purpose');
    }
    return File('${_namespace.path}/.$purpose.pending');
  }

  void trackKeyOperation(Future<Object?> operation) {
    requireHeld();
    _keyOperations.add(operation);
  }

  Future<void>? _closeFuture;

  Future<void> close() => _closeFuture ??= _close();

  Future<void> _close() async {
    if (_closed) return;
    _closing = true;
    await Future.wait(_keyOperations);
    _closed = true;
    if (identical(current, this)) current = null;
    for (final handle in _locks.reversed) {
      await handle.close();
    }
    _held.removeAll(_paths);
  }

  static LinuxProfileOwnership requireCurrent() {
    final owner = current;
    if (owner == null) throw StateError('必须先取得 Linux 资料所有权');
    owner.requireHeld();
    return owner;
  }
}
