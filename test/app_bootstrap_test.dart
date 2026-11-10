import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/main.dart' as app;
import 'package:fqapp/services/app_log.dart';
import 'package:fqapp/services/encrypted_hive.dart';
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:fqapp/services/library_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  testWidgets('ownership busy offers dedicated exit without retry or writes', (
    tester,
  ) async {
    var exited = false;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () async => throw LinuxOwnershipBusy(),
          ownershipBusyExit: () => exited = true,
          child: const Text('business'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('fqapp 已有实例正在运行'), findsOneWidget);
    expect(find.text('重试'), findsNothing);
    expect(find.text('business'), findsNothing);
    await tester.tap(find.text('关闭并退出'));
    expect(exited, isTrue);
  });

  testWidgets('persistent quarantine gates startup and late lazy isolation', (
    tester,
  ) async {
    late Directory directory;
    await tester.runAsync(() async {
      directory = await Directory.systemTemp.createTemp('fqapp-quarantine-ui-');
      File(
        '${directory.path}/shelf_enc.unreadable-123.hive',
      ).writeAsStringSync('synthetic');
    });
    Widget boot() => MaterialApp(
      home: app.AppBootstrap(
        quarantineDirectory: directory,
        initializer: () async {},
        child: const Text('business'),
      ),
    );
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
    expect(find.text('本地数据已隔离，尚未恢复'), findsOneWidget);
    expect(find.text('business'), findsNothing);
    expect(find.textContaining(directory.path), findsOneWidget);
    await tester.tap(find.text('我已了解尚未恢复，继续使用当前资料'));
    await tester.pumpAndSettle();
    expect(find.text('business'), findsOneWidget);
    EncryptedHive.quarantineChanges.value++;
    await tester.pumpAndSettle();
    expect(find.text('business'), findsNothing);
    await tester.pumpWidget(const SizedBox());
    await tester.pumpWidget(boot());
    await tester.pumpAndSettle();
    expect(find.text('本地数据已隔离，尚未恢复'), findsOneWidget);
    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() => directory.delete(recursive: true));
  });

  testWidgets('ownership failure blocks runtime and all business bootstrap', (
    tester,
  ) async {
    var runtimeWrites = 0;
    var backendWrites = 0;
    var hiveWrites = 0;
    var fail = true;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () async {
            if (fail) throw StateError('profile locked');
            runtimeWrites++;
          },
          child: app.AppBootstrap(
            backendStarter: () async {
              backendWrites++;
            },
            initializer: () async {
              hiveWrites++;
            },
            child: const Text('business'),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect([runtimeWrites, backendWrites, hiveWrites], [0, 0, 0]);
    expect(find.text('business'), findsNothing);
    fail = false;
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect([runtimeWrites, backendWrites, hiveWrites], [1, 1, 1]);
    expect(find.text('business'), findsOneWidget);
  });

  testWidgets('required backend failure blocks local writes and retries', (
    tester,
  ) async {
    var attempts = 0;
    var localWrites = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          backendMustSucceed: true,
          backendStarter: () async {
            if (++attempts == 1) throw StateError('pool key unavailable');
          },
          initializer: () async {
            localWrites++;
          },
          child: const Text('business'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(localWrites, 0);
    expect(find.text('business'), findsNothing);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(attempts, 2);
    expect(localWrites, 1);
  });

  testWidgets('synchronous backend hook failure remains retryable', (
    tester,
  ) async {
    var localWrites = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          backendStarter: () => throw StateError('hook failed'),
          initializer: () async {
            localWrites++;
          },
          child: const Text('business'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(localWrites, 0);
    expect(find.text('无法读取本地数据'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('retrying initialization retains existing Hive history', (
    tester,
  ) async {
    SharedPreferences.setMockInitialValues({});
    final tempRoot = Directory.systemTemp.absolute;
    late Directory directory;
    late Box<dynamic> history;
    late LinuxProfileOwnership owner;
    final record = {
      'id': 'kept',
      'kind': 'book',
      'title': '已保存作品',
      'chapterId': 'chapter-7',
      'episode': 6,
      'position': 73.5,
    };
    await tester.runAsync(() async {
      directory = await tempRoot.createTemp('fqapp-bootstrap-');
      owner = await LinuxProfileOwnership.acquire(
        directory,
        keyNamespaceDirectory: directory,
      );
      Hive.init(directory.path);
      history = await Hive.openBox<dynamic>('history_enc');
      await Hive.openBox<dynamic>('read_time_enc');
      // 已看集 box 也在 LibraryStore.init 里开箱（F07），同样要预开，
      // 否则 openBox 落在 widget 测试的 fake-async 路径上不会完成。
      await Hive.openBox<dynamic>('watched_episodes_enc');
      await history.put('kept', record);
    });
    addTearDown(() async {
      await tester.pumpWidget(const SizedBox.shrink());
      await tester.runAsync(() async {
        await Hive.close();
        await owner.close();
        if (directory.absolute.parent.path != tempRoot.path) {
          throw StateError('Temporary directory escaped its parent');
        }
        await directory.delete(recursive: true);
      });
    });
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () async {
            attempts++;
            await LibraryStore.instance.init();
            if (attempts == 1) throw StateError('transient startup failure');
          },
          child: const Text('ready'),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('无法读取本地数据'), findsOneWidget);
    expect(history.get('kept'), record);
    await tester.tap(find.text('重试'));
    await tester.pumpAndSettle();
    expect(find.text('ready'), findsOneWidget);
    expect(attempts, 2);
    expect(history.get('kept'), record);
    expect(
      (await LibraryStore.instance.historyEntry('kept'))?['position'],
      73.5,
    );
  });

  testWidgets('bootstrap mounts business pages only after a successful retry', (
    tester,
  ) async {
    final first = Completer<void>();
    final retry = Completer<void>();
    var attempts = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () => ++attempts == 1 ? first.future : retry.future,
          child: const Text('ready'),
        ),
      ),
    );
    expect(find.text('ready'), findsNothing);
    expect(attempts, 1);
    first.completeError(StateError('cannot open stored data'));
    await tester.pump();
    expect(find.text('无法读取本地数据'), findsOneWidget);
    final button = tester.widget<OutlinedButton>(find.byType(OutlinedButton));
    button.onPressed!();
    button.onPressed!();
    await tester.pump();
    expect(attempts, 2);
    expect(find.text('ready'), findsNothing);
    retry.complete();
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
  });

  testWidgets('disposing a pending bootstrap ignores its late completion', (
    tester,
  ) async {
    final initialized = Completer<void>();
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () => initialized.future,
          child: const Text('ready'),
        ),
      ),
    );
    await tester.pumpWidget(const SizedBox.shrink());
    initialized.completeError(StateError('late initialization error'));
    await tester.pump();
    expect(tester.takeException(), isNull);
  });

  testWidgets('backend starts before local data init completes', (
    tester,
  ) async {
    final localInit = Completer<void>();
    var backendStarted = false;
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () => localInit.future,
          backendStarter: () async {
            backendStarted = true;
          },
          child: const Text('ready'),
        ),
      ),
    );
    await tester.pump();
    expect(backendStarted, isTrue);
    expect(find.text('ready'), findsNothing);
    localInit.complete();
    await tester.pump();
    expect(find.text('ready'), findsOneWidget);
  });

  testWidgets('backend failure does not fail the bootstrap gate', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: app.AppBootstrap(
          initializer: () async {},
          backendStarter: () async {
            throw StateError('backend down');
          },
          child: const Text('ready'),
        ),
      ),
    );
    // No pumpAndSettle: it advances the fake clock past the next test's
    // AnimationController start and trips its elapsed-time assertion.
    await tester.pump();
    await tester.pump();
    // Backend errors are owned by RootShell's UI, not the bootstrap gate.
    expect(find.text('ready'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('main renders a retryable screen when the data directory fails', (
    tester,
  ) async {
    const channel = MethodChannel('plugins.flutter.io/path_provider');
    var attempts = 0;
    final messenger =
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(channel, (call) async {
      // 只统计引导用的文档目录（Hive.initFlutter）；应用日志落盘会另探一次
      // 支持目录（getApplicationSupportDirectory），与本用例的「重试一次」无关。
      if (call.method == 'getApplicationDocumentsDirectory') attempts++;
      throw PlatformException(
        code: 'unavailable',
        message: 'private-storage-path',
      );
    });
    addTearDown(() => messenger.setMockMethodCallHandler(channel, null));
    addTearDown(() => tester.pumpWidget(const SizedBox.shrink()));
    app.main();
    // main() 接管了 debugPrint 与 FlutterError.onError，把应用日志收进缓冲。
    // flutter_test 会在测试体结束时断言这两个 foundation 调试变量未被改动，
    // 所以必须在**测试体内**还原（addTearDown 跑在不变量检查之后，太晚）。
    try {
      await tester.pump();
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('无法读取本地数据'), findsOneWidget);
      expect(find.textContaining('private-storage-path'), findsNothing);
      expect(attempts, 1);
      await tester.tap(find.text('重试'));
      await tester.pump();
      await tester.pump();
      expect(attempts, 2);
      expect(find.text('无法读取本地数据'), findsOneWidget);
      expect(tester.takeException(), isNull);
    } finally {
      await AppLog.instance.resetForTest();
    }
  });
  for (final lazy in [false, true]) {
    testWidgets('normal bootstrap blocks real wrong-key isolation lazy=$lazy', (
      tester,
    ) async {
      late Directory directory;
      late List<int> original;
      await tester.runAsync(() async {
        directory = await Directory.systemTemp.createTemp(
          'fqapp-bootstrap-key-',
        );
        Hive.init(directory.path);
        final box = await EncryptedHive.openBox<String>(
          Hive,
          'shelf',
          keys: SecureKeyProvider(storage: InMemorySecureKeyStorage()),
        );
        await box.put('book', 'synthetic retained book');
        await box.close();
        original = File('${directory.path}/shelf_enc.hive').readAsBytesSync();
      });
      final ready = Completer<void>();
      await tester.pumpWidget(MaterialApp(home: app.AppBootstrap(
        quarantineDirectory: directory,
        initializer: () => ready.future,
        child: const Text('business'),
      )));
      await tester.runAsync(() async {
        final wrong = SecureKeyProvider(storage: InMemorySecureKeyStorage());
        if (lazy) {
          await EncryptedHive.openLazyBox<String>(Hive, 'shelf', keys: wrong);
        } else {
          await EncryptedHive.openBox<String>(Hive, 'shelf', keys: wrong);
        }
        AppLog.instance.clear();
        ready.complete();
      });
      await tester.pumpAndSettle();
      expect(find.text('本地数据已隔离，尚未恢复'), findsOneWidget);
      expect(find.text('business'), findsNothing);
      final preserved = EncryptedHive.quarantines(directory);
      expect(File(preserved.single.path).readAsBytesSync(), original);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await Hive.close();
        await directory.delete(recursive: true);
      });
    });
  }

}
