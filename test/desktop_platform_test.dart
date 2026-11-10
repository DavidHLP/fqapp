import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:fqapp/services/desktop_platform.dart';
import 'package:fqapp/services/desktop_media.dart';
import 'package:fqapp/services/platform_channel.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/widgets/desktop_chapter_sidebar.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  tearDown(() {
    PlatformChannels.invoke = null;
    PlatformChannels.events = null;
  });

  test(
    'Linux core path is shared and independent of the working directory',
    () {
      final original = Directory.current;
      final elsewhere = Directory.systemTemp.createTempSync('fqapp-core-path-');
      try {
        final expected =
            '${File(Platform.resolvedExecutable).parent.path}'
            '/lib/libfqapi_core.so';
        expect(desktopCoreLibraryPath(), expected);
        Directory.current = elsewhere;
        expect(desktopCoreLibraryPath(), expected);
      } finally {
        Directory.current = original;
        elsewhere.deleteSync();
      }
    },
    skip: !Platform.isLinux,
  );

  test('platform adapters preserve typed bytes and errors', () async {
    final bytes = Uint8List.fromList([1, 2, 3]);
    PlatformChannels.invoke = (channel, method, args) async {
      expect(channel, 'fqapp/library_backup');
      if (method == 'openBackup') return bytes;
      throw PlatformException(code: 'cancelled');
    };
    const channel = AppMethodChannel('fqapp/library_backup');
    expect(await channel.invokeMethod<Uint8List>('openBackup'), same(bytes));
    await expectLater(
      channel.invokeMethod<void>('saveBackup'),
      throwsA(isA<PlatformException>()),
    );
  });

  test('TXT decoder preserves Unicode and UTF16 BOM', () {
    expect(
      decodeDesktopText(
        Uint8List.fromList([0xef, 0xbb, 0xbf, 0xe4, 0xb8, 0xad]),
      ),
      '中',
    );
    expect(
      decodeDesktopText(Uint8List.fromList([0xff, 0xfe, 0x2d, 0x4e])),
      '中',
    );
    expect(
      decodeDesktopText(Uint8List.fromList([0xfe, 0xff, 0x4e, 0x2d])),
      '中',
    );
  });

  test('TXT decoder rejects truncated UTF16 and malformed GB18030', () {
    expect(() => decodeDesktopText(Uint8List.fromList([255, 254, 45])),
        throwsFormatException);
    expect(() => decodeDesktopText(Uint8List.fromList([255, 254, 0, 216])),
        throwsFormatException);
    if (Platform.isLinux) {
      expect(decodeDesktopText(Uint8List.fromList([0xd6, 0xd0])), '中');
      expect(decodeDesktopText(Uint8List.fromList([0x95, 0x32, 0x82, 0x36])), '𠀀');
      expect(() => decodeDesktopText(Uint8List.fromList([0x81])),
          throwsFormatException);
    }
  });

  test('Linux native integrations bypass Windows adapters and retain failures', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    addTearDown(() => debugDefaultTargetPlatformOverride = null);
    final calls = <String>[];
    const channels = ['fqapp/system_tts', 'fqapp/fanqie_account',
      'fqapp/desktop_session', 'fqapp/native_player'];
    for (final name in channels) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), (call) async {
        calls.add('$name/${call.method}');
        throw PlatformException(code: 'unavailable');
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(MethodChannel(name), null));
    }
    for (final call in [
      ('fqapp/system_tts', 'initialize', <String, dynamic>{}),
      ('fqapp/fanqie_account', 'login', <String, dynamic>{}),
      ('fqapp/native_player', 'setKeepScreenOn', <String, dynamic>{'on': true}),
      ('fqapp/native_player', 'startListenForeground', <String, dynamic>{}),
    ]) {
      await expectLater(DesktopPlatform.instance.invoke(call.$1, call.$2, call.$3),
          throwsA(isA<PlatformException>()));
    }
    expect(calls, ['fqapp/system_tts/initialize', 'fqapp/fanqie_account/login',
      'fqapp/desktop_session/setKeepScreenOn', 'fqapp/native_player/startListenForeground']);
  });

  testWidgets(
    'desktop directory filters and selects original chapter indices',
    (tester) async {
      int? selected;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: DesktopChapterSidebar(
              chapters: [
                for (var i = 0; i < 5; i++)
                  Chapter(itemId: '$i', title: '第 $i 章', volumeName: ''),
              ],
              currentIndex: 2,
              onSelected: (index) => selected = index,
            ),
          ),
        ),
      );
      await tester.enterText(find.byType(TextField), '3');
      await tester.pump();
      expect(find.text('第 2 章'), findsNothing);
      await tester.tap(find.text('第 3 章'));
      expect(selected, 3);
    },
  );
}
