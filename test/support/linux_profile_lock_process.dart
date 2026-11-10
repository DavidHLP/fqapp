import 'dart:io';

import 'package:fqapp/services/linux_profile_ownership.dart';

Future<void> main(List<String> arguments) async {
  try {
    final owner = await LinuxProfileOwnership.acquire(
      Directory(arguments[0]),
      keyNamespaceDirectory: Directory(arguments[1]),
    );
    stdout.writeln('owned');
    if (arguments.contains('hold')) await stdin.first;
    await owner.close();
  } catch (_) {
    exitCode = 23;
  }
}
