import 'dart:convert';

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

  /// Returns the profile's taste vector, recomputing (and caching) only when
  /// the stored snapshot is missing or stale relative to the current row
  /// count. [nowMs] is injectable for deterministic tests.
  Future<AffinityVector> vectorFor(String profileId, {int? nowMs}) async {
    final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
    final currentCount = await _db.countMediaInteractions(profileId);
    if (currentCount == 0) return AffinityVector.empty;

    // Count alone is insufficient: at the retention cap the count stays pinned
    // while rows rotate, so also require the newest interaction to be no later
    // than when the snapshot was computed.
    final latestAt = await _db.latestInteractionAt(profileId);
    final snapshot = await _db.getAffinitySnapshot(profileId);
    final fresh = snapshot != null && snapshot.eventCount == currentCount && latestAt <= snapshot.computedAt;
    if (fresh) {
      try {
        return AffinityVector.fromJson(jsonDecode(snapshot.vectorJson) as Map<String, dynamic>);
      } catch (e) {
        appLogger.w('AffinityEngine: corrupt snapshot for $profileId, recomputing', error: e);
      }
    }

    final vector = await _recompute(profileId, now);
    await _db.upsertAffinitySnapshot(
      AffinitySnapshotsCompanion.insert(
        profileId: profileId,
        vectorJson: jsonEncode(vector.toJson()),
        eventCount: currentCount,
        computedAt: now,
      ),
    );
    return vector;
  }

  Future<AffinityVector> _recompute(String profileId, int nowMs) async {
    final rows = await _db.getMediaInteractions(profileId);
    final events = [
      for (final row in rows)
        TasteEvent(
          weight: row.eventWeight,
          occurredAtMs: row.occurredAt,
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
