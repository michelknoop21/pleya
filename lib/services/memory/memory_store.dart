import 'dart:convert';

import 'package:drift/drift.dart';

import '../../database/app_database.dart';

/// The memory tables as one profile sees them. Every statement here, by id
/// included, carries the profile of this instance in its WHERE clause, so a
/// row of another profile does not exist for it.
class MemoryStore {
  MemoryStore(this._db, this._profileId);

  final AppDatabase _db;
  final String _profileId;

  Future<T> transaction<T>(Future<T> Function() action) => _db.transaction(action);

  /// Newest change first.
  // On an equal change time the newest made goes first, then the id: an
  // arbitrary order between two facts of one millisecond, but a stable one.
  Future<List<AssistantMemoryRow>> all() =>
      (_db.select(_db.assistantMemories)
            ..where((t) => t.profileId.equals(_profileId))
            ..orderBy([
              (t) => OrderingTerm.desc(t.updatedAt),
              (t) => OrderingTerm.desc(t.createdAt),
              (t) => OrderingTerm.asc(t.id),
            ]))
          .get();

  Future<int> count() async {
    final amount = _db.assistantMemories.id.count();
    final query = _db.selectOnly(_db.assistantMemories)
      ..addColumns([amount])
      ..where(_db.assistantMemories.profileId.equals(_profileId));
    return (await query.getSingle()).read(amount) ?? 0;
  }

  Future<AssistantMemoryRow?> byId(String id) => (_db.select(
    _db.assistantMemories,
  )..where((t) => t.profileId.equals(_profileId) & t.id.equals(id))).getSingleOrNull();

  /// At most two rows whose id starts with [prefix]: enough to tell one match
  /// from several. [prefix] must hold no LIKE wildcard.
  Future<List<AssistantMemoryRow>> byIdPrefix(String prefix) =>
      (_db.select(_db.assistantMemories)
            ..where((t) => t.profileId.equals(_profileId) & t.id.like('$prefix%'))
            ..limit(2))
          .get();

  Future<AssistantMemoryRow?> byValueKey(String valueKey) => (_db.select(
    _db.assistantMemories,
  )..where((t) => t.profileId.equals(_profileId) & t.valueKey.equals(valueKey))).getSingleOrNull();

  Future<void> insert({
    required String id,
    required String category,
    required String value,
    required String valueKey,
    required String source,
    required int at,
  }) => _db
      .into(_db.assistantMemories)
      .insert(
        AssistantMemoriesCompanion.insert(
          id: id,
          profileId: _profileId,
          category: category,
          value: value,
          valueKey: valueKey,
          source: source,
          createdAt: at,
          updatedAt: at,
        ),
      );

  Future<int> update(
    String id, {
    required String category,
    required String value,
    required String valueKey,
    required String source,
    required int at,
  }) => (_db.update(_db.assistantMemories)..where((t) => t.profileId.equals(_profileId) & t.id.equals(id))).write(
    AssistantMemoriesCompanion(
      category: Value(category),
      value: Value(value),
      valueKey: Value(valueKey),
      source: Value(source),
      updatedAt: Value(at),
    ),
  );

  Future<int> deleteById(String id) =>
      (_db.delete(_db.assistantMemories)..where((t) => t.profileId.equals(_profileId) & t.id.equals(id))).go();

  /// Drops this profile's facts and its written overview.
  Future<void> deleteAll() async {
    await (_db.delete(_db.assistantMemories)..where((t) => t.profileId.equals(_profileId))).go();
    await deleteOverview();
  }

  /// Drops this profile's written overview. Called in the transaction of
  /// every change to its facts: the text was written from facts that are no
  /// longer the facts, and a removed fact must not stay on the device in it.
  Future<void> deleteOverview() =>
      (_db.delete(_db.assistantMemoryOverviews)..where((t) => t.profileId.equals(_profileId))).go();

  Future<AssistantMemoryOverviewRow?> overview() =>
      (_db.select(_db.assistantMemoryOverviews)..where((t) => t.profileId.equals(_profileId))).getSingleOrNull();

  Future<void> putOverview({
    required String factsHash,
    required String locale,
    required String status,
    required String body,
    required int at,
  }) => _db
      .into(_db.assistantMemoryOverviews)
      .insertOnConflictUpdate(
        AssistantMemoryOverviewsCompanion.insert(
          profileId: _profileId,
          factsHash: factsHash,
          locale: locale,
          status: status,
          body: body,
          generatedAt: at,
        ),
      );

  Future<Map<String, dynamic>?> syncState() async {
    final row = await (_db.select(
      _db.assistantMemorySyncStates,
    )..where((t) => t.profileId.equals(_profileId))).getSingleOrNull();
    return row == null ? null : jsonDecode(row.payload) as Map<String, dynamic>;
  }

  Future<void> putSyncState(Map<String, dynamic> state) => _db
      .into(_db.assistantMemorySyncStates)
      .insertOnConflictUpdate(
        AssistantMemorySyncStatesCompanion.insert(profileId: _profileId, payload: jsonEncode(state)),
      );

  Future<void> removeSyncState() =>
      (_db.delete(_db.assistantMemorySyncStates)..where((t) => t.profileId.equals(_profileId))).go();

  /// Called inside the same transaction as the edit, so a crash cannot lose a pending mutation.
  Future<void> noteSyncChange({bool clear = false}) async {
    final state = await syncState();
    if (state == null) return;
    state['generation'] = (state['generation'] as int) + 1;
    if (clear) {
      final known = (state['quarantine'] ?? state['base']) as Map<String, dynamic>;
      state['base'] = {'epoch': known['epoch'], 'revision': known['revision'], 'facts': <Object>[]};
      state['clearGeneration'] = state['generation'];
      state['conflicts'] = <Object>[];
      state['quarantine'] = null;
      state['inFlight'] = null;
      state['sentGeneration'] = null;
      state['excluded'] = <Object>[];
    }
    await putSyncState(state);
  }

  Future<void> replaceFacts(List<AssistantMemoriesCompanion> facts) async {
    await deleteAll();
    for (final fact in facts) {
      await _db.into(_db.assistantMemories).insert(fact);
    }
  }
}
