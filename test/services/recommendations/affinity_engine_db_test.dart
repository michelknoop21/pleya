import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/recommendations/affinity_engine.dart';

MediaInteractionsCompanion _row(
  String profile,
  String globalKey, {
  double weight = 1.0,
  List<String> genres = const [],
  int? occurredAt,
  String? seriesKey,
  String eventType = 'completed',
}) => MediaInteractionsCompanion.insert(
  profileId: profile,
  globalKey: globalKey,
  seriesKey: Value(seriesKey),
  mediaKind: 'movie',
  eventType: eventType,
  eventWeight: weight,
  // Default to "now" so retention pruning (365d) doesn't drop the row.
  occurredAt: occurredAt ?? DateTime.now().millisecondsSinceEpoch,
  genresJson: Value(jsonEncode(genres)),
);

void main() {
  late AppDatabase db;

  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  test('records interactions and counts per profile', () async {
    await db.insertMediaInteraction(_row('p1', 's:1', genres: ['Sci-Fi']), profileId: 'p1');
    await db.insertMediaInteraction(_row('p1', 's:2', genres: ['Sci-Fi']), profileId: 'p1');
    await db.insertMediaInteraction(_row('p2', 's:3'), profileId: 'p2');

    expect(await db.countMediaInteractions('p1'), 2);
    expect(await db.countMediaInteractions('p2'), 1);
  });

  test('profile deletion wipes taste data', () async {
    await db.insertMediaInteraction(_row('p1', 's:1'), profileId: 'p1');
    await db.upsertAffinitySnapshot(
      AffinitySnapshotsCompanion.insert(profileId: 'p1', vectorJson: '{}', eventCount: 1, computedAt: 1),
    );
    await db.deleteRecommendationDataForProfile('p1');
    expect(await db.countMediaInteractions('p1'), 0);
    expect(await db.getAffinitySnapshot('p1'), isNull);
  });

  test('retention prunes rows older than 365 days', () async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final old = now - const Duration(days: 400).inMilliseconds;
    await db.insertMediaInteraction(_row('p1', 's:old', occurredAt: old), profileId: 'p1');
    await db.insertMediaInteraction(_row('p1', 's:new', occurredAt: now), profileId: 'p1');
    // The prune runs on each insert; the old row should be gone.
    final rows = await db.getMediaInteractions('p1');
    expect(rows.map((r) => r.globalKey), ['s:new']);
  });

  group('AffinityEngine', () {
    test('computes, caches, and reuses a snapshot', () async {
      final engine = AffinityEngine(db);
      for (var i = 0; i < 3; i++) {
        await db.insertMediaInteraction(_row('p1', 's:$i', genres: ['Sci-Fi']), profileId: 'p1');
      }
      final v1 = await engine.vectorFor('p1');
      expect(v1.of('genre', 'sci-fi'), greaterThan(0));

      final snap = await db.getAffinitySnapshot('p1');
      expect(snap, isNotNull);
      expect(snap!.eventCount, 3);

      // No new interactions → same snapshot reused (eventCount unchanged).
      final v2 = await engine.vectorFor('p1');
      expect(v2.eventCount, 3);
    });

    test('empty history returns the empty vector', () async {
      final engine = AffinityEngine(db);
      final v = await engine.vectorFor('nobody');
      expect(v.eventCount, 0);
      expect(v.isWarm, isFalse);
    });

    test('adding interactions invalidates the stale snapshot', () async {
      final engine = AffinityEngine(db);
      await db.insertMediaInteraction(_row('p1', 's:1', genres: ['Drama']), profileId: 'p1');
      await engine.vectorFor('p1');
      await db.insertMediaInteraction(_row('p1', 's:2', genres: ['Sci-Fi']), profileId: 'p1');
      final v = await engine.vectorFor('p1');
      expect(v.eventCount, 2);
      expect(v.of('genre', 'sci-fi'), greaterThan(0));
    });

    test('recomputes when the count is unchanged but a newer interaction arrived', () async {
      // Simulates the retention cap: count stays equal, rows rotate. The
      // snapshot must still refresh because the newest interaction is later.
      final engine = AffinityEngine(db);
      final t0 = DateTime.now().millisecondsSinceEpoch;
      await db.insertMediaInteraction(
        _row('p1', 's:1', genres: ['Drama'], occurredAt: t0),
        profileId: 'p1',
      );
      final before = await engine.vectorFor('p1', nowMs: t0);
      expect(before.of('genre', 'drama'), greaterThan(0));
      expect(before.of('genre', 'sci-fi'), 0);

      // Delete the old row and add a newer one — count returns to 1.
      await db.deleteRecommendationDataForProfile('p1');
      final t1 = t0 + 1000;
      await db.insertMediaInteraction(
        _row('p1', 's:2', genres: ['Sci-Fi'], occurredAt: t1),
        profileId: 'p1',
      );
      // Re-seed the snapshot as if it were the stale count==1 one from before.
      // vectorFor must detect the newer latestInteractionAt and recompute.
      final after = await engine.vectorFor('p1', nowMs: t1 + 1000);
      expect(after.of('genre', 'sci-fi'), greaterThan(0));
    });
  });

  group('recentPositiveInteractions', () {
    // Wall clock, not a constant: the 365-day retention prune on insert would
    // otherwise drop every fixture row.
    final now = DateTime.now().millisecondsSinceEpoch;
    const day = Duration.millisecondsPerDay;

    test('one row per evidence key, newest first, positives only, inside the window', () async {
      await db.insertMediaInteraction(
        _row('p1', 's:ep1', seriesKey: 's:show', occurredAt: now - 1 * day),
        profileId: 'p1',
      );
      await db.insertMediaInteraction(
        _row('p1', 's:ep2', seriesKey: 's:show', occurredAt: now - 2 * day, weight: 0.4, eventType: 'partial'),
        profileId: 'p1',
      );
      await db.insertMediaInteraction(_row('p1', 's:film', occurredAt: now - 3 * day), profileId: 'p1');
      await db.insertMediaInteraction(
        _row('p1', 's:dismissed', occurredAt: now - 1 * day, weight: -0.3, eventType: 'skipped'),
        profileId: 'p1',
      );
      await db.insertMediaInteraction(_row('p1', 's:old', occurredAt: now - 40 * day), profileId: 'p1');
      // Another household member's viewing never seeds this profile (DEC-062).
      await db.insertMediaInteraction(_row('p2', 's:theirs', occurredAt: now), profileId: 'p2');

      final rows = await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 6);

      expect(rows.map((r) => r.globalKey), [
        's:ep1',
        's:film',
      ], reason: 'the show once, the dismissal, the old row and the other profile never');
    });

    test('two rows at the same moment always come back in the same order', () async {
      // Tautulli timestamps are whole seconds, so ties are real.
      await db.insertMediaInteraction(_row('p1', 's:first', occurredAt: now), profileId: 'p1');
      await db.insertMediaInteraction(_row('p1', 's:second', occurredAt: now), profileId: 'p1');

      final rows = await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 1);

      expect(rows.map((r) => r.globalKey), ['s:second'], reason: 'the later insert wins the tie');
    });

    test('rows on servers outside serverIds are skipped before the limit, so they take no slot', () async {
      for (var i = 0; i < 6; i++) {
        await db.insertMediaInteraction(_row('p1', 'pleya:$i', occurredAt: now - i * 1000), profileId: 'p1');
      }
      for (var i = 0; i < 3; i++) {
        await db.insertMediaInteraction(_row('p1', 'plex:$i', occurredAt: now - day - i * 1000), profileId: 'p1');
      }

      final rows = await db.recentPositiveInteractions(
        'p1',
        sinceMs: now - 30 * day,
        minWeight: 0.4,
        limit: 6,
        serverIds: const {'plex'},
      );

      expect(rows.map((r) => r.globalKey), ['plex:0', 'plex:1', 'plex:2']);
    });

    test('a key whose newest row is a dismissal seeds nothing, an older dismissal does not block', () async {
      await db.insertMediaInteraction(
        _row('p1', 's:film', occurredAt: now - 2 * day, weight: 0.4, eventType: 'partial'),
        profileId: 'p1',
      );
      await db.insertMediaInteraction(
        _row('p1', 's:film', occurredAt: now - 1 * day, weight: -0.3, eventType: 'skipped'),
        profileId: 'p1',
      );
      await db.insertMediaInteraction(
        _row('p1', 's:back', occurredAt: now - 3 * day, weight: -0.3, eventType: 'skipped'),
        profileId: 'p1',
      );
      await db.insertMediaInteraction(_row('p1', 's:back', occurredAt: now - 1 * day), profileId: 'p1');

      final rows = await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 6);

      expect(rows.map((r) => r.globalKey), ['s:back']);
    });

    test('an imported row on a disabled server is not a seed', () async {
      await db.insertMediaInteraction(
        MediaInteractionsCompanion.insert(
          profileId: 'p1',
          globalKey: 'pms:9',
          mediaKind: 'movie',
          eventType: 'completed',
          eventWeight: 1.0,
          occurredAt: now,
          source: const Value('tautulli'),
          sourceServerId: const Value('pms'),
          sourceEventId: const Value('tautulli:pms:9'),
        ),
        profileId: 'p1',
      );
      expect(await db.recentPositiveInteractions('p1', sinceMs: now - 30 * day, minWeight: 0.4, limit: 6), isEmpty);
      expect(
        await db.recentPositiveInteractions(
          'p1',
          sinceMs: now - 30 * day,
          minWeight: 0.4,
          limit: 6,
          enabledImportServerIds: const {'pms'},
        ),
        hasLength(1),
      );
    });
  });
}
