import 'app_database.dart';

/// Counters that keep a late memory write from landing after a wipe. Kept in
/// memory and static, like the recommendation epochs: the database object can
/// be rebuilt with the provider tree while a service of the old tree is still
/// finishing a call.
abstract final class AssistantMemoryEpochs {
  static final Map<String, int> _wipes = {};
  static final Map<String, int> _removals = {};

  /// Raised whenever the facts of [profileId] are wiped as a whole: by
  /// `MemoryService.clearAll` and by profile deletion.
  static int wipes(String profileId) => _wipes[profileId] ?? 0;

  /// Raised only when [profileId] is deleted. A service made before the
  /// deletion never writes again.
  static int removals(String profileId) => _removals[profileId] ?? 0;

  static void noteWipe(String profileId) => _wipes[profileId] = wipes(profileId) + 1;

  static void _noteRemoval(String profileId) {
    noteWipe(profileId);
    _removals[profileId] = removals(profileId) + 1;
  }
}

extension AssistantMemoryWipe on AppDatabase {
  /// Wipes the remembered facts and the written overview of a profile, in one
  /// transaction. The only memory query that takes a profile id: profile
  /// deletion also has to reach a profile that is not the active one.
  /// Everything else goes through `MemoryService`, which is bound to its own
  /// profile. The epochs move first, so a write that is still on its way
  /// finds them changed and stores nothing.
  Future<void> deleteAssistantMemoryForProfile(String profileId) {
    AssistantMemoryEpochs._noteRemoval(profileId);
    return transaction(() async {
      await (delete(assistantMemories)..where((t) => t.profileId.equals(profileId))).go();
      await (delete(assistantMemoryOverviews)..where((t) => t.profileId.equals(profileId))).go();
    });
  }
}
