/// Fase 7 closure, register I22 and I23 (hoofdstuk 7.4 and 7.6 of
/// docs/tvos-unified-experience.md).
///
/// Leaving a destination and coming back to it must return the viewer to where
/// they were standing, not to the top of the page. On this shell that is two
/// different mechanisms, because the surfaces are two different kinds of thing:
///
///  * a destination's **root** screen lives in `MainScreen`'s `IndexedStack`
///    and is never unmounted, so it keeps its own scroll offset and its rails
///    keep their own tile — nothing has to be stored anywhere;
///  * the complete catalog is a [TvNestedRoute], and only the *active*
///    destination's top route is built. Switching away tears it down. Its place
///    therefore lives one level up, in [TvNavigationCoordinator], which is the
///    production consumer hoofdstuk 7.6's focus memory did not have when fase 7
///    was first committed.
///
/// These drive the production [TvRootShell], the production
/// [TvMoviesScreen]/[TvSeriesScreen] over a real [UnifiedCatalogProvider], and
/// the production [TvDiscoveryLandingScreen] — and they move through them with
/// the remote, because a focus contract asserted by calling methods proves the
/// methods rather than the contract. The shell host below is the same wiring
/// `MainScreen._openTvCompleteCatalog` and `MainScreen._selectTvDestination`
/// build; mounting `MainScreen` itself would drag in the whole app bootstrap
/// for no additional coverage of what is under test.
library;

import 'package:flutter/material.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/tv_discovery_landing_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/tv/tv_movies_landing_screen.dart';
import 'package:pleya/screens/tv/tv_movies_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/screens/tv/tv_series_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/screens/tv/tv_my_pleya_navigator.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

/// Enough titles that the grid is several screens tall — without that there is
/// nothing to scroll and every offset assertion below would pass at zero.
const int _titleCount = 90;

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient({required this.items});

  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final end = (query.offset + query.limit).clamp(0, items.length);
    final slice = query.offset >= items.length ? const <MediaItem>[] : items.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: items.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaHub _hub(String id, String title, List<String> itemIds) => MediaHub(
  id: id,
  identifier: id,
  title: title,
  type: 'movie',
  items: [
    for (final itemId in itemIds)
      MediaItem(
        id: itemId,
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Title $itemId',
        year: 2024,
        serverId: 'nas',
        serverName: 'NAS',
      ),
  ],
  size: itemIds.length,
  serverId: 'nas',
  serverName: 'NAS',
);

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaHub> Function() hubsResult = () => const [];

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'nas'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubsResult(), succeededServerIds: serverIds ?? const {'nas'});
}

/// Answers identity lookups and nothing else — the landing's rails only need a
/// client to exist for artwork resolution.
class _FakeHubClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  // Answered explicitly rather than left to `noSuchMethod`: `DiscoverProvider`
  // calls all four while loading, and a throwing stub turns every run of this
  // test into a wall of caught-error logging.
  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyAddedShows({int limit = 50}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The part of `MainScreen` this contract lives in, and nothing else: the
/// coordinator, the nested stack, and the two focus hand-offs the bar drives.
class _ShellHost extends StatefulWidget {
  const _ShellHost({super.key, required this.coordinator, this.buildCatalog, this.roots, this.rootOrder = const []});

  final TvNavigationCoordinator coordinator;

  /// Builds the destination's complete catalog, handed the place the previous
  /// visit reported — `MainScreen._openTvCompleteCatalog`, inlined.
  final Widget Function(TvDestinationId destination, GlobalKey? screenKey)? buildCatalog;

  /// The destinations' own root screens, hosted the way `MainScreen` hosts
  /// them: one `IndexedStack`, so a destination the viewer leaves is still
  /// mounted and keeps everything it owns.
  final Map<TvDestinationId, (GlobalKey, Widget)>? roots;

  /// The stack's order, because an `IndexedStack` is indexed.
  final List<TvDestinationId> rootOrder;

  @override
  State<_ShellHost> createState() => _ShellHostState();
}

class _ShellHostState extends State<_ShellHost> {
  final _navNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
  final _navScope = FocusScopeNode(debugLabel: 'nav');
  final _contentScope = FocusScopeNode(debugLabel: 'content');
  bool _isNavFocused = false;

  @override
  void dispose() {
    _navNodes.dispose();
    _navScope.dispose();
    _contentScope.dispose();
    super.dispose();
  }

  FocusMemoryTracker get navNodes => _navNodes;

  void openCatalog(TvDestinationId destination) {
    final screenKey = GlobalKey(debugLabel: 'tvCatalog_${destination.name}');
    widget.coordinator.activate(destination);
    widget.coordinator.pushNested(
      destination,
      TvNestedRoute(
        id: 'tvCatalog_${destination.name}',
        screenKey: screenKey,
        builder: (_) => widget.buildCatalog!(destination, screenKey),
      ),
    );
    _focusContent();
  }

  /// `MainScreen._openTvMyPleyaSection`, inlined: Mijn Pleya stays the active
  /// destination and the section rides in as a nested route on top of it.
  /// [restoredFocusKeys] records what `_popTvNestedRoute` would hand back to
  /// the hub.
  final restoredFocusKeys = <String>[];

  void openSection(TvMyPleyaSection section, Widget child) {
    widget.coordinator.activate(TvDestinationId.myPleya);
    widget.coordinator.pushNested(
      TvDestinationId.myPleya,
      TvNestedRoute(id: 'tvMyPleya_${section.name}', restoreFocusKey: section.tileFocusKey, builder: (_) => child),
    );
    setState(() {});
  }

  /// `MainScreen._popTvNestedRoute`: pop, then put the remote back on the tile
  /// the section was opened from rather than at the top of the hub.
  bool popSection() {
    final popped = widget.coordinator.popNested();
    if (popped == null) return false;
    final key = popped.restoreFocusKey;
    if (key != null && widget.coordinator.active == TvDestinationId.myPleya) {
      restoredFocusKeys.add(key);
    }
    setState(() {});
    return true;
  }

  /// `MainScreen._selectTvDestination`: activate, then put the remote back in
  /// the content of whatever is now on screen.
  void selectDestination(TvDestinationId destination) {
    widget.coordinator.activate(destination);
    setState(() => _isNavFocused = false);
    _focusContent();
  }

  /// `MainScreen._focusContent`: a nested route is what the viewer is looking
  /// at, and otherwise it is the destination's own root screen.
  void _focusContent() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final route = widget.coordinator.activeNestedRoute;
      if (route != null) {
        if (route.screenKey?.currentState case final FocusableTab focusable) {
          focusable.focusActiveTabIfReady();
        }
        return;
      }
      if (widget.roots?[widget.coordinator.active]?.$1.currentState case final FocusableTab focusable) {
        focusable.focusActiveTabIfReady();
      }
    });
  }

  @override
  Widget build(BuildContext context) => TvRootShell(
    coordinator: widget.coordinator,
    contentFocus: TvContentFocusAuthority(),
    navNodes: _navNodes,
    navFocusScope: _navScope,
    contentFocusScope: _contentScope,
    isNavFocused: _isNavFocused,
    profile: null,
    onSelectDestination: selectDestination,
    onFocusDestination: widget.coordinator.activate,
    onFocusContent: ({bool restorePreviousFocus = true}) => _focusContent(),
    onFocusNav: () => setState(() => _isNavFocused = true),
    onOpenProfiles: () {},
    onOverlaySheetOpenChanged: (_) {},
    onKeyEvent: (_) => KeyEventResult.ignored,
    selectLibrary: null,
    openSettings: null,
    child: widget.roots == null
        ? const SizedBox.shrink()
        : IndexedStack(
            index: widget.rootOrder.indexOf(widget.coordinator.active).clamp(0, widget.rootOrder.length - 1),
            children: [for (final destination in widget.rootOrder) widget.roots![destination]!.$2],
          ),
  );
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  /// Mounts the shell with both catalogs reachable, and returns the host state.
  Future<_ShellHostState> pumpShell(WidgetTester tester, TvNavigationCoordinator coordinator) async {
    final client = _FakeLibraryClient(
      items: [
        for (var i = 0; i < _titleCount; i++)
          MediaItem(
            id: 'movie_$i',
            backend: MediaBackend.plex,
            kind: MediaKind.movie,
            title: 'Film ${i.toString().padLeft(2, '0')}',
            serverId: 'nas',
            year: 2000 + i % 25,
          ),
        for (var i = 0; i < _titleCount; i++)
          MediaItem(
            id: 'show_$i',
            backend: MediaBackend.plex,
            kind: MediaKind.show,
            title: 'Serie ${i.toString().padLeft(2, '0')}',
            serverId: 'nas',
            year: 2000 + i % 25,
          ),
      ],
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'NAS',
        ),
        MediaLibrary(
          id: '2',
          backend: MediaBackend.plex,
          title: 'Series',
          kind: MediaKind.show,
          serverId: 'nas',
          serverName: 'NAS',
        ),
      ]);
    final hidden = HiddenLibrariesProvider();
    final catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hidden);
    addTearDown(() {
      catalogs.dispose();
      hidden.dispose();
      libraries.dispose();
      multiServer.dispose();
    });

    setGoldenSurfaceSize(tester);
    final hostKey = GlobalKey<_ShellHostState>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            Provider<UnifiedCatalogs>.value(value: catalogs),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: InputModeTracker(
                child: _ShellHost(
                  key: hostKey,
                  coordinator: coordinator,
                  buildCatalog: (destination, screenKey) => destination == TvDestinationId.series
                      ? TvSeriesScreen(
                          catalogKey: screenKey,
                          restoreFrom: coordinator.contentFocusFor(destination),
                          onRemember: (place) => coordinator.rememberContentFocus(destination, place),
                        )
                      : TvMoviesScreen(
                          catalogKey: screenKey,
                          restoreFrom: coordinator.contentFocusFor(destination),
                          onRemember: (place) => coordinator.rememberContentFocus(destination, place),
                        ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return hostKey.currentState!;
  }

  /// The `groupId` of the card the remote is on, read off the focused node's
  /// debug label — the grid names each node after the group it draws.
  String? focusedCardGroupId(WidgetTester tester) {
    final label = FocusManager.instance.primaryFocus?.debugLabel;
    if (label == null || !label.startsWith('TvUnifiedCard(')) return null;
    return label.substring('TvUnifiedCard('.length, label.length - 1);
  }

  double gridOffset(WidgetTester tester) => tester
      .widget<Scrollable>(find.descendant(of: find.byType(TvUnifiedMediaGrid), matching: find.byType(Scrollable)))
      .controller!
      .offset;

  /// Walks the remote DOWN from wherever the focus is until it is on a card in
  /// row [row] — the real traversal, so what this proves is the contract and
  /// not a method call.
  Future<void> walkDownRows(WidgetTester tester, int rows) async {
    for (var i = 0; i < rows; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
  }

  Future<void> walkRight(WidgetTester tester, int steps) async {
    for (var i = 0; i < steps; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }
  }

  // ---------------------------------------------------------------------------
  // The complete catalog (register I23, and the card half of I22)
  // ---------------------------------------------------------------------------

  for (final scenario in [
    (destination: TvDestinationId.movies, other: TvDestinationId.series, name: 'All movies'),
    (destination: TvDestinationId.series, other: TvDestinationId.movies, name: 'All series'),
  ]) {
    testWidgets('${scenario.name} comes back to the card and the scroll region it was left on', (tester) async {
      final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
      addTearDown(coordinator.dispose);

      final host = await pumpShell(tester, coordinator);
      host.openCatalog(scenario.destination);
      await tester.pumpAndSettle();
      expect(find.byType(TvUnifiedMediaGrid), findsOneWidget, reason: 'sanity: the catalog must have loaded cards');

      // Down out of the header, then down and across into the grid: a
      // non-first row and a non-first column, so nothing here can pass by
      // landing on the default card.
      await walkDownRows(tester, 4);
      await walkRight(tester, 2);
      final leftOn = focusedCardGroupId(tester);
      final offsetWhenLeft = gridOffset(tester);
      expect(leftOn, isNotNull, reason: 'the remote must actually be on a card');
      expect(offsetWhenLeft, greaterThan(0), reason: 'sanity: walking down must have scrolled the grid');

      // Leave content for the bar, walk to the other destination, select it.
      final barNodes = host.navNodes;
      barNodes.get(scenario.other.focusKey).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(coordinator.active, scenario.other);

      // And back.
      barNodes.get(scenario.destination.focusKey).requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      // The same logical catalog destination, with its own page still on it.
      expect(coordinator.active, scenario.destination);
      expect(coordinator.activeNestedRoute?.id, 'tvCatalog_${scenario.destination.name}');
      expect(find.byType(TvUnifiedMediaGrid), findsOneWidget);

      // The scroll region survived. Not asserted to the pixel: the restore is
      // clamped to the live extent, and the point of the contract is that the
      // viewer is back among the same cards rather than at the top of the page.
      expect(gridOffset(tester), offsetWhenLeft);

      // Re-enter the content: DOWN out of the header lands on the card the
      // viewer was left on, which is hoofdstuk 7.4's "Down vanaf header gaat
      // naar het laatst gefocuste griditem" read across a destination switch.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedCardGroupId(tester), leftOn);
    });
  }

  testWidgets('coming back does not restart the merge that is already loaded', (tester) async {
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    addTearDown(coordinator.dispose);

    final host = await pumpShell(tester, coordinator);
    host.openCatalog(TvDestinationId.movies);
    await tester.pumpAndSettle();

    final catalog = Provider.of<UnifiedCatalogs>(tester.element(find.byType(TvUnifiedMediaGrid)), listen: false).movies;
    // Page in a second time, so "restarted" is visible as a shrinking list
    // rather than only as a refetch nobody can see.
    await catalog.loadMore();
    await tester.pumpAndSettle();
    final loaded = catalog.snapshot.groups.length;
    expect(loaded, greaterThan(0));
    final firstGroupId = catalog.snapshot.groups.first.groupId;

    host.selectDestination(TvDestinationId.series);
    await tester.pumpAndSettle();
    host.selectDestination(TvDestinationId.movies);
    await tester.pumpAndSettle();

    // Hoofdstuk 24 and [DEC-069]: a nested route may not cost a reload. The
    // pages are still there and they are the same pages — a restart would have
    // dropped back to one page under a new generation.
    expect(catalog.snapshot.groups, hasLength(loaded));
    expect(catalog.snapshot.groups.first.groupId, firstGroupId);
  });

  // ---------------------------------------------------------------------------
  // A discovery landing (the destination-root half of register I22)
  // ---------------------------------------------------------------------------

  testWidgets('the Films landing comes back to the rail tile it was left on', (tester) async {
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    addTearDown(coordinator.dispose);

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeHubClient());
    final aggregation = _FakeAggregationService(manager);
    final multiServer = MultiServerProvider(manager, aggregation);
    final hidden = HiddenLibrariesProvider();
    final libraries = LibrariesProvider();
    final discover = DiscoverProvider(multiServer, hidden, libraries, isProfileBinding: () => false);
    aggregation.hubsResult = () => [
      _hub('recently-added-movies', 'Recently Added', ['m1', 'm2', 'm3']),
      _hub('top-picks-movies', 'Top Picks', ['m4', 'm5']),
    ];
    await discover.load();
    final landing = TvDiscoveryLandingProvider(discover: discover, multiServer: multiServer);
    addTearDown(() {
      landing.dispose();
      discover.dispose();
      libraries.dispose();
      hidden.dispose();
      multiServer.dispose();
    });
    for (var i = 0; i < 50 && landing.isProjecting; i++) {
      await Future<void>.value();
    }
    expect(landing.movieRails, isNotEmpty, reason: 'sanity: the projection must have produced rails');

    setGoldenSurfaceSize(tester);
    final moviesKey = GlobalKey(debugLabel: 'tvMoviesLanding');
    final hostKey = GlobalKey<_ShellHostState>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
            ChangeNotifierProvider<TvDiscoveryLandingProvider>.value(value: landing),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: InputModeTracker(
                child: _ShellHost(
                  key: hostKey,
                  coordinator: coordinator,
                  rootOrder: const [TvDestinationId.movies, TvDestinationId.myPleya],
                  roots: {
                    TvDestinationId.movies: (moviesKey, TvMoviesLandingScreen(landingKey: moviesKey, onOpenAll: () {})),
                    TvDestinationId.myPleya: (GlobalKey(), const Center(child: Text('elsewhere'))),
                  },
                ),
              ),
            ),
          ),
        ),
      ),
    );
    coordinator.activate(TvDestinationId.movies);
    await tester.pumpAndSettle();

    // Stand on a tile that is neither the first rail's first tile nor the one
    // a fresh rail would autofocus.
    final rails = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).toList();
    expect(rails, hasLength(greaterThan(1)));
    final wanted = rails.first.widget.groups[1].groupId;
    expect(rails.first.focusGroup(wanted), isTrue);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvDiscoveryTile_$wanted');

    // Away and back, through the bar.
    hostKey.currentState!.selectDestination(TvDestinationId.myPleya);
    await tester.pumpAndSettle();
    expect(find.text('elsewhere'), findsOneWidget);
    hostKey.currentState!.selectDestination(TvDestinationId.movies);
    await tester.pumpAndSettle();

    // Hoofdstuk 7.1: coming in from the bar lands on the page header, not on a
    // card — the header is the one control that changes where you are, and
    // starting under it would make it reachable only by going back up.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvDiscoveryViewAll');

    // And DOWN out of it returns to the tile, not to the start of the row.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvDiscoveryTile_$wanted');
  });

  testWidgets('a remembered card that is gone falls back to the first, and never to nothing', (tester) async {
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    addTearDown(coordinator.dispose);
    // A place naming a title this catalog does not have — what a filter change
    // or a server going away leaves behind.
    coordinator.rememberContentFocus(
      TvDestinationId.movies,
      const TvDestinationFocusMemory(focusedElementId: 'sort', groupId: 'nope', scrollOffset: 4000),
    );

    final host = await pumpShell(tester, coordinator);
    host.openCatalog(TvDestinationId.movies);
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(find.byType(TvUnifiedMediaCard), findsWidgets);
    expect(focusedCardGroupId(tester), isNotNull, reason: 'the remote must land on a card, not on nothing');
  });

  group('I20: coming back from Settings', () {
    testWidgets('the section rides on Mijn Pleya and Back puts the remote on its tile', (tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final coordinator = TvNavigationCoordinator();
      addTearDown(coordinator.dispose);
      final hostKey = GlobalKey<_ShellHostState>();

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: _ShellHost(key: hostKey, coordinator: coordinator),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();

      hostKey.currentState!.openSection(TvMyPleyaSection.settings, const Center(child: Text('settings section')));
      await tester.pumpAndSettle();

      // Settings is *not* a root destination: the bar still says Mijn Pleya,
      // which is what makes Back mean "close the section" rather than "go up
      // to the bar" (hoofdstuk 7.5 step 2).
      expect(find.text('settings section'), findsOneWidget);
      expect(coordinator.active, TvDestinationId.myPleya);
      expect(coordinator.activeCanPop, isTrue);

      expect(hostKey.currentState!.popSection(), isTrue);
      await tester.pumpAndSettle();

      expect(find.text('settings section'), findsNothing);
      expect(
        coordinator.active,
        TvDestinationId.myPleya,
        reason: 'the destination never changed, so there is nothing to restore but the focus',
      );
      expect(coordinator.activeCanPop, isFalse);
      expect(
        hostKey.currentState!.restoredFocusKeys,
        [TvMyPleyaSection.settings.tileFocusKey],
        reason: 'the remote lands back on the tile the section was opened from, not at the top of the hub',
      );
    });

    testWidgets('the production route carries the tile the shell restores to', (tester) async {
      // The shell test above supplies its own route; this pins the real one so
      // the two halves cannot drift apart.
      final route = tvMyPleyaNestedRoute(TvMyPleyaSection.settings);

      expect(route.id, 'tvMyPleya_settings');
      expect(route.restoreFocusKey, TvMyPleyaSection.settings.tileFocusKey);
      expect(route.screenKey, isNotNull, reason: 'without a key the shell cannot ask the section to take focus');
    });
  });
}
