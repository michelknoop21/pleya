import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_recommend_constraints.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_trakt_services.dart';
import 'package:pleya/database/app_database.dart' show WatchedIdentity;
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/models/trakt/trakt_ids.dart';
import 'package:pleya/models/trakt/trakt_title.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/recommendations/taste_profile.dart';
import 'package:pleya/services/trakt/trakt_library_reader.dart';
import 'package:pleya/services/unified_catalog/home_custom_row_loader.dart';
import 'package:pleya/utils/external_ids.dart';

import 'assistant_find_fakes.dart';

TraktTitle _title(String title, int year, {String? imdb, int? tmdb, bool show = false}) => TraktTitle(
  title: title,
  year: year,
  ids: TraktIds(imdb: imdb, tmdb: tmdb),
  isShow: show,
  at: '2026-10-0${1 + year % 9}T00:00:00.000Z',
);

AssistantTool _tool(String name) => assistantTools.singleWhere((t) => t.name == name);

AssistantTraktServices _trakt({List<TraktTitle>? titles, bool available = true}) =>
    AssistantTraktServices(available: () => available, watchlist: () async => titles);

CatalogHomeCustomRowLoader _loader(MultiServerManager m, {Set<String> visibleLibraries = const {'films'}}) =>
    CatalogHomeCustomRowLoader(
      libraries: () => [
        for (final id in visibleLibraries)
          MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: id, kind: MediaKind.movie, serverId: 'jf'),
      ],
      isServerVisible: m.isServerVisible,
      hiddenLibraryKeys: () => const {},
      clientFor: m.getClient,
    );

AssistantToolContext _ctx(
  MultiServerManager m, {
  AssistantTraktServices? trakt,
  bool catalog = true,
  Set<String> visibleLibraries = const {'films'},
}) => AssistantToolContext(
  servers: m,
  trakt: trakt,
  catalog: catalog
      ? AssistantCatalogServices(
          rowLoader: _loader(m, visibleLibraries: visibleLibraries),
          profileId: 'p',
          activeProfileId: () => 'p',
        )
      : null,
);

Future<Map<String, Object?>> _run(AssistantToolContext ctx, [Map<String, Object?> args = const {}]) async =>
    (await _tool('trakt_watchlist').run(ctx, null, args) as AssistantToolResult).data;

Map<String, Object?> _row(Map<String, Object?> data, String title) =>
    ((data['titles'] as List).cast<Map<String, Object?>>()).singleWhere((r) => r['title'] == title);

void main() {
  late MultiServerManager manager;
  late FakeServer jf;

  setUp(() {
    manager = MultiServerManager();
    addTearDown(manager.dispose);
    jf = FakeServer(
      'jf',
      libraries: {
        'films': [fakeItem('m1', 'Dune', year: 2021, lib: 'films')],
        'privat': [fakeItem('m2', 'Hidden Gem', year: 2019, lib: 'privat')],
      },
      ids: {
        'm1': const ExternalIds(imdb: 'tt1160419', tmdb: 438631),
        'm2': const ExternalIds(imdb: 'tt9999999'),
      },
    );
    manager.debugRegisterClientForTesting(jf);
  });

  group('trakt_watchlist', () {
    test('in the library by id, not found when every server answered, hidden libraries do not count', () async {
      final ctx = _ctx(
        manager,
        trakt: _trakt(
          titles: [
            _title('Dune', 2021, imdb: 'tt1160419'),
            _title('Obscure Film', 2001, imdb: 'tt0000042'),
            _title('Hidden Gem', 2019, imdb: 'tt9999999'),
          ],
        ),
      );

      final data = await _run(ctx);

      expect(_row(data, 'Dune')['library_status'], 'in_library');
      expect(_row(data, 'Dune')['item_id'], 'm1');
      expect(_row(data, 'Dune')['server_id'], 'jf');
      expect(_row(data, 'Obscure Film')['library_status'], 'not_found_in_library');
      expect(_row(data, 'Hidden Gem')['library_status'], 'not_found_in_library');
      expect(() => ctx.requireShownItem(ServerId('jf'), 'm1'), returnsNormally);
    });

    test('a server that is offline makes a miss "not_checked", never "not found"', () async {
      final offline = FakeServer('nas', libraries: const {});
      manager.debugRegisterClientForTesting(offline, online: false);
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Obscure Film', 2001, imdb: 'tt0000042')]),
      );

      final data = await _run(ctx);

      expect(_row(data, 'Obscure Film')['library_status'], 'not_checked');
    });

    test('a title that is on the reachable server is still found while another is offline', () async {
      manager.debugRegisterClientForTesting(FakeServer('nas', libraries: const {}), online: false);
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Dune', 2021, imdb: 'tt1160419')]),
      );

      expect(_row(await _run(ctx), 'Dune')['library_status'], 'in_library');
    });

    test('without the catalog wiring nothing is looked up and nothing is called "missing"', () async {
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Dune', 2021, imdb: 'tt1160419')]),
        catalog: false,
      );

      final data = await _run(ctx);

      expect(_row(data, 'Dune')['library_status'], 'not_checked');
      expect(jf.identities, isEmpty);
    });

    test('titles beyond the lookup cap are listed as not_checked', () async {
      final titles = [for (var i = 0; i < 20; i++) _title('Film $i', 2000 + i, imdb: 'tt${1000000 + i}')];
      final data = await _run(_ctx(manager, trakt: _trakt(titles: titles)));

      final statuses = [for (final r in data['titles'] as List) (r as Map)['library_status']];
      expect(statuses.where((s) => s == 'not_checked'), hasLength(8));
      expect(jf.identities, hasLength(12));
    });

    test('kind filter keeps films or series only', () async {
      final ctx = _ctx(
        manager,
        trakt: _trakt(
          titles: [
            _title('Dune', 2021, imdb: 'tt1160419'),
            _title('Severance', 2022, show: true),
          ],
        ),
      );

      final shows = await _run(ctx, {'kind': 'show'});

      expect((shows['titles'] as List).map((r) => (r as Map)['title']), ['Severance']);
    });

    test('not linked, or switched off mid-ask, is trakt_not_connected', () async {
      var available = true;
      final trakt = AssistantTraktServices(
        available: () => available,
        watchlist: () async {
          available = false;
          return [_title('Dune', 2021, imdb: 'tt1160419')];
        },
      );

      await expectLater(
        _run(_ctx(manager, trakt: _trakt(available: false))),
        throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'trakt_not_connected')),
      );
      await expectLater(
        _run(_ctx(manager, trakt: trakt)),
        throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'trakt_not_connected')),
      );
    });

    test('Trakt that cannot be read is trakt_unreachable, not an empty watchlist', () async {
      await expectLater(
        _run(_ctx(manager, trakt: _trakt(titles: null))),
        throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'trakt_unreachable')),
      );
    });

    test('the tool is not offered without Trakt services and is blocked for kids', () {
      expect(_tool('trakt_watchlist').serves(AssistantToolContext(servers: manager), ServerId('jf')), isFalse);
      expect(kidsToolPolicy['trakt_watchlist'], KidsTool.blocked);
    });
  });

  group('Trakt in "seen"', () {
    test('Trakt is read only for a linked, non-kids, same profile with personalization on', () {
      bool ok({bool c = true, bool k = false, bool s = true, bool p = true}) =>
          assistantTraktAvailable(connected: c, kidsProfile: k, sameProfile: s, personalization: p);
      expect(ok(), isTrue);
      expect(ok(c: false), isFalse);
      expect(ok(k: true), isFalse);
      expect(ok(s: false), isFalse, reason: 'a turn that outlived a profile switch');
      expect(ok(p: false), isFalse, reason: 'personalization off');
    });

    test('AssistantTraktSeen: nothing when unavailable, completed-only leaves series out, flag follows use', () async {
      var available = false;
      final seen = AssistantTraktSeen(
        available: () => available,
        read: () async => TraktSeen(
          movies: [_title('Dune', 2021, imdb: 'tt1160419')],
          shows: [_title('Severance', 2022, show: true)],
        ),
      );
      expect(await seen.identities(), isEmpty);
      expect(seen.included, isFalse);

      available = true;
      expect((await seen.identities(completedOnly: true)).map((i) => i.show), [false]);
      expect((await seen.identities()).map((i) => i.show), [false, true]);
      expect(seen.included, isTrue);
    });

    test('my_watching leaves out a pick the user watched on Trakt and says so', () async {
      final dune = MediaItem(
        id: 'p1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Dune',
        year: 2021,
        serverId: 'jf',
        raw: const {
          'ProviderIds': {'Imdb': 'tt1160419'},
        },
      );
      final other = MediaItem(
        id: 'p2',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Arrival',
        year: 2016,
        serverId: 'jf',
        raw: const {
          'ProviderIds': {'Imdb': 'tt2543164'},
        },
      );
      final trakt = AssistantTraktSeen(
        available: () => true,
        read: () async => TraktSeen(movies: [_title('Dune', 2021, imdb: 'tt1160419')]),
      );
      final ctx = AssistantToolContext(
        servers: manager,
        personal: AssistantPersonalServices(
          userName: 'Michel',
          recent: () async => const [],
          everSeen: () async => const {},
          everSeenIdentities: () async => <WatchedIdentity>[...await trakt.identities()],
          seenIncludesTrakt: () => trakt.included,
          taste: () async => AffinityVector.empty,
          picks: (_) async => [
            MediaHub(id: 'h', title: 'Voor jou', type: 'movie', items: [dune, other]),
          ],
        ),
      );

      ctx.recommend = const AssistantRecommendConstraints(excludeWatched: true);
      final data = (await _tool('my_watching').run(ctx, null, const {}) as AssistantToolResult).data;

      final titles = [
        for (final row in data['picks'] as List)
          for (final t in (row as Map)['titles'] as List) (t as Map)['title'],
      ];
      expect(titles, ['Arrival']);
      expect(data['seen_includes_trakt'], isTrue);
    });
  });
}
