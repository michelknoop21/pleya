import 'dart:math' as math;

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
import 'package:pleya/theme/mono_tokens.dart';
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
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:pleya/widgets/tv_spotlight_background.dart';
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

  testWidgets('TV tab focus returns to discover browse rail instead of reload action', (tester) async {
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
    expect(find.byType(TvBrowseRail), findsOneWidget);

    final scale = TvLayoutConstants.scaleForSize(const Size(1280, 720));
    final spotlightLeft = (24 * scale).clamp(18.0, 40.0).toDouble();
    final spotlightBackground = tester.widget<TvSpotlightBackground>(find.byType(TvSpotlightBackground));
    expect(spotlightBackground.contentLeft, closeTo(spotlightLeft + currentForegroundLeft, 0.001));

    final railHeight = TvBrowseRailLayout.estimateHeight(
      size: const Size(foregroundWidth, 720),
      hubs: [hub],
      density: LibraryDensity.max,
      episodePosterMode: settings.read(SettingsService.episodePosterMode),
      fullCardLayout: settings.read(SettingsService.tvFullCardLayout),
      tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
    );
    // Netflix landing: at rest the rail shows its first hub in full and the hero
    // owns what's left (mirrors the spotlightBottom math in DiscoverScreen).
    final spotlightTop = (720 * MonoTokens.tvHeroContentTopFraction).clamp(64.0 * scale, 120.0 * scale).toDouble();
    final railScale = TvBrowseRailLayout.scaleForSize(const Size(foregroundWidth, 720));
    final firstHubMetrics = TvBrowseRailLayout.metricsForHub(
      hub: hub,
      availableWidth: foregroundWidth - TvBrowseRailLayout.horizontalInsetForScale(railScale),
      density: LibraryDensity.max,
      episodePosterMode: settings.read(SettingsService.episodePosterMode),
      scale: railScale,
      fullCardLayout: settings.read(SettingsService.tvFullCardLayout),
      tallPosterScale: TvBrowseRailLayout.compactTallPosterScale,
    );
    // The bottom focus-ring reserve is not part of the resting peek.
    final firstHubPeek =
        TvBrowseRailLayout.railTopPaddingForScale(railScale) +
        TvBrowseRailLayout.hubStripHeightForScale(railScale) +
        firstHubMetrics.height -
        firstHubMetrics.focusExtra;
    final railPeek = math.min(railHeight, math.min(firstHubPeek, 720 * MonoTokens.tvHomeRailMaxPeekFraction));
    final maxSpotlightBottom = (720 - spotlightTop - (MonoTokens.tvHeroMinInfoHeight * scale))
        .clamp(0.0, double.infinity)
        .toDouble();
    final expectedSpotlightBottom = (railPeek + MonoTokens.tvHeroRailGap * scale)
        .clamp(0.0, maxSpotlightBottom)
        .toDouble();
    expect(spotlightBackground.contentBottom, closeTo(expectedSpotlightBottom, 0.001));

    // The rail no longer receives the bleed via constructor (a per-flip param
    // would rebuild the whole rail); its bleed layer reads the scope's
    // sideNavigationWidth itself. Assert the rendered bleed position instead.
    final browseRail = tester.widget<TvBrowseRail>(find.byType(TvBrowseRail));
    expect(browseRail.backgroundBleedLeft, isNull);
    final railBleedPositions = tester
        .widgetList<Positioned>(find.descendant(of: find.byType(TvBrowseRail), matching: find.byType(Positioned)))
        .where((p) => p.left == -targetSidebarOffset);
    expect(railBleedPositions, isNotEmpty, reason: 'rail bleed layer positions at -sideNavigationWidth');

    final backgroundPosition = tester.widget<Positioned>(
      find.ancestor(of: find.byType(TvSpotlightBackground), matching: find.byType(Positioned)).first,
    );
    expect(backgroundPosition.left, -currentForegroundLeft);
    expect(backgroundPosition.width, 1280);

    tester.state<FocusableActionBarState>(find.byType(FocusableActionBar)).requestFocusOnFirst();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ActionBar[0]');

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_browse_rail');
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    tester.state<FocusableActionBarState>(find.byType(FocusableActionBar)).requestFocusOnFirst();
    await tester.pump();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ActionBar[0]');

    (discoverKey.currentState! as FocusableTab).focusActiveTabIfReady();
    (discoverKey.currentState! as TabVisibilityAware).onTabHidden();
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'ActionBar[0]');

    (discoverKey.currentState! as TabVisibilityAware).onTabShown();
    (discoverKey.currentState! as FocusableTab).focusActiveTabIfReady();
    await tester.pump();
    await tester.pump();

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_browse_rail');
  });

  // Fase-0 baseline for Pleya Unified TV 2026 (docs/tvos-unified-experience.md
  // hoofdstuk 27): this group locks in the existing Home-focus traversal that
  // fase 0 must not change before any unified-catalog work begins. It asserts
  // what DiscoverScreen actually does today on TV — including where it
  // diverges from the intended hoofdstuk 7 focus contract (e.g. Up from the
  // browse rail always lands on the hero Play pill, never on a "last used"
  // hero CTA) — not what a future phase should make it do.
  group('Home-focus baseline (TV)', () {
    testWidgets('cold TV focus lands on the hero Play pill when a spotlight item exists', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    });

    testWidgets('Down from the hero Play pill reaches the first browse row', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_browse_rail');
    });

    testWidgets('Up from the first browse row returns focus to the hero Play pill', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
      await tester.pump();
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_browse_rail');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowUp);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowUp);
      // _focusTvHeroPlay drops the rail reveal and re-requests focus on the
      // next frame, so this needs more than one pump to settle.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 350));

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
    });

    testWidgets('Right from hero Play moves to hero More-info, and Left moves back', (tester) async {
      final key = await _pumpTvDiscoverScreen(tester);
      addTearDown(key.disposeAll);

      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowRight);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_info');

      await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowLeft);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pump();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tv_hero_play');
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
/// global hub ('hub_1') carrying one item so a hero spotlight item always
/// exists (see [DiscoverScreenState._defaultSpotlightItem]). Reused by the
/// Home-focus baseline tests so they exercise the real focus wiring instead
/// of a hand-rolled substitute.
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
