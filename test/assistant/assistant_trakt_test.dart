import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_recommend_constraints.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/assistant/assistant_trakt_services.dart';
import 'package:pleya/database/app_database.dart' show WatchedIdentity;
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_identity.dart';
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
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import 'assistant_find_fakes.dart';

TraktTitle _title(String title, int year, {String? imdb, int? tmdb, bool show = false}) => TraktTitle(
  title: title,
  year: year,
  ids: TraktIds(imdb: imdb, tmdb: tmdb),
  isShow: show,
  at: '2026-10-0${1 + year % 9}T00:00:00.000Z',
);

AssistantTool _tool(String name) => assistantTools.singleWhere((t) => t.name == name);

AssistantTraktServices _trakt({List<TraktTitle>? titles, String? blocked}) =>
    AssistantTraktServices(blocked: () => blocked, watchlist: () async => titles);

class _FailingSearch extends FakeServer {
  _FailingSearch(super.id);
  @override
  Future<List<MediaItem>> searchItems(String query, {int limit = 100}) async => throw StateError('search failed');
}

/// A Pleya Server as the real client behaves: it can prove a title only by a
/// TMDB number, and says "cannot tell" by throwing otherwise (never by
/// answering an empty list).
class _PleyaServer extends FakeServer {
  _PleyaServer(super.id);
  @override
  MediaBackend get backend => MediaBackend.pleyaServer;

  @override
  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async {
    if (identity.externalIds.tmdb == null) throw StateError('Pleya Server needs a TMDB number');
    return const [];
  }
}

CatalogHomeCustomRowLoader _loader(MultiServerManager m, {Set<String> visibleLibraries = const {'films'}}) =>
    CatalogHomeCustomRowLoader(
      libraries: () => [
        for (final server in const ['jf', 'jf2'])
          for (final id in visibleLibraries)
            MediaLibrary(id: id, backend: MediaBackend.jellyfin, title: id, kind: MediaKind.movie, serverId: server),
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

    test('a full title search page is no proof of absence: not_checked', () async {
      final busy = FakeServer(
        'busy',
        libraries: {
          'films': [for (var i = 0; i < 25; i++) fakeItem('d$i', 'Dune Part $i', year: 1990 + i, lib: 'films')],
        },
      );
      manager.debugRegisterClientForTesting(busy);
      // "Dune" (2020, another id) is not on any server, but busy's title
      // search for it is full: not confirmed. "Obscure Film" gets a short page.
      final data = await _run(
        _ctx(
          manager,
          trakt: _trakt(
            titles: [
              _title('Dune', 2020, imdb: 'tt0000099'),
              _title('Obscure Film', 2001, imdb: 'tt0000042'),
            ],
          ),
        ),
      );
      expect(_row(data, 'Dune')['library_status'], 'not_checked');
      expect(_row(data, 'Obscure Film')['library_status'], 'not_found_in_library');
    });

    test('a hit on a server that answered still wins next to a server that cannot answer by identity', () async {
      manager.debugRegisterClientForTesting(_PleyaServer('ps'));
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Dune', 2021, imdb: 'tt1160419')]),
      );

      expect(_row(await _run(ctx), 'Dune')['library_status'], 'in_library');
    });

    test('Trakt listing a title twice is one row; a title on two servers is one card', () async {
      manager.debugRegisterClientForTesting(
        FakeServer(
          'jf2',
          libraries: {
            'films': [fakeItem('x1', 'Dune', year: 2021, lib: 'films')],
          },
          ids: {'x1': const ExternalIds(imdb: 'tt1160419')},
        ),
      );
      final ctx = _ctx(
        manager,
        trakt: _trakt(
          titles: [
            _title('Dune', 2021, imdb: 'tt1160419'),
            _title('Dune', 2021, imdb: 'tt1160419'),
          ],
        ),
      );

      final result = await _tool('trakt_watchlist').run(ctx, null, const {}) as AssistantToolResult;

      expect((result.data['titles'] as List), hasLength(1));
      expect(((result.data['titles'] as List).single as Map)['servers'], hasLength(2));
      expect((result.display! as AssistantMediaGrid).entries, hasLength(1));
    });

    test('a failing title search is "not_checked", never "not found"', () async {
      final flaky = _FailingSearch('flaky');
      manager.debugRegisterClientForTesting(flaky);
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Obscure Film', 2001, imdb: 'tt0000042')]),
      );

      expect(_row(await _run(ctx), 'Obscure Film')['library_status'], 'not_checked');
    });

    test('a cancelled ask leaves every title "not_checked"', () async {
      final cancel = AbortController()..abort();
      final ctx = AssistantToolContext(
        servers: manager,
        trakt: _trakt(titles: [_title('Obscure Film', 2001, imdb: 'tt0000042')]),
        cancel: cancel,
        catalog: AssistantCatalogServices(rowLoader: _loader(manager), profileId: 'p', activeProfileId: () => 'p'),
      );

      expect(_row(await _run(ctx), 'Obscure Film')['library_status'], 'not_checked');
    });

    test('a Pleya Server that cannot prove the title (no TMDB number) makes a miss "not_checked"', () async {
      manager.debugRegisterClientForTesting(_PleyaServer('ps'));
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Obscure Film', 2001, imdb: 'tt0000042')]),
      );

      expect(_row(await _run(ctx), 'Obscure Film')['library_status'], 'not_checked');
    });

    test('a Pleya Server that was asked by TMDB number and does not hold the title is a real miss', () async {
      manager.debugRegisterClientForTesting(_PleyaServer('ps'));
      final ctx = _ctx(
        manager,
        trakt: _trakt(titles: [_title('Obscure Film', 2001, imdb: 'tt0000042', tmdb: 4242)]),
      );

      expect(_row(await _run(ctx), 'Obscure Film')['library_status'], isNot('not_checked'));
    });

    test('Trakt linked but personalization off says so, not "not connected"', () async {
      await expectLater(
        _run(_ctx(manager, trakt: _trakt(blocked: 'trakt_personalization_off'))),
        throwsA(isA<AssistantToolError>().having((e) => e.code, 'code', 'trakt_personalization_off')),
      );
    });

    test('series are not pushed out by newer films: the kind filter comes before the cap', () async {
      final films = [for (var i = 0; i < 35; i++) _title('Film $i', 2000 + i, imdb: 'tt${2000000 + i}')];
      final ctx = _ctx(manager, trakt: _trakt(titles: [...films, _title('Severance', 2022, show: true)]));

      final shows = await _run(ctx, {'kind': 'show'});

      expect((shows['titles'] as List).map((r) => (r as Map)['title']), ['Severance']);
      expect(shows['trakt_entries_read'], 1);
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
      String? block;
      final trakt = AssistantTraktServices(
        blocked: () => block,
        watchlist: () async {
          block = 'trakt_not_connected';
          return [_title('Dune', 2021, imdb: 'tt1160419')];
        },
      );

      await expectLater(
        _run(_ctx(manager, trakt: _trakt(blocked: 'trakt_not_connected'))),
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
    test('the block reason names the cause', () {
      String? why({bool c = true, bool k = false, bool s = true, bool p = true}) =>
          assistantTraktBlock(connected: c, kidsProfile: k, sameProfile: s, personalization: p);
      expect(why(), isNull);
      expect(why(c: false), 'trakt_not_connected');
      expect(why(k: true), 'trakt_not_available');
      expect(why(s: false), 'trakt_not_available');
      expect(why(p: false), 'trakt_personalization_off');
    });

    test('Trakt is read only for a linked, non-kids, same profile with personalization on', () {
      bool ok({bool c = true, bool k = false, bool s = true, bool p = true}) =>
          assistantTraktBlock(connected: c, kidsProfile: k, sameProfile: s, personalization: p) == null;
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
      expect(seen.unavailable, isFalse, reason: 'not allowed is not "could not be read"');

      available = true;
      expect((await seen.identities(completedOnly: true)).map((i) => i.show), [false]);
      expect((await seen.identities()).map((i) => i.show), [false, true]);
      expect(seen.included, isTrue);
    });

    test('allowed but unreadable Trakt is flagged, so "unseen" is not read as complete', () async {
      var recovered = false;
      final seen = AssistantTraktSeen(available: () => true, read: () async => null);
      expect(await seen.identities(), isEmpty);
      expect(seen.unavailable, isTrue);
      expect(seen.included, isFalse);

      // It recovers: the flag follows the last read, not the first failure.
      final recovering = AssistantTraktSeen(
        available: () => true,
        read: () async => recovered ? TraktSeen(movies: [_title('Dune', 2021, imdb: 'tt1160419')]) : null,
      );
      expect(await recovering.identities(), isEmpty);
      expect(recovering.unavailable, isTrue);
      recovered = true;
      expect(await recovering.identities(), isNotEmpty);
      expect(recovering.unavailable, isFalse);
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
