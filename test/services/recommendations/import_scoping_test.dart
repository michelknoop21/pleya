import 'dart:convert';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/services/recommendations/affinity_engine.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';

/// Real "now": the retention prune measures against the wall clock, so a fixed
/// historical timestamp would be deleted on insert.
final _now = DateTime.now().millisecondsSinceEpoch;

MediaInteractionsCompanion _local(
  String profile,
  String globalKey, {
  double weight = 1.0,
  List<String> genres = const ['Local'],
  int? occurredAt,
}) => MediaInteractionsCompanion.insert(
  profileId: profile,
  globalKey: globalKey,
  mediaKind: 'movie',
  eventType: 'completed',
  eventWeight: weight,
  occurredAt: occurredAt ?? _now,
  genresJson: Value(jsonEncode(genres)),
);

MediaInteractionsCompanion _imported(
  String profile,
  String globalKey, {
  required String serverId,
  List<String> genres = const ['Imported'],
  int? occurredAt,
  String? sourceServerIdOverride,
  bool nullServerId = false,
}) => MediaInteractionsCompanion.insert(
  profileId: profile,
  globalKey: globalKey,
  mediaKind: 'movie',
  eventType: 'completed',
  eventWeight: 1.0,
  occurredAt: occurredAt ?? _now,
  genresJson: Value(jsonEncode(genres)),
  source: const Value(kInteractionSourceTautulli),
  sourceEventId: Value('tautulli:$serverId:$globalKey'),
  sourceServerId: nullServerId ? const Value(null) : Value(sourceServerIdOverride ?? serverId),
);

void main() {
  late AppDatabase db;
  setUp(() => db = AppDatabase.forTesting(NativeDatabase.memory()));
  tearDown(() async => db.close());

  group('the scoring whitelist', () {
    setUp(() async {
      await db.insertImportedInteractions([
        _local('p1', 's1:local'),
        _imported('p1', 's1:a', serverId: 'srvA'),
        _imported('p1', 's1:b', serverId: 'srvB'),
        _imported('p1', 's1:orphan', serverId: 'srvA', nullServerId: true),
      ], profileId: 'p1');
    });

    test('an empty enabled set excludes every imported row and keeps local ones', () async {
      // The empty case must never produce a bare `IN ()`, which SQLite rejects.
      final rows = await db.getMediaInteractions('p1');
      expect(rows.map((r) => r.globalKey), ['s1:local']);
      expect(await db.countMediaInteractions('p1', enabledImportServerIds: const {}), 1);
      expect(await db.latestInteractionAt('p1'), _now);
    });

    test('only explicitly enabled servers count', () async {
      final rows = await db.getMediaInteractions('p1', enabledImportServerIds: const {'srvA'});
      expect(rows.map((r) => r.globalKey), ['s1:local', 's1:a']);
      expect(await db.countMediaInteractions('p1', enabledImportServerIds: const {'srvA'}), 2);
    });

    test('enabling both servers counts both', () async {
      expect(await db.countMediaInteractions('p1', enabledImportServerIds: const {'srvA', 'srvB'}), 3);
    });

    test('an imported row with a null server id is never counted', () async {
      for (final enabled in [
        const <String>{},
        const {'srvA'},
        const {'srvA', 'srvB'},
        const {'srvA', 'srvB', 'srvC'},
      ]) {
        final rows = await db.getMediaInteractions('p1', enabledImportServerIds: enabled);
        expect(rows.map((r) => r.globalKey), isNot(contains('s1:orphan')));
      }
    });

    test('an unknown server id in the enabled set changes nothing', () async {
      expect(await db.countMediaInteractions('p1', enabledImportServerIds: const {'srvZ'}), 1);
    });

    test('the unfiltered count is the storage count the retention cap uses', () async {
      expect(await db.countMediaInteractions('p1'), 4);
    });
  });

  group('AffinityEngine server scoping', () {
    late AffinityEngine engine;
    setUp(() {
      engine = AffinityEngine(db);
    });

    Future<void> seed() async {
      await db.insertImportedInteractions([
        _local('p1', 's1:local', genres: const ['Noir']),
        for (var i = 0; i < 3; i++) _imported('p1', 's1:a$i', serverId: 'srvA', genres: const ['Sci-Fi']),
      ], profileId: 'p1');
    }

    test('imported history counts only while its server is enabled', () async {
      await seed();

      final on = await engine.vectorFor('p1', enabledImportServerIds: const {'srvA'}, nowMs: _now);
      expect(on.of('genre', 'sci-fi'), greaterThan(0));
      expect(on.of('genre', 'noir'), greaterThan(0));

      final off = await engine.vectorFor('p1', nowMs: _now);
      expect(off.of('genre', 'sci-fi'), 0, reason: 'excluded, not deleted');
      expect(off.of('genre', 'noir'), greaterThan(0), reason: 'local always counts');
    });

    test('flipping the policy invalidates the snapshot immediately', () async {
      await seed();
      // Same row count and same newest timestamp in both states, so only the
      // enabled key can tell these two vectors apart.
      final on = await engine.vectorFor('p1', enabledImportServerIds: const {'srvA'}, nowMs: _now);
      final snapshotOn = await db.getAffinitySnapshot('p1');
      expect(snapshotOn!.enabledKey, 'srvA');

      final off = await engine.vectorFor('p1', nowMs: _now);
      final snapshotOff = await db.getAffinitySnapshot('p1');
      expect(snapshotOff!.enabledKey, '');
      expect(off.of('genre', 'sci-fi'), 0);

      final backOn = await engine.vectorFor('p1', enabledImportServerIds: const {'srvA'}, nowMs: _now);
      expect(backOn.of('genre', 'sci-fi'), closeTo(on.of('genre', 'sci-fi'), 1e-9));
      expect((await db.getAffinitySnapshot('p1'))!.enabledKey, 'srvA');
    });

    test('the enabled key is order independent', () {
      expect(AffinityEngine.enabledKeyFor(const {'b', 'a'}), AffinityEngine.enabledKeyFor(const {'a', 'b'}));
      expect(AffinityEngine.enabledKeyFor(const {}), '');
    });

    test('a snapshot from an older vector shape is recomputed', () async {
      await seed();
      await db.upsertAffinitySnapshot(
        AffinitySnapshotsCompanion.insert(
          profileId: 'p1',
          vectorJson: jsonEncode({
            'v': 1,
            'eventCount': 4,
            'dims': {
              'genre': {'stale': 1.0},
            },
          }),
          eventCount: 4,
          computedAt: _now + 1000,
          enabledKey: const Value('srvA'),
        ),
      );
      final vector = await engine.vectorFor('p1', enabledImportServerIds: const {'srvA'}, nowMs: _now);
      expect(vector.of('genre', 'stale'), 0);
      expect(vector.of('genre', 'sci-fi'), greaterThan(0));
    });

    test('imported episodes of one show saturate like local ones', () async {
      await db.insertImportedInteractions([
        for (var i = 0; i < 20; i++)
          MediaInteractionsCompanion.insert(
            profileId: 'p1',
            globalKey: 'srvA:show',
            mediaKind: 'episode',
            eventType: 'completed',
            eventWeight: 1.0,
            occurredAt: _now - i * 1000,
            genresJson: Value(jsonEncode(const ['Sci-Fi'])),
            seriesKey: const Value('srvA:show'),
            source: const Value(kInteractionSourceTautulli),
            sourceEventId: Value('tautulli:srvA:$i'),
            sourceServerId: const Value('srvA'),
          ),
        _imported('p1', 'srvA:control', serverId: 'srvA', genres: const ['Control']),
      ], profileId: 'p1');

      final vector = await engine.vectorFor('p1', enabledImportServerIds: const {'srvA'}, nowMs: _now);
      // One control title normalises to 1/kSeriesEvidenceCap of the binge.
      expect(1 / vector.of('genre', 'control'), closeTo(kSeriesEvidenceCap, 1e-6));
    });
  });
}
