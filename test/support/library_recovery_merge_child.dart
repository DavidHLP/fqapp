import 'dart:convert';
import 'dart:io';
import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter/foundation.dart';
import 'package:fqapp/models/library_backup.dart';
import 'package:fqapp/models/media_item.dart';
import 'package:fqapp/services/library_backup_service.dart';
import 'package:fqapp/services/library_store.dart';
import 'package:fqapp/services/shelf_store.dart';
import 'package:fqapp/services/shelf_group_store.dart';
import 'package:fqapp/services/linux_library_recovery.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:fqapp/services/ai_reading/ai_backup.dart';
import 'package:fqapp/services/ai_reading/ai_models.dart';
import 'package:fqapp/services/ai_reading/ai_store.dart';
import 'package:hive_ce/hive.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'library_backup_fixture.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test('isolated recovery worker', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.linux;
    final root = Directory(Platform.environment['RECOVERY_TEST_ROOT']!);
    final mode = Platform.environment['RECOVERY_TEST_MODE']!;
    SharedPreferences.setMockInitialValues({});
    Future<void> barrier(String point) async {
      if (mode != point) return;
      File(
        '${root.path}/barrier',
      ).writeAsStringSync('$pid:$point', flush: true);
      await Future<void>.delayed(const Duration(hours: 1));
    }

    Future<void> init() async {
      await LibraryStore.instance.init();
      await ShelfStore.instance.init();
      await ShelfGroupStore.instance.init();
    }

    final profile = Directory('${root.path}/profile');
    if (mode == 'seed') {
      final owner = await openBackupFixture(profile);
      await init();
      await LibraryStore.instance.addHistory({
        'id': 'same',
        'kind': 'book',
        'chapterId': 'local-new',
        'position': 99.5,
      });
      await ShelfStore.instance.add(
        MediaItem(
          id: 'same',
          title: 'local title',
          cover: '',
          author: '',
          badge: '',
          ep: '',
          kind: 'book',
        ),
      );
      await AiStore.instance.init();
      await AiStore.instance.putPrompt(
        AiPromptRecord(
          promptId: 'p1',
          revision: 2,
          source: 'user',
          text: 'local-new',
          hash: 'local-hash',
          createdAt: DateTime(2026),
          active: false,
        ),
      );
      final payload = AiBackupPayload(
        feedback: [],
        prompts: [
          for (final id in ['p1', 'p2', 'p3'])
            AiPromptRecord(
              promptId: id,
              revision: 1,
              source: 'user',
              text: 'prompt-$id',
              hash: 'hash-$id',
              createdAt: DateTime(2026),
            ),
        ],
        candidates: [],
        trials: [],
        trialResults: [],
        usage: [],
        pending: [],
        createdAt: DateTime(2026),
      );
      final backup = LibraryBackup.capture(
        shelf: [
          ShelfRecord(
            item: MediaItem(
              id: 'new',
              title: 'incoming',
              cover: '',
              author: '',
              badge: '',
              ep: '',
              kind: 'book',
            ),
            addedAt: DateTime(2020),
          ),
          ShelfRecord(
            item: MediaItem(
              id: 'same',
              title: 'old title',
              cover: '',
              author: '',
              badge: '',
              ep: '',
              kind: 'book',
            ),
            addedAt: DateTime(2020),
          ),
        ],
        history: [
          {'id': 'same', 'kind': 'book', 'chapterId': 'old', 'position': 1.0},
          {'id': 'new', 'kind': 'book', 'chapterId': 'ch-2', 'position': 31.5},
        ],
        watched: {
          'series': {'ep': 100},
        },
        groups: {
          'version': 1,
          'groups': {
            'g1-a': {'name': 'read', 'at': 1, 'deleted': false},
          },
          'assignments': {
            'book:new': {'group': 'g1-a', 'at': 1},
          },
        },
        aiData: base64Encode(
          GZipEncoder().encode(utf8.encode(jsonEncode(payload.toJson()))),
        ),
      );
      LinuxLibraryRecovery.schedule(owner, backup.encode());
      File('${root.path}/source.json').writeAsBytesSync(backup.encode());
      await Hive.close();
      await owner.close();
      return;
    }
    final owner = await LinuxProfileOwnership.acquire(
      profile,
      keyNamespaceDirectory: profile,
    );
    if (mode == 'inspect') {
      await openExisting(profile);
      final observed = <String, Object?>{};
      for (final file in profile.listSync().whereType<File>()) {
        final name = file.uri.pathSegments.last;
        if (name.endsWith('_enc.hive')) {
          final boxName = name.substring(0, name.length - 5);
          observed[boxName] = Hive.box<dynamic>(
            boxName,
          ).toMap().map((key, value) => MapEntry(key.toString(), value));
        }
      }
      File(
        '${root.path}/observed.json',
      ).writeAsStringSync(jsonEncode(observed), flush: true);
      await Hive.close();
      await owner.close();
      return;
    }
    if (mode == 'verify-snapshot') {
      final record =
          jsonDecode(
                File('${profile.path}/.fqapp-restore.json').readAsStringSync(),
              )
              as Map;
      final snapshot = Directory(record['snapshot'] as String);
      expect(
        File('${snapshot.path}/source-backup.json').readAsBytesSync(),
        File('${root.path}/source.json').readAsBytesSync(),
      );
      Hive.init('${snapshot.path}/profile');
      final box = await Hive.openBox<dynamic>(
        'history_enc',
        encryptionCipher: HiveAesCipher(List.filled(32, 7)),
      );
      expect((box.get('same') as Map)['chapterId'], 'local-new');
      expect(box.get('new'), isNull);
      await Hive.close();
    } else {
      await LinuxLibraryRecovery.resume(
        owner: owner,
        boundary: barrier,
        merge: (bytes) async {
          await openExisting(profile);
          await init();
          final service = LibraryBackupService()..restoreBoundary = barrier;
          AiBackupService.instance.afterPromptCommit = () async {
            await Hive.box<dynamic>('ai_prompts_v1_enc').flush();
            await barrier('ai-partial');
          };
          await service.restore(LibraryBackup.decode(bytes));
          for (final file in profile.listSync().whereType<File>()) {
            final name = file.uri.pathSegments.last;
            if (name.endsWith('.hive') &&
                Hive.isBoxOpen(name.substring(0, name.length - 5))) {
              await Hive.box<dynamic>(
                name.substring(0, name.length - 5),
              ).flush();
            }
          }
        },
      );
      if (mode == 'verify') {
        await openExisting(profile);
        await init();
        final snapshot = await LibraryStore.instance.backupSnapshot();
        expect(
          snapshot.history.singleWhere((e) => e['id'] == 'same')['chapterId'],
          'local-new',
        );
        final incoming = snapshot.history.singleWhere((e) => e['id'] == 'new');
        expect(incoming['chapterId'], 'ch-2');
        expect(incoming['position'], 31.5);
        expect(snapshot.watched['series'], {'ep': 100});
        expect(ShelfStore.instance.records().map((e) => e.item.id).toSet(), {
          'same',
          'new',
        });
        expect(
          ShelfStore.instance
              .records()
              .singleWhere((e) => e.item.id == 'same')
              .item
              .title,
          'local title',
        );
        expect(
          ShelfStore.instance
              .records()
              .singleWhere((e) => e.item.id == 'new')
              .addedAt,
          DateTime(2020),
        );
        expect(
          ShelfGroupStore.instance.backupOrganization()['groups']['g1-a'],
          {'name': 'read', 'at': 1, 'deleted': false},
        );
        expect(
          ShelfGroupStore.instance
              .backupOrganization()['assignments']['book:new'],
          {'group': 'g1-a', 'at': 1},
        );
        await AiStore.instance.init();
        final prompts = await AiStore.instance.prompts();
        expect(prompts, hasLength(3));
        for (final prompt in prompts) {
          expect(
            prompt.text,
            prompt.promptId == 'p1' ? 'local-new' : 'prompt-${prompt.promptId}',
          );
          expect(
            prompt.hash,
            prompt.promptId == 'p1' ? 'local-hash' : 'hash-${prompt.promptId}',
          );
          expect(prompt.revision, prompt.promptId == 'p1' ? 2 : 1);
          expect(prompt.active, prompt.promptId != 'p1');
          expect(prompt.createdAt, DateTime(2026));
          expect(prompt.source, 'user');
        }
        await Hive.close();
      }
    }
    await owner.close();
  });
}

Future<void> openExisting(Directory directory) async {
  Hive.init(directory.path);
  for (final file in directory.listSync().whereType<File>()) {
    final name = file.uri.pathSegments.last;
    if (name.endsWith('_enc.hive')) {
      await Hive.openBox<dynamic>(
        name.substring(0, name.length - 5),
        encryptionCipher: HiveAesCipher(List.filled(32, 7)),
      );
    }
  }
}
