import 'dart:io';

import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:hive_ce/hive.dart';

Future<void> main(List<String> arguments) async {
  try {
    final owner = await LinuxProfileOwnership.acquire(
      Directory(arguments[0]),
      keyNamespaceDirectory: Directory(arguments[1]),
    );
    if (arguments.contains('hive-write') || arguments.contains('hive-read')) {
      Hive.init(owner.directory.path);
      final box = await Hive.openBox<String>(
        'synthetic_enc',
        encryptionCipher: HiveAesCipher(List.filled(32, 7)),
      );
      if (arguments.contains('hive-write')) {
        await box.put('record', 'retained');
      }
      if (box.get('record') != 'retained') {
        throw StateError('synthetic readback failed');
      }
      await Hive.close();
    }
    stdout.writeln('owned');
    if (arguments.contains('hold')) await stdin.first;
    await owner.close();
  } catch (_) {
    exitCode = 23;
  }
}
