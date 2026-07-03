import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/database/app_database.dart';
import 'package:plezy/services/recommendations/affinity_engine.dart';

MediaInteractionsCompanion _row(
  String profile,
  String globalKey, {
  double weight = 1.0,
  List<String> genres = const [],
  int? occurredAt,
}) =>
    MediaInteractionsCompanion.insert(
      profileId: profile,
      globalKey: globalKey,
      mediaKind: 'movie',
      eventType: 'completed',
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
  });
}
