import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:fqapp/main.dart' as app;
import 'package:fqapp/services/secure_key_provider.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:fqapp/services/backend_service.dart';
import 'package:hive_ce/hive.dart';
import 'package:fqapp/pages/home_page.dart';
import 'package:fqapp/pages/player_page.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/services/platform_capabilities.dart';
import '../test/support/fakes.dart' show MemoryReaderStore;
import 'package:fqapp/pages/reader_page.dart';
import 'package:fqapp/services/desktop_platform.dart';
import 'package:fqapp/services/imported_book_store.dart';
import 'package:fqapp/services/native_player.dart';
import 'package:fqapp/services/platform_channel.dart';
import 'package:fqapp/services/system_tts.dart';

// Real runner/plugins only. Invoke in a disposable HOME, private bus and keyring.
void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();
  tearDownAll(() async {
    await BackendService.instance.stop();
    await Hive.close();
    await LinuxProfileOwnership.current?.close();
  });
  testWidgets('Linux production startup and imported reading', (tester) async {
    expect(Platform.isLinux, isTrue);
    final root = Directory(Platform.environment['FQAPP_EVIDENCE']!);
    Future<void> wait(bool Function() condition, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('Timeout: $label');
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    try {
      await const FlutterSecureKeyStorage().read(
        SecureKeyProvider.hiveBoxKeyName,
      );
      File('${root.path}/key-preflight.txt').writeAsStringSync(
        'Real Secret Service read completed (value not recorded)',
      );
    } catch (error) {
      File('${root.path}/key-preflight.txt').writeAsStringSync(
        'Real Secret Service read failed: ${error.runtimeType}',
      );
      rethrow;
    }
    await app.main();
    await wait(
      () => find.byType(HomePage).evaluate().isNotEmpty,
      'production startup gate/home',
    );
    File('${root.path}/startup.txt').writeAsStringSync(
      'Production HOME mounted after real Secret Service startup\n',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Linux startup with explicitly provisioned synthetic device key', (
    tester,
  ) async {
    // Separate fixture: this does not pass the failing fresh-profile acceptance.
    expect(
      Platform.environment['HOME'],
      startsWith('${Directory.systemTemp.path}/fqapp-acceptance-'),
    );
    final key = await SecureKeyProvider.instance.devicePoolKey(
      allowCreate: true,
    );
    expect(key, isNotNull);
    await app.main();
    final deadline = DateTime.now().add(const Duration(seconds: 40));
    while (find.byType(HomePage).evaluate().isEmpty) {
      if (DateTime.now().isAfter(deadline)) {
        fail('Provisioned profile home did not mount');
      }
      await tester.pump(const Duration(milliseconds: 100));
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    File(
      '${Platform.environment['FQAPP_EVIDENCE']}/provisioned-startup.txt',
    ).writeAsStringSync(
      'Production startup succeeded with a device key explicitly provisioned in the disposable Secret Service. Fresh-profile startup remains a separate failing acceptance.',
    );
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Linux synthetic file import and production reader', (
    tester,
  ) async {
    final root = Directory(Platform.environment['FQAPP_EVIDENCE']!);
    Future<void> wait(bool Function() condition, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('Timeout: $label');
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    final source = File('${root.path}/synthetic.txt');
    await source.writeAsString('第一章 开始\n隔离导入阅读验收正文。\n第二章 出发\n这是第二章。');
    final store = ImportedBookStore.instance;
    final book = await store.importBytes(
      fileName: 'synthetic.txt',
      bytes: Uint8List.fromList(await source.readAsBytes()),
    );
    final text = await store.chapterText(book.id, book.chapters.first.itemId);
    expect(text, contains('隔离导入阅读验收正文'));
    await tester.pumpWidget(
      MaterialApp(
        home: ReaderPage(
          bookId: book.id,
          title: book.title,
          chapters: book.chapters,
          startIndex: 0,
          localOnly: true,
          chapterLoader: (chapter) =>
              store.chapterText(book.id, chapter.itemId),
        ),
      ),
    );
    await wait(
      () => find
          .textContaining('隔离导入阅读验收正文', findRichText: true)
          .evaluate()
          .isNotEmpty,
      'production reader renders imported text',
    );
    File('${root.path}/reading.txt').writeAsStringSync(text);
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets('Linux real texture seek MPRIS and production entry', (
    tester,
  ) async {
    final root = Directory(Platform.environment['FQAPP_EVIDENCE']!);
    Future<void> wait(bool Function() condition, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('Timeout: $label');
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    if (PlatformChannels.invoke == null) {
      await DesktopPlatform.instance.initialize();
    }
    final fixture = await File(
      '/tmp/fqapp-runtime-evidence/fixture.mp4',
    ).readAsBytes();
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() => server.close(force: true));
    server.listen((request) async {
      final range = request.headers.value('range');
      final match = range == null
          ? null
          : RegExp(r'^bytes=(\d+)-(\d*)$').firstMatch(range);
      final start = match == null ? 0 : int.parse(match[1]!);
      final end = match == null || match[2]!.isEmpty
          ? fixture.length - 1
          : int.parse(match[2]!).clamp(0, fixture.length - 1);
      request.response.headers.contentType = ContentType('video', 'mp4');
      request.response.headers.set('accept-ranges', 'bytes');
      if (match != null) {
        request.response.statusCode = HttpStatus.partialContent;
        request.response.headers.set(
          'content-range',
          'bytes $start-$end/${fixture.length}',
        );
      }
      request.response.contentLength = end - start + 1;
      if (request.method != 'HEAD') {
        request.response.add(fixture.sublist(start, end + 1));
      }
      await request.response.close();
    });
    final fixtureUrl = 'http://127.0.0.1:${server.port}/fixture.mp4';
    final player = NativePlayer();
    addTearDown(player.dispose);
    var created = false;
    final creation = player.create(fixtureUrl, '').then((_) {
      created = true;
    });
    await wait(() => created, 'production media creation');
    await creation;
    await tester.pumpWidget(
      MaterialApp(
        home: SizedBox(
          width: 640,
          height: 480,
          child: DesktopPlatform.instance.videoSurface(player.textureId!),
        ),
      ),
    );
    // Keep rendering the real texture while the native play call is pending.
    var started = false;
    final starting = player.play().then((_) => started = true);
    await wait(() => started, 'production play acknowledgement');
    await starting;
    await wait(
      () => player.firstFrameRendered && player.position.inMilliseconds > 1200,
      'texture first frame and clock',
    );
    expect(player.videoWidth, 320);
    expect(player.videoHeight, 240);
    Future<String> mpris(String method, List<String> args) async {
      final result = await Process.run('gdbus', [
        'call',
        '--session',
        '--dest',
        'org.mpris.MediaPlayer2.fqapp',
        '--object-path',
        '/org/mpris/MediaPlayer2',
        '--method',
        method,
        ...args,
      ]);
      expect(result.exitCode, 0, reason: '${result.stderr}');
      return result.stdout as String;
    }

    final properties = await mpris('org.freedesktop.DBus.Properties.GetAll', [
      'org.mpris.MediaPlayer2.Player',
    ]);
    expect(properties, contains('Playing'));
    File('${root.path}/mpris.txt').writeAsStringSync(properties);
    await mpris('org.mpris.MediaPlayer2.Player.Pause', []);
    await wait(() => !player.playing, 'real MPRIS Pause callback');
    await mpris('org.mpris.MediaPlayer2.Player.Play', []);
    await wait(() => player.playing, 'real MPRIS Play callback');

    await player.setRate(1.0);
    await player.pause();
    await wait(() => !player.playing, 'pause');
    await player.seek(const Duration(seconds: 7));
    await wait(() => player.position.inMilliseconds >= 6500, 'paused seek');
    expect(player.playing, isFalse);
    await player.play();
    await wait(() => player.position.inMilliseconds > 8000, 'seek resume');
    File('${root.path}/media.json').writeAsStringSync(
      jsonEncode({
        'firstFrame': player.firstFrameRendered,
        'width': player.videoWidth,
        'height': player.videoHeight,
        'positionMs': player.position.inMilliseconds,
        'backend': Platform.environment['GDK_BACKEND'],
        'audio': 'ALSA null; not audible acceptance',
      }),
    );
    await player.dispose();
    expect(supportsVideoPlayback, isTrue);
    final entryPlayer = NativePlayer();
    addTearDown(entryPlayer.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: PlayerPage(
          bookId: 'linux-synthetic',
          title: '合成播放入口',
          eps: [Chapter(itemId: 'fixture', title: '第一集', volumeName: '')],
          startIndex: 0,
          historyStore: MemoryReaderStore(),
          playerFactory: () => entryPlayer,
          contentLoader: (_) async => {'video_url': fixtureUrl, 'key_hex': ''},
        ),
      ),
    );
    await wait(
      () =>
          entryPlayer.firstFrameRendered &&
          entryPlayer.position.inMilliseconds > 1000,
      'production PlayerPage entry first frame',
    );
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
    await tester.pump();
    expect(entryPlayer.playWhenReady, isTrue);
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.hidden);
    final pauseDeadline = DateTime.now().add(const Duration(seconds: 10));
    // A real hidden Flutter view stops frames; do not await pump until resumed.
    while (entryPlayer.playing) {
      if (DateTime.now().isAfter(pauseDeadline)) {
        fail('Hidden page did not pause');
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
    }
    tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
    await wait(
      () => entryPlayer.playing,
      'production page resumes automatic pause',
    );
    File('${root.path}/entry.txt').writeAsStringSync(
      'Linux getter, production PlayerPage first frame; injected inactive/hidden/resumed with real player',
    );
    await tester.pumpWidget(const SizedBox.shrink());
    await entryPlayer.dispose();
  });
  testWidgets('Linux native speech completion cancellation and disconnect', (
    tester,
  ) async {
    final root = Directory(Platform.environment['FQAPP_EVIDENCE']!);
    Future<void> wait(bool Function() condition, String label) async {
      final deadline = DateTime.now().add(const Duration(seconds: 40));
      while (!condition()) {
        if (DateTime.now().isAfter(deadline)) fail('Timeout: $label');
        await tester.pump(const Duration(milliseconds: 100));
        await Future<void>.delayed(const Duration(milliseconds: 100));
      }
    }

    final events = <Map>[];
    final subscription = SystemTts.events.listen((e) {
      if (e is Map) events.add(e);
      File('${root.path}/tts.json').writeAsStringSync(jsonEncode(events));
    });
    addTearDown(subscription.cancel);
    expect((await SystemTts.engines()).engines, isNotEmpty);
    for (final volume in [-0.01, 1.01, double.nan]) {
      await expectLater(
        const MethodChannel(
          'fqapp/system_tts',
        ).invokeMethod<int>('initialize', {'rate': 1.0, 'volume': volume}),
        throwsA(
          isA<PlatformException>().having(
            (e) => e.message,
            'message',
            contains('音量超出范围'),
          ),
        ),
      );
    }
    for (final volume in [0.0, 0.5, 1.0]) {
      expect(
        await SystemTts.initialize(SystemTtsPreferences(volume: volume)),
        4000,
      );
    }
    await SystemTts.initialize(const SystemTtsPreferences());
    await SystemTts.speak('这是隔离中文短句。', 'complete');
    await wait(
      () => events.any((e) => e['id'] == 'complete' && e['type'] == 'done'),
      'native TTS done',
    );
    expect(
      events.any((e) => e['id'] == 'complete' && e['type'] == 'start'),
      isTrue,
    );
    await SystemTts.speak(List.filled(30, '这是取消测试。').join(), 'cancel');
    await wait(
      () => events.any((e) => e['id'] == 'cancel' && e['type'] == 'start'),
      'native TTS start',
    );
    await SystemTts.stop();
    await Future<void>.delayed(const Duration(seconds: 2));
    expect(
      events.any((e) => e['id'] == 'cancel' && e['type'] == 'done'),
      isFalse,
    );
    await SystemTts.speak('这是取消后的新句子。', 'replacement');
    await wait(
      () => events.any((e) => e['id'] == 'replacement' && e['type'] == 'done'),
      'replacement utterance completes',
    );
    expect(
      events.any((e) => e['id'] == 'cancel' && e['type'] == 'done'),
      isFalse,
    );
    File('${root.path}/disconnect.request').writeAsStringSync(
      'Terminate only the speech daemon owned by the session harness',
    );
    await wait(
      () => events.any((e) => e['type'] == 'engine_stopped'),
      'native speech service disconnect',
    );
    await SystemTts.shutdown();
    File('${root.path}/tts.json').writeAsStringSync(jsonEncode(events));
    await tester.pumpWidget(const SizedBox.shrink());
  });
  testWidgets(
    'Linux native session capability and inhibit release diagnostics',
    (tester) async {
      const channel = MethodChannel('fqapp/desktop_session');
      final result = <String, dynamic>{
        'capabilities': await channel.invokeMapMethod<String, dynamic>(
          'capabilities',
        ),
      };
      try {
        await channel.invokeMethod<void>('setKeepScreenOn', {'on': true});
        result['inhibitRequest'] =
            'acknowledged; physical idle inhibition unverified';
      } on PlatformException catch (error) {
        result['inhibitRequestError'] = error.code;
      } finally {
        await channel.invokeMethod<void>('setKeepScreenOn', {'on': false});
        result['releaseAcknowledged'] = true;
      }
      File(
        '${Platform.environment['FQAPP_EVIDENCE']}/session-capabilities.json',
      ).writeAsStringSync(jsonEncode(result));
    },
  );
}
