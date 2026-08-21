import 'dart:convert';

import 'package:drift/drift.dart' show Value;

import '../../database/app_database.dart';
import '../../utils/app_logger.dart';
import 'taste_profile.dart';

/// Turns the local [MediaInteractions] history into a cached [AffinityVector]
/// per profile. The snapshot is a pure derivative of the log, so it is safe to
/// recompute whenever the interaction count drifts from what the snapshot was
/// built from.
class AffinityEngine {
  final AppDatabase _db;

  AffinityEngine(this._db);

  /// The stored form of an enabled-import-server set. Sorted so the same set
  /// always produces the same key, and joined with a character that cannot
  /// appear in a Plex machine identifier.
  static String enabledKeyFor(Set<String> enabledImportServerIds) {
    final ids = enabledImportServerIds.toList()..sort();
    return ids.join(',');
  }

  /// Returns the profile's taste vector, recomputing (and caching) only when
  /// the stored snapshot is missing or stale.
  ///
  /// [enabledImportServerIds] names the servers whose imported history may
  /// count. Everything else imported is excluded without being deleted, which
  /// is what the admin policy toggle and disconnecting both come down to.
  /// [nowMs] is injectable for deterministic tests.
  Future<AffinityVector> vectorFor(
    String profileId, {
    Set<String> enabledImportServerIds = const {},
    int? nowMs,
  }) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final enabledKey = enabledKeyFor(enabledImportServerIds);
    final currentCount = await _db.countMediaInteractions(profileId, enabledImportServerIds: enabledImportServerIds);
    if (currentCount == 0) return AffinityVector.empty;

    // Three things can stale a snapshot. The count catches new rows. The newest
    // timestamp catches rotation at the retention cap, where the count stays
    // pinned. The enabled key catches a policy change, which moves neither.
    final latestAt = await _db.latestInteractionAt(profileId, enabledImportServerIds: enabledImportServerIds);
    final snapshot = await _db.getAffinitySnapshot(profileId);
    final fresh =
        snapshot != null &&
        snapshot.eventCount == currentCount &&
        latestAt <= snapshot.computedAt &&
        snapshot.enabledKey == enabledKey;
    if (fresh) {
      try {
        final decoded = jsonDecode(snapshot.vectorJson) as Map<String, dynamic>;
        if (decoded['v'] == AffinityVector.schemaVersion) {
          return AffinityVector.fromJson(decoded);
        }
        appLogger.i('AffinityEngine: snapshot predates the current vector shape, recomputing');
      } catch (e) {
        appLogger.w('AffinityEngine: corrupt snapshot for $profileId, recomputing', error: e);
      }
    }

    final vector = await _recompute(profileId, now, enabledImportServerIds);
    await _db.upsertAffinitySnapshot(
      AffinitySnapshotsCompanion.insert(
        profileId: profileId,
        vectorJson: jsonEncode(vector.toJson()),
        eventCount: currentCount,
        computedAt: now,
        enabledKey: Value(enabledKey),
      ),
    );
    return vector;
  }

  Future<AffinityVector> _recompute(String profileId, int nowMs, Set<String> enabledImportServerIds) async {
    final rows = await _db.getMediaInteractions(profileId, enabledImportServerIds: enabledImportServerIds);
    final events = [
      for (final row in rows)
        TasteEvent(
          weight: row.eventWeight,
          occurredAtMs: row.occurredAt,
          // Episodes roll up to their series so a binge saturates as one title;
          // anything else is evidence about itself. A legacy episode row with
          // rich metadata has no series key and falls back to its own key,
          // which is the pre-rollup behaviour and ages out with the retention
          // window.
          evidenceKey: row.seriesKey ?? row.globalKey,
          genres: _decodeList(row.genresJson),
          actors: _decodeList(row.actorsJson),
          directors: _decodeList(row.directorsJson),
          moods: _decodeList(row.moodsJson),
          studio: row.studio,
          year: row.year,
        ),
    ];
    return AffinityVector.build(events, nowMs: nowMs);
  }

  static List<String> _decodeList(String json) {
    try {
      final decoded = jsonDecode(json);
      return decoded is List ? [for (final e in decoded) '$e'] : const [];
    } catch (_) {
      return const [];
    }
  }
}
