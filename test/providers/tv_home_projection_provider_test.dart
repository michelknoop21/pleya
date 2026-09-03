/// Fase 6 (hoofdstuk 9.5 of docs/tvos-unified-experience.md, DEC-067): the TV
/// Home hero's slide list — `TvHomeProjectionProvider` re-projects whatever
/// `DiscoverProvider` already fetched through `HomeProjectionService` and
/// dedupes it through `FeaturedSelector`, never re-fetching and never
/// re-ranking on its own.
///
/// Hero *presentation* stays fase 8's; this file covers what the hero
/// rotates over, not how it looks. `test/screens/discover_screen_tv_hero_test.dart`
/// covers the same contract end-to-end through the real screen.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/utils/external_ids.dart';

import '../test_helpers/prefs.dart';

MediaItem _movie(String id, {String? title, int? year, String? guid, String serverId = 'server_1'}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title ?? id,
  year: year,
  guid: guid,
  serverId: serverId,
  serverName: serverId,
);

MediaHub _hub(String id, {required List<MediaItem> items, String serverId = 'server_1'}) => MediaHub(
  id: id,
  identifier: id,
  title: id,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: serverId,
  serverName: 'Server',
);

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaItem> Function() latestMoviesResult = () => const [];
  List<MediaItem> Function() onDeckResult = () => const [];
  List<MediaHub> Function() hubsResult = () => const [];

  /// Feeds `DiscoverProvider._latestShowsHub`. Non-empty here on purpose in
  /// the skip-guard tests: it is what flips `DiscoverProvider.hubs` from
  /// returning its raw field to allocating a fresh list on every read, which
  /// is the production shape and the one an `identical()` guard silently
  /// failed on.
  List<MediaItem> Function() latestShowsResult = () => const [];

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: latestMoviesResult(), succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: onDeckResult(), succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<OnDeckAggregationResult> getLatestShowsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: latestShowsResult(), succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubsResult(), succeededServerIds: serverIds ?? const {'server_1'});
}

class _FakeClient implements MediaServerClient {
  _FakeClient({String serverId = 'server_1'}) : serverId = ServerId(serverId);

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Same polling shape `tv_discovery_landing_provider_test.dart` uses: a
/// microtask-only yield, since this is a plain `test`, not `testWidgets`,
/// and a real `Timer` never fires without a widget binding to pump it.
Future<void> _settle(TvHomeProjectionProvider provider) async {
  for (var i = 0; i < 50 && provider.isProjecting; i++) {
    await Future<void>.value();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeAggregationService aggregation;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider discover;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider();
    discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
  });

  tearDown(() {
    discover.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
  });

  TvHomeProjectionProvider makeHome() => TvHomeProjectionProvider(
    discover: discover,
    multiServer: multiServer,
    continueWatchingTitle: 'Continue Watching',
    latestMoviesTitle: 'Recently Released',
  );

  test('FeaturedSelector output becomes heroGroups for real latestMovies input', () async {
    aggregation.latestMoviesResult = () => [_movie('m1', title: 'Recent One'), _movie('m2', title: 'Recent Two')];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups, hasLength(2));
    home.dispose();
  });

  test('recent-released order from DiscoverProvider.latestMovies is preserved exactly', () async {
    // getLatestMoviesFromAllServers already sorts by release date descending
    // (data_aggregation_service.dart) — this provider must not re-rank it.
    aggregation.latestMoviesResult = () => [
      _movie('m1', title: 'Newest', year: 2026),
      _movie('m2', title: 'Middle', year: 2025),
      _movie('m3', title: 'Oldest', year: 2020),
    ];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups.map((g) => g.representativeSource.item.title), ['Newest', 'Middle', 'Oldest']);
    home.dispose();
  });

  test('same primary input yields the same relevant ordering on a second projection', () async {
    aggregation.latestMoviesResult = () => [_movie('m1', title: 'A'), _movie('m2', title: 'B')];
    final home = makeHome();
    await discover.load();
    await _settle(home);
    final first = home.heroGroups.map((g) => g.groupId).toList();

    // A second, unrelated notification (e.g. a hubs-only refresh) re-runs the
    // projection; the same primary input must land in the same order.
    aggregation.hubsResult = () => [];
    await discover.load();
    await _settle(home);

    expect(home.heroGroups.map((g) => g.groupId).toList(), first);
    home.dispose();
  });

  test('the same title on two servers is one featured slide, not two', () async {
    aggregation.latestMoviesResult = () => [
      _movie('m1-a', title: 'Dune', guid: 'plex://movie/dune', serverId: 'server_1'),
      _movie('m1-b', title: 'Dune', guid: 'plex://movie/dune', serverId: 'server_2'),
    ];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups, hasLength(1));
    expect(home.heroGroups.single.sources, hasLength(2));
    home.dispose();
  });

  // DEC-067: hubs never pad a non-empty hero. Dedup is allowed to shrink the
  // rotation; filling the gap with Top Picks would make the billboard claim
  // "newly out" about titles that are not.
  test('one recent film plus available Top Picks yields a hero of exactly that film', () async {
    aggregation.latestMoviesResult = () => [_movie('m1', title: 'Primary One')];
    aggregation.hubsResult = () => [
      _hub(
        'top-picks',
        items: [
          _movie('h1', title: 'Top Pick One'),
          _movie('h2', title: 'Top Pick Two'),
        ],
      ),
    ];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups.map((g) => g.representativeSource.item.title), ['Primary One']);
    expect(home.hubs, isNotEmpty, reason: 'the hubs still exist — they are simply not hero content');
    home.dispose();
  });

  test('dedup shrinking eight concrete films to five logical ones yields a hero of five', () async {
    aggregation.latestMoviesResult = () => [
      // Three titles that each exist twice, on two servers, under one guid —
      // the exact case the pre-DEC-067 hero showed twice.
      for (final title in ['Dune', 'Arrival', 'Sicario'])
        for (final server in ['server_1', 'server_2'])
          _movie('$title-$server', title: title, guid: 'plex://movie/$title', serverId: server),
      _movie('solo-a', title: 'Solo A', guid: 'plex://movie/solo-a'),
      _movie('solo-b', title: 'Solo B', guid: 'plex://movie/solo-b'),
    ];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups, hasLength(5));
    expect(home.heroGroups.map((g) => g.representativeSource.item.title), [
      'Dune',
      'Arrival',
      'Sicario',
      'Solo A',
      'Solo B',
    ], reason: 'release order survives the dedup');
    home.dispose();
  });

  test('a hero with no eligible recent film is empty rather than padded from hubs', () async {
    // Every recent "film" is unreleased metadata, so FeaturedSelector rejects
    // all of them; hoofdstuk 9.5's fallback is DiscoverScreen's on-deck/hub
    // billboard, not a hub-filled rotation claiming to be new releases.
    aggregation.latestMoviesResult = () => [_movie('m1', title: 'Next Year', year: DateTime.now().year + 3)];
    aggregation.hubsResult = () => [
      _hub('top-picks', items: [_movie('h1', title: 'Top Pick One')]),
    ];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups, isEmpty);
    expect(home.hasProjectedHero, isTrue, reason: 'empty is an answer here, not an unfinished load');
    expect(home.projectedLatestMovies, same(discover.latestMovies));
    home.dispose();
  });

  test('hasProjectedHero and projectedLatestMovies separate "still loading" from "no eligible film"', () async {
    aggregation.latestMoviesResult = () => [_movie('m1', title: 'Recent One')];
    final home = makeHome();

    expect(home.hasProjectedHero, isFalse);
    expect(home.projectedLatestMovies, isNull);

    await discover.load();
    await _settle(home);

    expect(home.hasProjectedHero, isTrue);
    expect(home.projectedLatestMovies, same(discover.latestMovies));
    home.dispose();
  });

  test('featuredGroupFor matches a candidate by any of its sources, not only the representative', () async {
    aggregation.latestMoviesResult = () => [
      _movie('m1-a', title: 'Dune', guid: 'plex://movie/dune', serverId: 'server_1'),
      _movie('m1-b', title: 'Dune', guid: 'plex://movie/dune', serverId: 'server_2'),
    ];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    final group = home.heroGroups.single;
    final nonRepresentative = group.sources.firstWhere((s) => s.sourceKey != group.representativeSourceKey);

    expect(home.featuredGroupFor(nonRepresentative.item)?.groupId, group.groupId);
    expect(home.featuredGroupFor(_movie('unrelated', title: 'Not Featured')), isNull);
    home.dispose();
  });

  test('twelve recent films cap the hero at hoofdstuk 9.5s eight, and the rest stay activation-safe', () async {
    // `latestMovies` can hold up to 12 (data_aggregation_service.dart's own
    // cap); `FeaturedSelector.maxCount` is hoofdstuk 9.5's upper bound of 8.
    // That is a cap on the *rotation*, not a filter on what may be shown: an
    // item past it never becomes a hero slide, but rail focus can still put
    // it in the billboard, so `featuredGroupFor` must still name its group.
    aggregation.latestMoviesResult = () => [for (var i = 1; i <= 12; i++) _movie('m$i', title: 'Movie $i')];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups, hasLength(8), reason: 'the hero rotation stays at maxCount');
    expect(home.featuredGroupFor(_movie('m9', title: 'Movie 9')), isNotNull);
    expect(home.featuredGroupFor(_movie('m12', title: 'Movie 12')), isNotNull);
    home.dispose();
  });

  // Point 14 of the fase-6 correction: the reference-identity skip guard is
  // only allowed to stay if a meaningful change to each input it watches
  // still reprojects. Each of these would silently stop working if the guard
  // watched the wrong thing — and `unansweredServerIds` is a *computed* Set,
  // so it needed a different comparison than the three wholesale-replaced
  // lists.
  group('projection skip guard', () {
    test('a latestMovies change reprojects', () async {
      aggregation.latestMoviesResult = () => [_movie('m1', title: 'First')];
      final home = makeHome();
      await discover.load();
      await _settle(home);
      expect(home.heroGroups.single.representativeSource.item.title, 'First');

      aggregation.latestMoviesResult = () => [_movie('m2', title: 'Second')];
      await discover.load();
      await _settle(home);

      expect(home.heroGroups.single.representativeSource.item.title, 'Second');
      home.dispose();
    });

    test('an onDeck change reprojects', () async {
      aggregation.onDeckResult = () => [_movie('cw1', title: 'On Deck One')];
      final home = makeHome();
      await discover.load();
      await _settle(home);
      expect(home.continueWatching?.groups, hasLength(1));

      aggregation.onDeckResult = () => [_movie('cw1', title: 'On Deck One'), _movie('cw2', title: 'On Deck Two')];
      await discover.load();
      await _settle(home);

      expect(home.continueWatching?.groups, hasLength(2));
      home.dispose();
    });

    test('a hubs change reprojects', () async {
      aggregation.hubsResult = () => [
        _hub('top-picks', items: [_movie('h1', title: 'Pick One')]),
      ];
      final home = makeHome();
      await discover.load();
      await _settle(home);
      expect(home.hubs.single.groups, hasLength(1));

      aggregation.hubsResult = () => [
        _hub(
          'top-picks',
          items: [
            _movie('h1', title: 'Pick One'),
            _movie('h2', title: 'Pick Two'),
          ],
        ),
      ];
      await discover.load();
      await _settle(home);

      expect(home.hubs.single.groups, hasLength(2));
      home.dispose();
    });

    test('an unansweredServerIds change reprojects even when the three lists are untouched', () async {
      // `unansweredServerIds` is derived, not stored: it is
      // `onlineServerIds` minus the servers that fully answered. Registering
      // a second online server that has not answered changes what
      // `failedServerIds` the projection must carry, while `latestMovies`,
      // `onDeck` and `hubs` all keep their exact identity — the one case a
      // pure `identical()` guard skipped, leaving rows claiming every source
      // answered when one had not.
      aggregation.latestMoviesResult = () => [_movie('m1', title: 'Recent One')];
      final home = makeHome();
      await discover.load();
      await _settle(home);

      final beforeLatestMovies = discover.latestMovies;
      final beforeOnDeck = discover.onDeck;
      final beforeHubs = discover.hubs;
      expect(discover.unansweredServerIds, isEmpty);

      var reprojected = false;
      home.addListener(() => reprojected = true);

      multiServer.serverManager.debugRegisterClientForTesting(_FakeClient(serverId: 'server_2'));
      discover.notifyListeners();
      await _settle(home);

      expect(discover.unansweredServerIds, contains('server_2'), reason: 'precondition: the input really changed');
      expect(identical(discover.latestMovies, beforeLatestMovies), isTrue);
      expect(identical(discover.onDeck, beforeOnDeck), isTrue);
      expect(identical(discover.hubs, beforeHubs), isTrue);
      expect(reprojected, isTrue);
      home.dispose();
    });

    test('a notification that touches none of the inputs does not reproject', () async {
      aggregation.latestMoviesResult = () => [_movie('m1', title: 'Recent One')];
      final home = makeHome();
      await discover.load();
      await _settle(home);

      var reprojected = false;
      home.addListener(() => reprojected = true);

      discover.notifyListeners();
      await _settle(home);

      expect(reprojected, isFalse);
      home.dispose();
    });

    test('the guard still holds when DiscoverProvider.hubs allocates a fresh list per read', () async {
      // The production shape, and the one the first version of this guard
      // silently failed on: with a latest-shows hub present,
      // `DiscoverProvider.hubs` stops returning its raw field and builds a new
      // list on every read, so `identical()` was permanently false and the
      // guard never fired once.
      aggregation.latestMoviesResult = () => [_movie('m1', title: 'Recent One')];
      aggregation.latestShowsResult = () => [
        MediaItem(
          id: 's1',
          backend: MediaBackend.plex,
          kind: MediaKind.show,
          title: 'A Series',
          serverId: 'server_1',
          serverName: 'server_1',
        ),
      ];
      final home = makeHome();
      await discover.load();
      await _settle(home);

      expect(
        identical(discover.hubs, discover.hubs),
        isFalse,
        reason: 'precondition: the getter really does allocate per read here',
      );
      expect(home.heroGroups, hasLength(1));

      var reprojected = false;
      home.addListener(() => reprojected = true);

      discover.notifyListeners();
      await _settle(home);

      expect(reprojected, isFalse, reason: 'a fresh list of unchanged hubs is not a change');
      home.dispose();
    });

    test('a hubs change still reprojects when the getter allocates', () async {
      aggregation.latestShowsResult = () => [
        MediaItem(
          id: 's1',
          backend: MediaBackend.plex,
          kind: MediaKind.show,
          title: 'A Series',
          serverId: 'server_1',
          serverName: 'server_1',
        ),
      ];
      aggregation.hubsResult = () => [
        _hub('top-picks', items: [_movie('h1', title: 'Pick One')]),
      ];
      final home = makeHome();
      await discover.load();
      await _settle(home);
      final before = home.hubs.firstWhere((h) => h.groups.isNotEmpty).groups.length;
      expect(before, 1);

      aggregation.hubsResult = () => [
        _hub(
          'top-picks',
          items: [
            _movie('h1', title: 'Pick One'),
            _movie('h2', title: 'Pick Two'),
          ],
        ),
      ];
      await discover.load();
      await _settle(home);

      expect(home.hubs.firstWhere((h) => h.groups.length > 1).groups, hasLength(2));
      home.dispose();
    });
  });

  test('featuredGroupFor finds a Continue Watching item, even though CW is never a hero slide', () async {
    // Continue Watching is deliberately excluded from FeaturedSelector's
    // input (hoofdstuk 9.5 never lists it as a hero candidate — it's its own
    // rail, not hero content). But DiscoverScreen's own hero fallback chain
    // can still show an on-deck item as the billboard (e.g. an empty
    // latestMovies library), and that item must still resolve to a group for
    // source-safe activation.
    aggregation.latestMoviesResult = () => const [];
    aggregation.onDeckResult = () => [_movie('cw1', title: 'On Deck Title')];
    final home = makeHome();
    await discover.load();
    await _settle(home);

    expect(home.heroGroups, isEmpty, reason: 'CW is never a hero slide');
    expect(home.continueWatching, isNotNull);
    expect(home.featuredGroupFor(_movie('cw1', title: 'On Deck Title')), isNotNull);
    home.dispose();
  });
}
