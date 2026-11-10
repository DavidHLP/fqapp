import 'dart:convert';
import 'dart:io';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test(
    'fresh process SIGKILL recovery matrix with actual stores and fixed synthetic key',
    () async {
      final flutter =
          '${Platform.resolvedExecutable.split('/bin/cache/').first}/bin/flutter';
      for (final point in [
        'snapshot',
        'pending',
        'groups',
        'shelf',
        'history',
        'ai-partial',
        'before-complete',
        'complete',
      ]) {
        final root = await Directory.systemTemp.createTemp('fqapp-matrix-');
        Future<Process> launch(String mode) => Process.start(
          flutter,
          [
            'test',
            '--no-pub',
            '--reporter',
            'expanded',
            'test/support/library_recovery_merge_child.dart',
          ],
          environment: {
            'RECOVERY_TEST_ROOT': root.path,
            'RECOVERY_TEST_MODE': mode,
          },
        );
        Future<void> run(String mode) async {
          final child = await launch(mode);
          final out = child.stdout.transform(utf8.decoder).join();
          final err = child.stderr.transform(utf8.decoder).join();
          expect(
            await child.exitCode,
            0,
            reason: '$point/$mode: ${await out}\n${await err}',
          );
        }

        try {
          stdout.writeln('matrix $point');
          await run('seed');
          final child = await launch(point);
          final out = child.stdout.transform(utf8.decoder).join();
          final err = child.stderr.transform(utf8.decoder).join();
          final barrier = File('${root.path}/barrier');
          final deadline = DateTime.now().add(const Duration(seconds: 60));
          while (!barrier.existsSync() && DateTime.now().isBefore(deadline)) {
            await Future<void>.delayed(const Duration(milliseconds: 100));
          }
          if (!barrier.existsSync()) {
            child.kill();
            fail('$point failed to reach barrier: ${await out} ${await err}');
          }
          final enginePid = int.parse(
            barrier.readAsStringSync().split(':').first,
          );
          expect(Process.killPid(enginePid, ProcessSignal.sigkill), isTrue);
          child.kill(ProcessSignal.sigkill);
          await child.exitCode;
          await out.timeout(const Duration(seconds: 5), onTimeout: () => '');
          await err.timeout(const Duration(seconds: 5), onTimeout: () => '');
          final record =
              jsonDecode(
                    File(
                      '${root.path}/profile/.fqapp-restore.json',
                    ).readAsStringSync(),
                  )
                  as Map;
          expect(record['state'] == 'complete', point == 'complete');
          final preserved = <String, List<int>>{};
          for (final dir in root.listSync().whereType<Directory>().where(
            (e) => e.path.contains('.fqapp-before-restore-'),
          )) {
            for (final file
                in dir
                    .listSync(recursive: true)
                    .whereType<File>()
                    .where(
                      (f) =>
                          f.path.endsWith('.hive') ||
                          f.path.endsWith('source-backup.json'),
                    )) {
              preserved[file.path] = file.readAsBytesSync();
            }
          }
          await run('inspect');
          stdout.writeln(
            '$point persisted: ${File('${root.path}/observed.json').readAsStringSync()}',
          );
          await run('verify');
          await run('verify');
          await run('verify-snapshot');
          for (final entry in preserved.entries) {
            expect(
              File(entry.key).readAsBytesSync(),
              entry.value,
              reason: '$point original snapshot changed',
            );
          }
        } finally {
          await root.delete(recursive: true);
        }
      }
    },
    timeout: const Timeout(Duration(minutes: 15)),
  );
}
