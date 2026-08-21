import 'dart:async';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/screens/discover_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/widgets/clickable_cursor.dart';
import 'package:pleya/widgets/fitting_title_text.dart';
import 'package:pleya/widgets/hub_section.dart';
import 'package:pleya/widgets/media_card.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';

/// The discover billboard used to be one large hidden play button: a tap
/// anywhere on it called `navigateToMediaItem(playDirectly: true)`. Any stray
/// click — a menu label missed by a few pixels, a click that woke the window —
/// started a film. It opens the detail page now, and only the Afspelen pill
/// plays.
///
/// These tests drive the real [DiscoverScreen] in non-TV mode so they exercise
/// the shipped gesture and the real navigation call, not a stub.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(false);
    TvDetectionService.setForceTVSync(false);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  /// Pumps the screen and returns the observer that records pushed routes.
  ///
  /// [size] and [platform] default to the original desktop-ish 1280x800,
  /// non-iOS pump every existing test in this file already relied on.
  /// [continueWatching] feeds the rail directly below the hero, so tests can
  /// measure the real gap between the hero's pagination row and the "Verder
  /// kijken" heading, or the rail's card count.
  Future<_RouteSpy> pumpDiscover(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    TargetPlatform? platform,
    List<MediaItem> continueWatching = const [],
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
    });

    final settings = await SettingsService.getInstance();
    // Pin the setting that used to turn the billboard tap into playback, so the
    // test cannot pass for the wrong reason.
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.play);

    // No artwork at all: `billboardArt` then returns null and the whole
    // CachedNetworkImage subtree is skipped, which keeps the fake client out of
    // image URL territory.
    final movie = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Movie 1',
      serverId: 'server_1',
      serverName: 'Server',
      durationMs: 7200000,
    );

    final client = _FakeHeroClient(movie, continueWatching: continueWatching);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
    final hiddenLibrariesProvider = HiddenLibrariesProvider();
    final librariesProvider = LibrariesProvider();
    final watchTogetherProvider = WatchTogetherProvider();
    final companionRemoteProvider = CompanionRemoteProvider();

    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    JellyfinApiCache.initialize(db);
    final downloadManager = DownloadManagerService(
      database: db,
      storageService: DownloadStorageService.instance,
      clientResolver: (serverId, {clientScopeId}) => null,
    );
    downloadManager.recoveryFuture = Future<void>.value();
    final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
    await downloadProvider.ensureInitialized();
    final offlineModeProvider = OfflineModeProvider(manager);
    final offlineWatchSync = OfflineWatchSyncService(database: db, serverManager: manager);
    final watchStateStore = WatchStateStore();
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
      registry: _FakeProfileRegistry(db),
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

    addTearDown(() async {
      watchStateStore.dispose();
      offlineWatchSync.dispose();
      offlineModeProvider.dispose();
      downloadProvider.dispose();
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

    final spy = _RouteSpy();

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
            ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
            ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineModeProvider),
            ChangeNotifierProvider<OfflineWatchSyncService>.value(value: offlineWatchSync),
            ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
          ],
          child: MaterialApp(
            theme: platform == null ? monoTheme(dark: true) : monoTheme(dark: true).copyWith(platform: platform),
            navigatorObservers: [spy],
            // MainScreenFocusScope is a plain InheritedModel: on this non-TV
            // path nothing reads these values (only `_buildTvContent` does),
            // so they stay at the original hardcoded desktop-ish geometry
            // regardless of `size` — real per-size layout comes entirely
            // from `tester.view.physicalSize` via MediaQuery.
            home: MainScreenFocusScope(
              focusSidebar: () {},
              focusContent: () {},
              isSidebarFocused: false,
              sideNavigationWidth: 80,
              reservedSideNavigationWidth: 80,
              foregroundLeft: 80,
              foregroundWidth: 1200,
              viewportWidth: 1280,
              child: const DiscoverScreen(),
            ),
          ),
        ),
      ),
    );

    // Never pumpAndSettle: the hero carousel keeps rescheduling frames.
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 900));
    return spy;
  }

  testWidgets('the hero play button still starts playback', (tester) async {
    final spy = await pumpDiscover(tester);
    expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered');
    spy.pushed.clear();

    final pill = find.ancestor(of: find.text(t.common.play), matching: find.byType(InkWell)).first;
    await tester.tapAt(tester.getCenter(pill));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(spy.names, contains(kVideoPlayerRouteName));
    expect(spy.pushed, hasLength(1), reason: 'the pill wins the arena; the billboard tap must not also fire');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('tapping the billboard opens details instead of playing', (tester) async {
    final spy = await pumpDiscover(tester);
    expect(find.text('Movie 1'), findsOneWidget);
    spy.pushed.clear();

    final billboard = find.ancestor(of: find.text('Movie 1'), matching: find.byType(ClickableCursor)).first;
    final rect = tester.getRect(billboard);
    // Mid-height on the right: clear of the play pill bottom-left and of the
    // app bar actions in the top-right corner, both of which have their own tap.
    await tester.tapAt(Offset(rect.right - 60, rect.center.dy));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(
      spy.names,
      isNot(contains(kVideoPlayerRouteName)),
      reason: 'the billboard opens the title; only the pill plays',
    );
    expect(spy.pushed, hasLength(1), reason: 'it does navigate somewhere: the detail page');

    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// The hero has no `clearLogoPath` in these tests (the fake movie carries
  /// no artwork at all), so it falls back to `FittingTitleText` inside a
  /// `SizedBox(width: heroLogoWidth, height: heroLogoHeight)` — the same box
  /// `homeHeroLogoConstraints` sizes. Measuring that box's real rendered rect
  /// is a direct proof of which `HomeHeroContentTier` the screen resolved to,
  /// not just of the pure layout function in isolation.
  Rect measuredLogoBoxRect(WidgetTester tester) =>
      tester.getRect(find.ancestor(of: find.byType(FittingTitleText), matching: find.byType(SizedBox)).first);

  testWidgets('iPad in portrait resolves the tabletPortrait tier, not the phone formula', (tester) async {
    // 834x1194: iPad Air-class portrait. `PlatformDetector.isHandheldIOS`
    // needs `TargetPlatform.iOS`, not just a narrow physical size — a bare
    // `tester.view.physicalSize` change cannot exercise this branch on its
    // own, which is exactly what the tabletPortrait tier check depends on.
    await pumpDiscover(tester, size: const Size(834, 1194), platform: TargetPlatform.iOS);
    expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered');

    final logoRect = measuredLogoBoxRect(tester);
    // tabletPortrait at 834pt: width = min(520, min(834*0.55, 834-64)) ≈ 458.7,
    // height = (834*0.18).clamp(120,160) ≈ 150.1 — see home_hero_layout_test.dart.
    expect(logoRect.width, closeTo(458.7, 1.0));
    expect(logoRect.height, closeTo(150.1, 1.0));
    // The phone formula would have given only ≈400x96 at this width — the
    // whole point of the tabletPortrait-specific formula.
    expect(logoRect.width, greaterThan(400));
    expect(logoRect.height, greaterThan(96));

    final contentAlign = tester.widget<Align>(
      find.ancestor(of: find.byType(FittingTitleText), matching: find.byType(Align)).first,
    );
    expect(contentAlign.alignment, Alignment.center, reason: 'tabletPortrait stays centred like phone');

    final contentPositioned = tester.widget<Positioned>(
      find.ancestor(of: find.byType(FittingTitleText), matching: find.byType(Positioned)).first,
    );
    expect(contentPositioned.bottom, closeTo(48, 0.5), reason: 'tabletPortrait shares the phone contentBottomInset');

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  testWidgets('iPad in landscape keeps the existing wide-content layout unchanged', (tester) async {
    // 1194x834 — width > height, i.e. actually landscape. Same device class
    // as the portrait case above (834x1194), rotated: orientation is what
    // must flip the tier here, not the raw width alone.
    await pumpDiscover(tester, size: const Size(1194, 834), platform: TargetPlatform.iOS);
    expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered');

    final logoRect = measuredLogoBoxRect(tester);
    expect(logoRect.width, closeTo(400, 0.5), reason: 'wide tier keeps its fixed 400x120 box');
    expect(logoRect.height, closeTo(120, 0.5));

    // Direct proof of tier == wide / tabletPortrait == false: the real
    // Align and Positioned the production tree resolved to, not just the
    // pure-function output in isolation.
    final contentAlign = tester.widget<Align>(
      find.ancestor(of: find.byType(FittingTitleText), matching: find.byType(Align)).first,
    );
    expect(contentAlign.alignment, Alignment.centerLeft, reason: 'alignLeft must be true on the wide tier');

    final contentPositioned = tester.widget<Positioned>(
      find.ancestor(of: find.byType(FittingTitleText), matching: find.byType(Positioned)).first,
    );
    expect(contentPositioned.bottom, closeTo(80, 0.5), reason: 'wide tier keeps its unchanged bottom: 80 inset');

    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox.shrink());
  });

  /// A single 16:9 episode so the first rail renders in its wide layout —
  /// the same shape `_firstRailHeight` sizes the hero against.
  MediaItem wideOnDeckItem() => MediaItem(
    id: 'episode_1',
    backend: MediaBackend.plex,
    kind: MediaKind.episode,
    title: 'Episode 1',
    grandparentTitle: 'Show',
    serverId: 'server_1',
    serverName: 'Server',
    durationMs: 1800000,
    viewOffsetMs: 60000,
  );

  Future<void> expectPaginationToRailHeadingWithinBand(
    WidgetTester tester, {
    required Size size,
    TargetPlatform? platform,
    required num min,
    required num max,
  }) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.episodePosterMode, EpisodePosterMode.episodeThumbnail);
    await pumpDiscover(tester, size: size, platform: platform, continueWatching: [wideOnDeckItem()]);
    // The continue-watching fetch resolves asynchronously; give it a couple
    // more frames to land and rebuild the rail under the hero.
    await tester.pump();
    await tester.pump();

    expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered');
    expect(find.text(t.discover.continueWatching), findsOneWidget, reason: 'the rail rendered');

    final paginationRect = tester.getRect(find.byKey(DiscoverScreen.heroPaginationKey));
    final headingRect = tester.getRect(find.text(t.discover.continueWatching));
    final gap = headingRect.top - paginationRect.bottom;

    expect(gap, inInclusiveRange(min, max), reason: 'size=$size platform=$platform gap=$gap');

    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('phone: the real gap between the pagination row and "Verder kijken" is 16-20pt', (tester) async {
    await expectPaginationToRailHeadingWithinBand(tester, size: const Size(402, 874), min: 16, max: 20);
  });

  testWidgets('iPad portrait: the real gap between the pagination row and "Verder kijken" is 16-24pt', (tester) async {
    await expectPaginationToRailHeadingWithinBand(
      tester,
      size: const Size(834, 1194),
      platform: TargetPlatform.iOS,
      min: 16,
      max: 24,
    );
  });

  /// Pumps the real screen — real `HubSection`, real `ListView.builder`, real
  /// `MediaCard`s — with a continue-watching hub of eight 16:9 episodes and
  /// counts how many card rects land fully inside [width]. `find.byType`
  /// only returns what `ListView.builder` actually built (its viewport plus
  /// a small cache extent), so "fully inside the viewport" is a real
  /// left/right rect check, not an assumption about how many got built.
  Future<void> expectExactlyThreeFullRailCards(
    WidgetTester tester, {
    required double width,
    required double height,
  }) async {
    final settings = await SettingsService.getInstance();
    await settings.write(SettingsService.episodePosterMode, EpisodePosterMode.episodeThumbnail);
    await settings.write(SettingsService.libraryDensity, LibraryDensity.defaultValue);

    final items = List.generate(
      8,
      (i) => MediaItem(
        id: 'episode_$i',
        backend: MediaBackend.plex,
        kind: MediaKind.episode,
        title: 'Episode $i',
        grandparentTitle: 'Show',
        serverId: 'server_1',
        serverName: 'Server',
        durationMs: 1800000,
      ),
    );

    await pumpDiscover(tester, size: Size(width, height), platform: TargetPlatform.iOS, continueWatching: items);
    await tester.pump();
    await tester.pump();

    expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered');
    expect(find.text(t.discover.continueWatching), findsOneWidget, reason: 'the rail rendered');
    // No second hub/section: `_FakeHeroClient.fetchGlobalHubs` returns none,
    // so exactly one HubSection existing is direct proof no next section is
    // in the tree to peek into the viewport.
    expect(find.byType(HubSection), findsOneWidget, reason: 'no next section below the rail');

    final cardFinder = find.byType(MediaCard);
    final cardCount = tester.widgetList(cardFinder).length;
    final rects = [for (var i = 0; i < cardCount; i++) tester.getRect(cardFinder.at(i))];
    final fullyVisible = rects.where((r) => r.left >= -0.5 && r.right <= width + 0.5).length;

    expect(fullyVisible, 3, reason: 'width=$width expected exactly 3 full cards, got $fullyVisible from rects=$rects');
    expect(tester.takeException(), isNull, reason: 'width=$width');

    await tester.pumpWidget(const SizedBox.shrink());
  }

  testWidgets('iPad rail: exactly 3 full 16:9 cards at 768pt, default density', (tester) async {
    await expectExactlyThreeFullRailCards(tester, width: 768, height: 1024);
  });

  testWidgets('iPad rail: exactly 3 full 16:9 cards at 834pt, default density', (tester) async {
    await expectExactlyThreeFullRailCards(tester, width: 834, height: 1194);
  });

  testWidgets('iPad rail: exactly 3 full 16:9 cards at 1024pt, default density', (tester) async {
    await expectExactlyThreeFullRailCards(tester, width: 1024, height: 1366);
  });
}

/// Records what the screen pushed, then drops it again.
///
/// The assertion is about which route the production code chose, not about the
/// destination rendering: a real [VideoPlayerScreen] would spin up mpv and a
/// real detail screen wants its own provider tree, neither of which says
/// anything about the gesture under test. The route is recorded before it is
/// removed, so nothing is hidden.
class _RouteSpy extends NavigatorObserver {
  final pushed = <Route<dynamic>>[];

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    pushed.add(route);
    if (previousRoute == null) return; // the home route itself
    scheduleMicrotask(() => route.navigator?.removeRoute(route));
  }

  Iterable<String?> get names => pushed.map((route) => route.settings.name);
}

class _FakeHeroClient implements MediaServerClient {
  _FakeHeroClient(this.movie, {this.continueWatching = const []});

  final MediaItem movie;
  final List<MediaItem> continueWatching;

  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<List<MediaItem>> fetchRecentlyAdded({int limit = 50}) async => [movie];

  @override
  Future<List<MediaHub>> fetchGlobalHubs({int limit = defaultHubPreviewLimit, bool includePlaybackHubs = true}) async =>
      const [];

  @override
  Future<List<MediaItem>> fetchContinueWatching({int? count = 20}) async => continueWatching;

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
