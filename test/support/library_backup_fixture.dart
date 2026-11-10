import 'dart:io';

import 'package:fqapp/services/linux_profile_ownership.dart';
import 'package:hive_ce/hive.dart';

/// Synthetic encrypted boxes bypass the production key provider entirely.
Future<LinuxProfileOwnership> openBackupFixture(Directory directory) async {
  final owner = await LinuxProfileOwnership.acquire(
    directory,
    keyNamespaceDirectory: directory,
  );
  Hive.init(directory.path);
  for (final name in [
    'history',
    'read_time',
    'watched_episodes',
    'shelf',
    'shelf_groups_v1',
    'ai_settings_v1',
    'ai_formal_v1',
    'ai_runs_v1',
    'ai_requests_v1',
    'ai_feedback_chapter_v1',
    'ai_prompts_v1',
    'ai_candidates_v1',
    'ai_trials_v1',
    'ai_trial_results_v1',
    'ai_usage_aggregate_v1',
    'ai_pending_bindings_v1',
    'ai_chapter_status_v1',
    'ai_meta_v1',
  ]) {
    await Hive.openBox<dynamic>(
      '${name}_enc',
      encryptionCipher: HiveAesCipher(List.filled(32, 7)),
    );
  }
  return owner;
}
