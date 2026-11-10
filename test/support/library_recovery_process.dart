import 'dart:io';
import 'dart:typed_data';

import 'package:fqapp/services/linux_library_recovery.dart';
import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:hive_ce/hive.dart';

Future<void> main(List<String> arguments) async {
  final root = Directory(arguments[0]);
  final owner = await LinuxProfileOwnership.acquire(
    root,
    keyNamespaceDirectory: Directory(arguments[1]),
  );
  Hive.init(root.path);
  if (arguments[2] == 'snapshot') {
    final box = await Hive.openBox<dynamic>(
      'history_enc',
      encryptionCipher: HiveAesCipher(List.filled(32, 7)),
    );
    await box.put('book:1', {'chapterId': 'old', 'position': 31.5});
    await Hive.close();
    File('${root.path}/local.epub').writeAsBytesSync([0, 1, 255]);
    final snapshot = LinuxLibraryRecovery.preserveClosedProfile(
      owner: owner,
      sourceBackup: Uint8List.fromList([123, 125]),
    );
    stdout.writeln(snapshot.path);
    // Test-only barrier after the real snapshot-ready durability boundary.
    // Parent kills us here; no teardown/ownership release is executed.
    await stdin.first;
  } else {
    final box = await Hive.openBox<dynamic>(
      'history_enc',
      encryptionCipher: HiveAesCipher(List.filled(32, 7)),
    );
    final entry = box.get('book:1') as Map;
    if (entry['chapterId'] != 'old' ||
        entry['position'] != 31.5 ||
        File('${root.path}/local.epub').readAsBytesSync().last != 255) {
      throw StateError('snapshot readback failed');
    }
    await Hive.close();
  }
  await owner.close();
}
