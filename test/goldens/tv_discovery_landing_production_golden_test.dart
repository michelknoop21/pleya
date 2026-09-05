/// Fase 6 (hoofdstuk 10.2a of docs/tvos-unified-experience.md, [DEC-064]):
/// production visual acceptance for `TvMoviesLandingScreen` and
/// `TvSeriesLandingScreen`.
///
/// `test/goldens/tv_discovery_golden_test.dart` already proved the
/// composition — the rail, the tile, the view-all row — with a
/// `_landing()` test helper standing in for the real screen. This file is
/// the promotion hoofdstuk 27 fase 6 asks for once that composition has a
/// production landing to render it: the *same* pictures, but produced by
/// `TvMoviesLandingScreen`/`TvSeriesLandingScreen` themselves, fed by the
/// real `TvDiscoveryLandingProvider` projecting fixture `DiscoverProvider`
/// data through `HomeProjectionService` — not a fixture standing in for the
/// projected `UnifiedMediaGroup`s directly.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_discovery_landing_production_golden_test.dart`
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_discovery_landing_provider.dart';
import 'package:pleya/screens/tv/tv_movies_landing_screen.dart';
import 'package:pleya/screens/tv/tv_series_landing_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_view_all_action.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/tv_discovery_artwork.dart';

// `pleyaServer` and `local` never merge across sources (hoofdstuk 4.2's
// `_neverMergedBackends` in `grouping_service.dart`), so a fixture meant to
// prove a real three-source merge needs three genuinely poolable backends —
// two physical Plex servers and one Jellyfin, not a third backend that would
// silently cap the group at two no matter how many sources this list holds.
const _servers = [
  (id: 'nas', name: 'NAS', backend: MediaBackend.plex),
  (id: 'attic', name: 'Zolder', backend: MediaBackend.jellyfin),
  (id: 'garage', name: 'Garage', backend: MediaBackend.plex),
];

MediaItem _film({
  required String id,
  required String title,
  required TvDiscoveryMood mood,
  String genre = 'Drama',
  int year = 2023,
  String serverId = 'nas',
  String serverName = 'NAS',
  MediaBackend backend = MediaBackend.plex,
}) {
  final artwork = TvDiscoveryArtwork.indexOfMood(mood);
  return MediaItem(
    id: id,
    backend: backend,
    kind: MediaKind.movie,
    title: title,
    year: year,
    summary: '$title is a $genre film that gives the expanded discovery card real prose to lay out.',
    genres: [genre],
    durationMs: 110 * 60 * 1000,
    serverId: serverId,
    serverName: serverName,
    thumbPath: TvDiscoveryArtwork.pathFor(artwork),
    artPath: TvDiscoveryArtwork.widePathFor(artwork),
  );
}

MediaItem _show({
  required String id,
  required String title,
  required TvDiscoveryMood mood,
  String genre = 'Drama',
  int year = 2022,
  int childCount = 3,
}) {
  final artwork = TvDiscoveryArtwork.indexOfMood(mood);
  return MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: MediaKind.show,
    title: title,
    year: year,
    summary: '$title runs $childCount seasons of $genre, enough to give the context block real copy.',
    genres: [genre],
    childCount: childCount,
    serverId: 'nas',
    serverName: 'NAS',
    thumbPath: TvDiscoveryArtwork.pathFor(artwork),
    artPath: TvDiscoveryArtwork.widePathFor(artwork),
  );
}

MediaItem _episode({
  required String id,
  required String showTitle,
  required TvDiscoveryMood mood,
  required int season,
  required int episode,
}) {
  final artwork = TvDiscoveryArtwork.indexOfMood(mood);
  return MediaItem(
    id: id,
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'The Return',
    grandparentTitle: showTitle,
    parentIndex: season,
    index: episode,
    durationMs: 48 * 60 * 1000,
    viewOffsetMs: 20 * 60 * 1000,
    summary: '$showTitle keeps a viewer mid-episode, so the Continue Watching card has a real offset to show.',
    serverId: 'nas',
    serverName: 'NAS',
    thumbPath: TvDiscoveryArtwork.widePathFor(artwork),
    grandparentThumbPath: TvDiscoveryArtwork.pathFor(artwork),
    artPath: TvDiscoveryArtwork.widePathFor(artwork),
  );
}

MediaHub _movieHub(String id, String title, List<MediaItem> items) => MediaHub(
  id: id,
  identifier: id,
  title: title,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

MediaHub _showHub(String id, String title, List<MediaItem> items) => MediaHub(
  id: id,
  identifier: id,
  title: title,
  type: 'show',
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaItem> Function() onDeckResult = () => const [];
  List<MediaHub> Function() hubsResult = () => const [];

  /// Which servers "answered". Null means every registered server did — the
  /// honest default for every scenario except the one that deliberately
  /// tests a server going unanswered.
  Set<String>? succeededServerIds;

  Set<String> get _allServerIds => {for (final server in _servers) server.id};

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: onDeckResult(), succeededServerIds: succeededServerIds ?? serverIds ?? _allServerIds);

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubsResult(), succeededServerIds: succeededServerIds ?? serverIds ?? _allServerIds);
}

class _FakeClient implements MediaServerClient {
  _FakeClient({String serverId = 'nas', this.backend = MediaBackend.plex}) : serverId = ServerId(serverId);

  @override
  final ServerId serverId;

  @override
  String? get serverName => serverId.value;

  @override
  final MediaBackend backend;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
    TvDiscoveryArtwork.install();
  });

  tearDownAll(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    TvDiscoveryArtwork.remove();
  });

  late _FakeAggregationService aggregation;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late DiscoverProvider discover;
  late TvDiscoveryLandingProvider landing;

  Future<void> bootstrap(WidgetTester tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    final manager = MultiServerManager();
    for (final server in _servers) {
      manager.debugRegisterClientForTesting(_FakeClient(serverId: server.id, backend: server.backend));
    }
    aggregation = _FakeAggregationService(manager);
    multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider();
    discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
    addTearDown(discover.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);
  }

  Future<void> settle(WidgetTester tester) async {
    await discover.load();
    landing = TvDiscoveryLandingProvider(discover: discover, multiServer: multiServer);
    addTearDown(landing.dispose);
    // Microtask-only yield — see tv_discovery_landing_provider_test.dart's
    // own note on why `Future.delayed` hangs a `testWidgets` binding.
    for (var i = 0; i < 50 && landing.isProjecting; i++) {
      await Future<void>.value();
    }
  }

  Widget shell(Widget child) {
    final theme = monoTheme(dark: true);
    return MultiProvider(
      providers: [
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
        ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
        ChangeNotifierProvider<TvDiscoveryLandingProvider>.value(value: landing),
      ],
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme,
        home: InputModeTracker(
          child: Scaffold(backgroundColor: theme.extension<MonoTokens>()!.bg, body: child),
        ),
      ),
    );
  }

  List<MediaHub> richMovieHubs() => [
    _movieHub('recently-added-movies', 'Recently Added', [
      _film(
        id: 'harbourlight',
        title: 'The Long Harbour',
        mood: TvDiscoveryMood.warmOrange,
        genre: 'Drama',
        year: 2023,
      ),
      // Three sources, three backends — the multi-source badge case.
      for (final server in _servers)
        _film(
          id: 'blue-signal-${server.id}',
          title: 'Blue Signal',
          mood: TvDiscoveryMood.brightBlue,
          genre: 'Science fiction',
          year: 2022,
          serverId: server.id,
          serverName: server.name,
          backend: server.backend,
        ),
      _film(
        id: 'canopy',
        title: 'Under the Canopy',
        mood: TvDiscoveryMood.greenNature,
        genre: 'Documentary',
        year: 2021,
      ),
      _film(
        id: 'kite-parade',
        title: 'Paper Kite Parade',
        mood: TvDiscoveryMood.familyAnimation,
        genre: 'Animation',
        year: 2024,
      ),
      _film(
        id: 'neighbours',
        title: 'The Neighbours Downstairs',
        mood: TvDiscoveryMood.lightComedy,
        genre: 'Comedy',
        year: 2020,
      ),
      _film(id: 'arcade', title: 'Arcade Midnight', mood: TvDiscoveryMood.neon, genre: 'Thriller', year: 2019),
    ]),
    _movieHub('top-picks-movies', 'Top Picks', [
      _film(id: 'quarry-road', title: 'Quarry Road', mood: TvDiscoveryMood.darkDrama, genre: 'Drama', year: 2018),
      _film(
        id: 'salt-compass',
        title: 'Salt and Compass',
        mood: TvDiscoveryMood.desertEpic,
        genre: 'Adventure',
        year: 2017,
      ),
      _film(id: 'wintering', title: 'Wintering', mood: TvDiscoveryMood.coldNoir, genre: 'Drama', year: 2015),
    ]),
  ];

  List<MediaHub> richSeriesHubs() => [
    _showHub('recently-added-shows', 'Recently Added', [
      _show(
        id: 'kite-street',
        title: 'Kite Street',
        mood: TvDiscoveryMood.familyAnimation,
        genre: 'Family',
        childCount: 3,
      ),
      _show(
        id: 'corner-bakery',
        title: 'The Corner Bakery',
        mood: TvDiscoveryMood.lightComedy,
        genre: 'Comedy',
        childCount: 5,
      ),
      _show(
        id: 'tides-north',
        title: 'Tides of the North',
        mood: TvDiscoveryMood.greenNature,
        genre: 'Documentary',
        childCount: 1,
      ),
      _show(
        id: 'atlas-unbound',
        title: 'Atlas Unbound',
        mood: TvDiscoveryMood.brightBlue,
        genre: 'Science fiction',
        childCount: 2,
      ),
      _show(
        id: 'lantern-hour',
        title: 'Lantern Hour',
        mood: TvDiscoveryMood.pastelRomance,
        genre: 'Romance',
        childCount: 4,
      ),
      _show(id: 'quiet-ward', title: 'The Quiet Ward', mood: TvDiscoveryMood.darkDrama, genre: 'Drama', childCount: 2),
    ]),
  ];

  List<MediaItem> continueWatchingOnDeck() => [
    _episode(
      id: 'harbourlight-s2e4',
      showTitle: 'Harbourlight',
      mood: TvDiscoveryMood.warmOrange,
      season: 2,
      episode: 4,
    ),
    _film(id: 'cw-film', title: 'The Long Harbour', mood: TvDiscoveryMood.warmOrange, genre: 'Drama', year: 2023),
  ];

  testWidgets('movies landing, first item focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richMovieHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvMoviesLandingScreen()));
    await tester.pumpAndSettle();

    // Actually focus it. The landing does not autofocus — focus entry is the
    // fase-7 shell's — so without this the render showed an unfocused first
    // tile under a name claiming otherwise, and the set had no golden of
    // hoofdstuk 33.3's binding composition at all.
    await focusFirstTile(tester, landing.movieRails);

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_movies_first_focused');
  });

  testWidgets('movies landing, multi-source item focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richMovieHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvMoviesLandingScreen()));
    await tester.pumpAndSettle();

    final multiSourceHub = landing.movieRails.firstWhere(
      (hub) => hub.groups.any((g) => g.sources.length == _servers.length),
    );
    final multiSourceGroup = multiSourceHub.groups.firstWhere((g) => g.sources.length == _servers.length);
    // The outer landing `ListView` virtualizes rails just like a rail
    // virtualizes its own tiles — the third rail has no `Element` at all yet,
    // so `ensureVisible` (which needs the target already built) cannot reach
    // it; `scrollUntilVisible` scrolls in steps and re-checks after each one,
    // which is what actually builds it.
    await tester.scrollUntilVisible(
      // By the rail's own title, not by key: since DEC-068 the landing keys
      // each rail with a `GlobalKey<TvDiscoveryRailState>` so DOWN out of the
      // header action can reach the first rail's state, and the old
      // `ValueKey(hubId)` finder matches nothing.
      find.byWidgetPredicate((w) => w is TvDiscoveryRail && w.title == multiSourceHub.title),
      200,
      scrollable: find.byType(Scrollable).first,
    );
    await tester.pumpAndSettle();
    final rails = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    expect(rails.any((rail) => rail.focusGroup(multiSourceGroup.groupId)), isTrue);
    await tester.pumpAndSettle();

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_movies_multi_source_focused');
  });

  testWidgets('movies landing, one server unanswered shows a partial row', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richMovieHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    // Only 'nas' answers, even though all three registered servers are
    // online — hoofdstuk 21.4's partial-coverage state.
    aggregation.succeededServerIds = {'nas'};
    await settle(tester);
    expect(discover.unansweredServerIds, {'attic', 'garage'});

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvMoviesLandingScreen()));
    await tester.pumpAndSettle();

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_movies_partial_state');
  });

  testWidgets('movies landing, View All focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richMovieHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvMoviesLandingScreen()));
    await tester.pumpAndSettle();

    // No scrolling: since DEC-068 the catalog action is in the page header,
    // which is exactly the point — it is reachable without walking the page.
    // Remote-first (DEC-064 punt 3): `TvViewAllAction` runs on a
    // `FocusableWrapper` Select key, not a tap, so it is driven by focusing
    // its node directly rather than `tester.tap`.
    tester.widget<TvViewAllAction>(find.byType(TvViewAllAction)).focusNode!.requestFocus();
    await tester.pumpAndSettle();

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_movies_view_all_focused');
  });

  testWidgets('series landing, first item focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richSeriesHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvSeriesLandingScreen()));
    await tester.pumpAndSettle();

    await focusFirstTile(tester, landing.seriesRails);

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_series_first_focused');
  });

  testWidgets('movies landing, a middle item focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richMovieHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvMoviesLandingScreen()));
    await tester.pumpAndSettle();

    await focusMiddleOfFirstRail(tester, landing.movieRails);

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_movies_middle_focused');
  });

  testWidgets('series landing, a middle item focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richSeriesHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvSeriesLandingScreen()));
    await tester.pumpAndSettle();

    await focusMiddleOfFirstRail(tester, landing.seriesRails);

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_series_middle_focused');
  });

  // This used to focus a Continue Watching episode on the series landing and
  // photograph it, for DEC-065 punt 3: "het gefocuste CW-item draagt de
  // episode-still van de concrete aflevering waar beschikbaar". That contract
  // has not gone anywhere, but the surface it is proven on has.
  // `TvDiscoveryLandingProvider._project` sorts backend hubs into a Films row
  // or a Series row by hub kind and drops episode, mixed and other rows on
  // purpose (hoofdstuk 17.1): they have no single Films-or-Series home and
  // belong to Home's own projection. So a series landing has no Continue
  // Watching rail to focus, and the old test failed on an empty `firstWhere`
  // rather than on a picture.
  //
  // The picture now lives where the rail does:
  // `tv_home_production_first_row_focused.png` in
  // `test/goldens/tv_home_production_golden_test.dart` shows the same
  // Harbourlight fixture focused as a wide episode still, with "S2 E4 · 28 min
  // left" under it. What is left to hold here is the rule that replaced it.
  testWidgets('series landing keeps Continue Watching off, however full the on deck is', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richSeriesHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvSeriesLandingScreen()));
    await tester.pumpAndSettle();

    expect(
      continueWatchingOnDeck().any((item) => item.kind == MediaKind.episode),
      isTrue,
      reason: 'precondition: the on deck this landing is fed does carry episodes',
    );
    expect(
      landing.seriesRails
          .expand((rail) => rail.groups)
          .where((g) => g.representativeSource.item.kind == MediaKind.episode),
      isEmpty,
      reason: 'episode rows belong to Home, not to a Films-or-Series landing (hoofdstuk 17.1)',
    );
  });

  testWidgets('series landing, View All focused', (tester) async {
    await bootstrap(tester);
    aggregation.hubsResult = richSeriesHubs;
    aggregation.onDeckResult = continueWatchingOnDeck;
    await settle(tester);

    setGoldenSurfaceSize(tester);
    await tester.pumpWidget(shell(const TvSeriesLandingScreen()));
    await tester.pumpAndSettle();

    tester.widget<TvViewAllAction>(find.byType(TvViewAllAction)).focusNode!.requestFocus();
    await tester.pumpAndSettle();

    await expectMatchesGolden(find.byType(MaterialApp), 'tv_discovery_production_series_view_all_focused');
  });
}

/// Focus a tile in the middle of the first recommendation rail — the state
/// the north star's row-focus reference shows, and the one that proves a
/// focused tile's neighbours stay visible on both sides.
Future<void> focusMiddleOfFirstRail(WidgetTester tester, List<UnifiedMediaHub> rails) async {
  // Rail 0 is Continue Watching; the first recommendation rail is what the
  // landing's own hierarchy leads with.
  final rail = rails.firstWhere((hub) => hub.groups.length >= 3, orElse: () => rails.last);
  final middle = rail.groups[rail.groups.length ~/ 2];
  final states = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
  expect(states.any((state) => state.focusGroup(middle.groupId)), isTrue);
  await tester.pumpAndSettle();
}

/// Focus the first tile of the first rail — hoofdstuk 33.3's reference state.
Future<void> focusFirstTile(WidgetTester tester, List<UnifiedMediaHub> rails) async {
  final first = rails.first.groups.first;
  final states = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
  expect(states.any((state) => state.focusGroup(first.groupId)), isTrue);
  await tester.pumpAndSettle();
}
