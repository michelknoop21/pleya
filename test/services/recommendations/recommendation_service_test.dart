import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
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
