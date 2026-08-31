import 'package:drift/native.dart';
import 'package:pleya/media/ids.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/focusable_action_bar.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/mixins/tab_visibility_aware.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/discover_screen.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:pleya/widgets/tv/tv_content_feed.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('TV tab focus returns to the Home feed instead of the reload action', (tester) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.libraryDensity, LibraryDensity.max);
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = const Size(1280, 720);
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final item = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Movie 1',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final hub = MediaHub(id: 'hub_1', title: 'Recommended', type: 'movie', items: [item], size: 1);
    final client = _FakeMediaServerClient(hubs: [hub]);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    final librariesProvider = LibrariesProvider();
    final watchTogetherProvider = WatchTogetherProvider();
    final companionRemoteProvider = CompanionRemoteProvider();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final profileRegistry = _FakeProfileRegistry(db);
    final connectionRegistry = _FakeConnectionRegistry(db);
    final profileConnectionRegistry = _FakeProfileConnectionRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connectionRegistry,
      profileConnections: profileConnectionRegistry,
      storage: storage,
      plexHomeUserFetcher: (_) async => const [],
    );
    final activeProfileProvider = ActiveProfileProvider(
      registry: profileRegistry,
      plexHome: plexHome,
      connections: connectionRegistry,
      storage: storage,
    );
    final discoverProvider = DiscoverProvider(
      multiServerProvider,
      hiddenLibrariesProvider,
      librariesProvider,
      isProfileBinding: () => activeProfileProvider.isBinding,
    );
    final discoverKey = GlobalKey<State<DiscoverScreen>>();
    const targetSidebarOffset = SideNavigationRailState.expandedWidth;
    const currentForegroundLeft = 120.0;
    const foregroundWidth = 1280 - SideNavigationRailState.tvCollapsedWidth;

    addTearDown(() async {
      discoverProvider.dispose();
      activeProfileProvider.dispose();
      companionRemoteProvider.dispose();
      watchTogetherProvider.dispose();
      librariesProvider.dispose();
      hiddenLibrariesProvider.dispose();
      multiServerProvider.dispose();
      await plexHome.dispose();
      await db.close();
    });

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
            ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
            ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
            ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
            ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogetherProvider),
            ChangeNotifierProvider<CompanionRemoteProvider>.value(value: companionRemoteProvider),
            ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
            ChangeNotifierProvider<DiscoverProvider>.value(value: discoverProvider),
            ChangeNotifierProvider<TvHomeProjectionProvider>(
              create: (context) => TvHomeProjectionProvider(
                discover: discoverProvider,
                multiServer: multiServerProvider,
                continueWatchingTitle: t.discover.continueWatching,
                latestMoviesTitle: t.discover.recentlyReleased,
              ),
            ),
          ],
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: MainScreenFocusScope(
              focusSidebar: () {},
              focusContent: () {},
              isSidebarFocused: false,
              sideNavigationWidth: targetSidebarOffset,
              reservedSideNavigationWidth: SideNavigationRailState.tvCollapsedWidth,
              foregroundLeft: currentForegroundLeft,
              foregroundWidth: foregroundWidth,
              viewportWidth: 1280,
              child: Align(
                alignment: Alignment.centerLeft,
                child: SizedBox(
                  width: foregroundWidth,
                  height: 720,
                  child: DiscoverScreen(key: discoverKey),
                ),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.pumpAndSettle();
    // Fase 8: Home is a `TvContentFeed` — a rounded in-page carousel over the
    // projected hero groups, with projected unified rows under it. The
    // spotlight/browse-rail geometry this test used to assert (the full-bleed
    // background's contentLeft/contentBottom, the rail's resting peek, the
    // sidebar bleed layers) has no subject any more: fase 7 removed the
    // sidebar and fase 8 removed the full-bleed billboard. What is left, and
    // what this test is named for, is the focus round trip.
    expect(find.byType(TvContentFeed), findsOneWidget);
    expect(find.byType(TvHeroBillboardCarousel), findsOneWidget, reason: 'the hub fallback billboard (hoofdstuk 9.5)');

    // The overlaid Home action bar is gone from TV with fase 8: 33.1's binding
    // composition has no chrome between the top navigation and the hero card,
    // and hoofdstuk 7.3 ("Up vanaf hero gaat naar de actieve
    // topnavbestemming") left it on no focus path at all. What the shell asks
    // for is the destination's primary focus, and that is what it gets.
    expect(find.byType(FocusableActionBar), findsNothing);

    (discoverKey.currentState! as FocusableTab).focusActiveTabIfReady();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');

    // Leaving the destination must not move the focus by itself — the shell
    // owns that — and coming back must land on the hero again rather than on
    // whatever traversal would have picked.
    (discoverKey.currentState! as TabVisibilityAware).onTabHidden();
    await tester.pump();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');

    FocusManager.instance.primaryFocus?.unfocus();
    await tester.pump();

    (discoverKey.currentState! as TabVisibilityAware).onTabShown();
    (discoverKey.currentState! as FocusableTab).focusActiveTabIfReady();
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');
  });

  // Fase-0 baseline for Pleya Unified TV 2026 (docs/tvos-unified-experience.md
  // hoofdstuk 27): this group locks in the existing Home-focus traversal that
  // fase 0 must not change before any unified-catalog work begins. It asserts
  // what DiscoverScreen actually does today on TV — including where it
  // diverges from the intended hoofdstuk 7 focus contract (e.g. Up from the
  // browse rail always lands on the hero Play pill, never on a "last used"
  // hero CTA) — not what a future phase should make it do.
  // The four fase-0 Home-focus baselines, unchanged in what they assert and
  // re-pointed at the fase-8 surface: the hero CTAs are the carousel's
  // (`tvHeroPlay` / `tvHeroMoreInfo`) and the row below it is a
  // `TvContentRow`, whose focus nodes are per logical card rather than one
  // node for the whole rail.
  group('Home-focus baseline (TV)', () {
    testWidgets('cold TV focus lands on the hero Play pill when a spotlight item exists', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');
    });

    testWidgets('Down from the hero Play pill reaches the first browse row', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();

      // The first content row's tile, keyed by logical group id — fase 8
      // replaced the single `tv_browse_rail` node with per-card nodes
      // (hoofdstuk 7.6: focus identity is the group, never an index).
      expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('tvDiscoveryTile_'));
    });

    testWidgets('Up from the first browse row returns focus to the hero Play pill', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, startsWith('tvDiscoveryTile_'));

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');
    });

    testWidgets('Right from hero Play moves to hero More-info, and Left moves back', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroMoreInfo');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');
    });
  });
}

/// Bundle of everything a pumped [DiscoverScreen] test harness needs to keep
/// alive for the duration of one test, plus a single teardown entry point.
class _TvDiscoverHarness {
  _TvDiscoverHarness({
    required this.discoverProvider,
    required this.activeProfileProvider,
    required this.companionRemoteProvider,
    required this.watchTogetherProvider,
    required this.librariesProvider,
    required this.hiddenLibrariesProvider,
    required this.multiServerProvider,
    required this.plexHome,
    required this.db,
  });

  final DiscoverProvider discoverProvider;
  final ActiveProfileProvider activeProfileProvider;
  final CompanionRemoteProvider companionRemoteProvider;
  final WatchTogetherProvider watchTogetherProvider;
  final LibrariesProvider librariesProvider;
  final HiddenLibrariesProvider hiddenLibrariesProvider;
  final MultiServerProvider multiServerProvider;
  final PlexHomeService plexHome;
  final AppDatabase db;

  Future<void> disposeAll() async {
    discoverProvider.dispose();
    activeProfileProvider.dispose();
    companionRemoteProvider.dispose();
    watchTogetherProvider.dispose();
    librariesProvider.dispose();
    hiddenLibrariesProvider.dispose();
    multiServerProvider.dispose();
    await plexHome.dispose();
    await db.close();
  }
}

/// Mounts [DiscoverScreen] on a 1280x720 TV-mode surface, wired with the same
/// fake providers/registries as the single pre-existing test above, with one
/// global hub ('hub_1') carrying one item. There are no recent films here, so
/// this exercises hoofdstuk 9.5's fallback billboard — the hub's first logical
/// title — which is exactly the shape these baselines were written against.
/// Reused by the Home-focus baseline tests so they exercise the real focus
/// wiring instead of a hand-rolled substitute.
Future<_TvDiscoverHarness> _pumpTvDiscoverScreen(WidgetTester tester) async {
  final settings = await SettingsService.getInstance();
  await settings.write(SettingsService.libraryDensity, LibraryDensity.max);
  tester.view.devicePixelRatio = 1.0;
  tester.view.physicalSize = const Size(1280, 720);
  addTearDown(() {
    tester.view.resetDevicePixelRatio();
    tester.view.resetPhysicalSize();
  });

  final item = MediaItem(
    id: 'movie_1',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Movie 1',
    serverId: 'server_1',
    serverName: 'Server',
  );
  final hub = MediaHub(id: 'hub_1', title: 'Recommended', type: 'movie', items: [item], size: 1);
  final client = _FakeMediaServerClient(hubs: [hub]);
  final manager = MultiServerManager()..debugRegisterClientForTesting(client);
  final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
  final hiddenLibrariesProvider = HiddenLibrariesProvider();
  final librariesProvider = LibrariesProvider();
  final watchTogetherProvider = WatchTogetherProvider();
  final companionRemoteProvider = CompanionRemoteProvider();

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  final profileRegistry = _FakeProfileRegistry(db);
  final connectionRegistry = _FakeConnectionRegistry(db);
  final profileConnectionRegistry = _FakeProfileConnectionRegistry(db);
  final storage = await StorageService.getInstance();
  final plexHome = PlexHomeService(
    connections: connectionRegistry,
    profileConnections: profileConnectionRegistry,
    storage: storage,
    plexHomeUserFetcher: (_) async => const [],
  );
  final activeProfileProvider = ActiveProfileProvider(
    registry: profileRegistry,
    plexHome: plexHome,
    connections: connectionRegistry,
    storage: storage,
  );
  final discoverProvider = DiscoverProvider(
    multiServerProvider,
    hiddenLibrariesProvider,
    librariesProvider,
    isProfileBinding: () => activeProfileProvider.isBinding,
  );
  final discoverKey = GlobalKey<State<DiscoverScreen>>();
  const foregroundWidth = 1280 - SideNavigationRailState.tvCollapsedWidth;

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibrariesProvider),
          ChangeNotifierProvider<HomeLayoutProvider>(create: (_) => HomeLayoutProvider()),
          ChangeNotifierProvider<LibrariesProvider>.value(value: librariesProvider),
          ChangeNotifierProvider<WatchTogetherProvider>.value(value: watchTogetherProvider),
          ChangeNotifierProvider<CompanionRemoteProvider>.value(value: companionRemoteProvider),
          ChangeNotifierProvider<ActiveProfileProvider>.value(value: activeProfileProvider),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discoverProvider),
          ChangeNotifierProvider<TvHomeProjectionProvider>(
            create: (context) => TvHomeProjectionProvider(
              discover: discoverProvider,
              multiServer: multiServerProvider,
              continueWatchingTitle: t.discover.continueWatching,
              latestMoviesTitle: t.discover.recentlyReleased,
            ),
          ),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: MainScreenFocusScope(
            focusSidebar: () {},
            focusContent: () {},
            isSidebarFocused: false,
            sideNavigationWidth: SideNavigationRailState.expandedWidth,
            reservedSideNavigationWidth: SideNavigationRailState.tvCollapsedWidth,
            foregroundLeft: 120.0,
            foregroundWidth: foregroundWidth,
            viewportWidth: 1280,
            child: Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: foregroundWidth,
                height: 720,
                child: DiscoverScreen(key: discoverKey),
              ),
            ),
          ),
        ),
      ),
    ),
  );

  return _TvDiscoverHarness(
    discoverProvider: discoverProvider,
    activeProfileProvider: activeProfileProvider,
    companionRemoteProvider: companionRemoteProvider,
    watchTogetherProvider: watchTogetherProvider,
    librariesProvider: librariesProvider,
    hiddenLibrariesProvider: hiddenLibrariesProvider,
    multiServerProvider: multiServerProvider,
    plexHome: plexHome,
    db: db,
  );
}

class _FakeMediaServerClient implements MediaServerClient {
  final List<MediaHub> hubs;

  _FakeMediaServerClient({required this.hubs});

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => const [];

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = defaultHubPreviewLimit, bool includePlaybackHubs = true}) async =>
      hubs;

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async => const [];

  @override
  Future<List<MediaItem>> fetchRecentlyWatched({int limit = 5}) async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeProfileRegistry extends ProfileRegistry {
  _FakeProfileRegistry(super.db);

  @override
  Stream<List<Profile>> watchProfiles() => Stream.value(const []);

  @override
  Future<List<Profile>> list() async => const [];
}

class _FakeConnectionRegistry extends ConnectionRegistry {
  _FakeConnectionRegistry(super.db);

  @override
  Stream<List<Connection>> watchConnections() => Stream.value(const []);

  @override
  Future<List<Connection>> list() async => const [];
}

class _FakeProfileConnectionRegistry extends ProfileConnectionRegistry {
  _FakeProfileConnectionRegistry(super.db);

  @override
  Stream<List<ProfileConnection>> watchAll() => Stream.value(const []);
}
