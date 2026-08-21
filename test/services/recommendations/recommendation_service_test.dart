import 'dart:async';

import 'package:drift/native.dart';
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/services/recommendations/personalized_rows_builder.dart';
import 'package:pleya/services/recommendations/recommendation_service.dart';
import 'package:pleya/services/recommendations/tautulli_history_importer.dart';
import 'package:pleya/services/settings_service.dart';

import '../../test_helpers/prefs.dart';

final _titles = PersonalizedRowTitles(
  topPicks: 'Top Picks',
  becauseYouLike: (g) => 'Because you like $g',
  hiddenGems: 'Hidden Gems',
);

/// Stands in for the real importer so the service's own logic is what is under
/// test: which servers it visits and what it does with the answer.
class _FakeImporter implements TautulliHistoryImporter {
  final TautulliImportOutcome? outcome;
  final Object? throws;
  int syncs = 0;

  _FakeImporter({this.outcome, this.throws});

  @override
  Future<TautulliImportOutcome?> sync() async {
    syncs++;
    if (throws != null) throw throws!;
    return outcome;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Enough of a client for [RecommendationService.buildRows] to get past its
/// "no clients, no rows" guard. Every catalogue call throws, which the pool
/// swallows into an empty pool — the rows are not what these tests measure.
class _FakeClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('pms-1');

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
  });
  tearDown(() async => db.close());

  RecommendationService service({Set<String> enabled = const {}, TautulliImporterFactory? factory}) =>
      RecommendationService(
        profileId: 'p1',
        database: db,
        titles: _titles,
        enabledImportServerIds: () => enabled,
        importerFactory: factory,
      );

  group('syncImportedHistory', () {
    test('does nothing without an importer factory', () async {
      expect(await service(enabled: const {'srvA'}).syncImportedHistory(), isFalse);
    });

    test('does nothing when no server is enabled', () async {
      var built = 0;
      final result = await service(
        factory: (_, _) {
          built++;
          return _FakeImporter() as TautulliHistoryImporter;
        },
      ).syncImportedHistory();
      expect(result, isFalse);
      expect(built, 0, reason: 'no configuration means no work and no network');
    });

    test('reports false when nothing new arrived', () async {
      final importer = _FakeImporter(outcome: const TautulliImportOutcome(fetched: 5, deduplicated: 5));
      expect(await service(enabled: const {'srvA'}, factory: (_, _) => importer).syncImportedHistory(), isFalse);
      expect(importer.syncs, 1);
    });

    test('reports true when rows were imported', () async {
      final importer = _FakeImporter(outcome: const TautulliImportOutcome(imported: 3));
      expect(await service(enabled: const {'srvA'}, factory: (_, _) => importer).syncImportedHistory(), isTrue);
    });

    test('a concurrent sync (null outcome) is not new data', () async {
      expect(await service(enabled: const {'srvA'}, factory: (_, _) => _FakeImporter()).syncImportedHistory(), isFalse);
    });

    test('visits every enabled server and reports true if any produced rows', () async {
      final visited = <String>[];
      final result = await service(
        enabled: const {'srvA', 'srvB'},
        factory: (_, serverId) {
          visited.add(serverId.toString());
          return _FakeImporter(outcome: serverId == ServerId('srvB') ? const TautulliImportOutcome(imported: 1) : null);
        },
      ).syncImportedHistory();
      expect(visited.toSet(), {'srvA', 'srvB'});
      expect(result, isTrue);
    });

    test('a refused binding (null importer) is skipped', () async {
      expect(await service(enabled: const {'srvA'}, factory: (_, _) => null).syncImportedHistory(), isFalse);
    });

    test('one failing server never takes the others down', () async {
      final result = await service(
        enabled: const {'srvA', 'srvB'},
        factory: (_, serverId) => serverId == ServerId('srvA')
            ? _FakeImporter(throws: Exception('boom'))
            : _FakeImporter(outcome: const TautulliImportOutcome(imported: 2)),
      ).syncImportedHistory();
      expect(result, isTrue);
    });

    test('the settings gate wins over everything', () async {
      await SettingsService.instance.write(SettingsService.personalizedRecommendations, false);
      var built = 0;
      final result = await service(
        enabled: const {'srvA'},
        factory: (_, _) {
          built++;
          return _FakeImporter(outcome: const TautulliImportOutcome(imported: 5));
        },
      ).syncImportedHistory();
      expect(result, isFalse);
      expect(built, 0);
    });
  });

  group('cold start', () {
    /// The whole point of the readiness seam, as one scenario: Discover wins
    /// the race against the integration store, so the first rows are built as
    /// if nothing were paired. Everything below is what has to happen next
    /// without the user touching anything.
    test('a saved integration hydrating after the first build still imports, exactly once', () async {
      final hydration = Completer<void>();
      var enabled = <String>{};
      var factoryCalls = 0;
      // Deliberately *not* new data: a warm profile has everything already, and
      // this is exactly the case that used to leave the rows scored without it.
      final importer = _FakeImporter(outcome: const TautulliImportOutcome(fetched: 4, deduplicated: 4));
      final s = RecommendationService(
        profileId: 'p1',
        database: db,
        titles: _titles,
        enabledImportServerIds: () => enabled,
        importSourcesReady: () => hydration.future,
        importerFactory: (_, _) {
          factoryCalls++;
          return importer;
        },
      );

      // 1. The rows render immediately, from whatever is known.
      await s.buildRows([_FakeClient()]);
      expect(factoryCalls, 0, reason: 'building rows never imports');

      // 2. The sync waits instead of concluding that nothing is paired.
      var finished = false;
      final pass = s.syncImportedHistory().then((v) {
        finished = true;
        return v;
      });
      await pumpEventQueue();
      expect(finished, isFalse, reason: 'hydration has not answered yet');
      expect(factoryCalls, 0);

      // 3. Hydration lands with a saved, enabled integration.
      enabled = {'pms-1'};
      hydration.complete();

      // 4. It imports once, and asks for a rebuild even though no row was new,
      //    because the rows on screen were scored without this server.
      expect(await pass, isTrue);
      expect(importer.syncs, 1);
      expect(factoryCalls, 1);

      // 5. Once the rows have been rebuilt with the server in scope, a further
      //    pass is quiet again.
      await s.buildRows([_FakeClient()]);
      expect(await s.syncImportedHistory(), isFalse);
      expect(importer.syncs, 2);
    });

    test('two readiness notifications do not start two imports', () async {
      final hydration = Completer<void>();
      final importer = _FakeImporter(outcome: const TautulliImportOutcome(imported: 1));
      final s = RecommendationService(
        profileId: 'p1',
        database: db,
        titles: _titles,
        enabledImportServerIds: () => const {'pms-1'},
        importSourcesReady: () => hydration.future,
        importerFactory: (_, _) => importer,
      );

      final first = s.syncImportedHistory();
      final second = s.syncImportedHistory();
      hydration.complete();
      expect(await first, isTrue);
      expect(await second, isTrue);
      expect(importer.syncs, 1, reason: 'one pass, shared by both callers');

      // And the guard releases: a later pass runs again.
      expect(await s.syncImportedHistory(), isTrue);
      expect(importer.syncs, 2);
    });

    test('a server that turns up mid-pass gets its own pass rather than being dropped', () async {
      // The other half of the single-flight guard. Coalescing is right for two
      // notifications about the same state; it is wrong when the second call
      // exists *because* the state moved, which is exactly what a second
      // server hydrating looks like.
      final hydration = Completer<void>();
      var enabled = <String>{'srvA'};
      final visited = <String>[];
      final s = RecommendationService(
        profileId: 'p1',
        database: db,
        titles: _titles,
        enabledImportServerIds: () => enabled,
        importSourcesReady: () => hydration.future,
        importerFactory: (_, serverId) {
          visited.add(serverId.toString());
          return _FakeImporter(outcome: const TautulliImportOutcome(imported: 1));
        },
      );

      final first = s.syncImportedHistory();
      enabled = {'srvA', 'srvB'};
      final second = s.syncImportedHistory();
      hydration.complete();
      await first;
      await second;

      expect(visited, containsAll(['srvA', 'srvB']));
    });

    test('a repeated notification about the same state costs no extra pass', () async {
      final importer = _FakeImporter(outcome: const TautulliImportOutcome(imported: 1));
      final hydration = Completer<void>();
      final s = RecommendationService(
        profileId: 'p1',
        database: db,
        titles: _titles,
        enabledImportServerIds: () => const {'srvA'},
        importSourcesReady: () => hydration.future,
        importerFactory: (_, _) => importer,
      );

      final calls = [for (var i = 0; i < 5; i++) s.syncImportedHistory()];
      hydration.complete();
      await Future.wait(calls);
      expect(importer.syncs, 1, reason: 'five notifications, one unchanged answer, one pass');
    });

    test('a readiness signal that fails is not allowed to block the import', () async {
      final importer = _FakeImporter(outcome: const TautulliImportOutcome(imported: 1));
      final s = RecommendationService(
        profileId: 'p1',
        database: db,
        titles: _titles,
        enabledImportServerIds: () => const {'pms-1'},
        importSourcesReady: () => Future<void>.error(StateError('store unreadable')),
        importerFactory: (_, _) => importer,
      );
      expect(await s.syncImportedHistory(), isTrue);
      expect(importer.syncs, 1);
    });

    test('readiness that never answers is bounded, and the import still runs', () {
      fakeAsync((async) {
        final importer = _FakeImporter(outcome: const TautulliImportOutcome(imported: 1));
        final s = RecommendationService(
          profileId: 'p1',
          database: db,
          titles: _titles,
          enabledImportServerIds: () => const {'pms-1'},
          importSourcesReady: () => Completer<void>().future,
          importerFactory: (_, _) => importer,
        );

        bool? result;
        unawaited(s.syncImportedHistory().then((v) => result = v));
        async.elapse(kImportSourcesReadyTimeout - const Duration(seconds: 1));
        async.flushMicrotasks();
        expect(result, isNull, reason: 'still waiting, on purpose');

        async.elapse(const Duration(seconds: 2));
        async.flushMicrotasks();
        expect(result, isTrue);
        expect(importer.syncs, 1);
      });
    });
  });

  group('buildRows', () {
    test('the settings gate yields no rows', () async {
      await SettingsService.instance.write(SettingsService.personalizedRecommendations, false);
      expect(await service().buildRows([]), isEmpty);
    });

    test('no clients yields no rows', () async {
      expect(await service().buildRows([]), isEmpty);
    });
  });
}
