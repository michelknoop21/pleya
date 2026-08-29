import 'dart:async';

import 'package:cached_network_image_ce/cached_network_image.dart';
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
import 'package:pleya/utils/home_hero_layout.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/watch_together/watch_together.dart';
import 'package:pleya/widgets/clickable_cursor.dart';
import 'package:pleya/widgets/fitting_title_text.dart';
import 'package:pleya/widgets/hub_section.dart';
import 'package:pleya/widgets/home_hero_artwork.dart';
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
  /// [topViewPadding] fills `MediaQuery.viewPaddingOf(context).top` — the
  /// Dynamic Island / notch inset the hero's sharp layer has to clear. Set in
  /// logical pixels; `devicePixelRatio` is pinned to 1.0 just below, so no
  /// conversion is needed. Left at null the view keeps its default zero
  /// padding, which is what every pre-existing test in this file relies on.
  ///
  /// [heroSquarePath] / [heroArtPath] give the hero item artwork, so
  /// `HomeHeroArtwork` is actually built and its frame rect can be measured.
  /// Without either, `billboardArt` returns null and the whole artwork
  /// subtree is skipped (which is exactly what the activation tests want).
  Future<_RouteSpy> pumpDiscover(
    WidgetTester tester, {
    Size size = const Size(1280, 800),
    TargetPlatform? platform,
    List<MediaItem> continueWatching = const [],
    double? topViewPadding,
    String? heroSquarePath,
    String? heroArtPath,
  }) async {
    tester.view.devicePixelRatio = 1.0;
    tester.view.physicalSize = size;
    if (topViewPadding != null) {
      tester.view.viewPadding = FakeViewPadding(top: topViewPadding);
      tester.view.padding = FakeViewPadding(top: topViewPadding);
    }
    addTearDown(() {
      tester.view.resetDevicePixelRatio();
      tester.view.resetPhysicalSize();
      tester.view.resetViewPadding();
      tester.view.resetPadding();
    });

    final settings = await SettingsService.getInstance();
    // Pin the setting that used to turn the billboard tap into playback, so the
    // test cannot pass for the wrong reason.
    await settings.write(SettingsService.continueWatchingAction, ContinueWatchingAction.play);

    // No artwork at all by default: `billboardArt` then returns null and the
    // whole CachedNetworkImage subtree is skipped, which keeps the fake client
    // out of image URL territory. Tests that need to measure the artwork layer
    // pass [heroSquarePath] or [heroArtPath]; `_FakeHeroClient.thumbnailUrl`
    // then hands back an empty URL, so the image resolves through
    // `errorBuilder` instead of the network.
    final movie = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: 'Movie 1',
      serverId: 'server_1',
      serverName: 'Server',
      durationMs: 7200000,
      artPath: heroArtPath,
      backgroundSquarePath: heroSquarePath,
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

  /// Returns the measured gap so the caller asserts the band it expects: the
  /// number belongs in the test, not hidden in a shared helper.
  Future<double> measurePaginationToRailHeadingGap(
    WidgetTester tester, {
    required Size size,
    TargetPlatform? platform,
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

    await tester.pumpWidget(const SizedBox.shrink());
    return gap;
  }

  testWidgets('phone: the real gap between the pagination row and "Verder kijken" is 16-20pt', (tester) async {
    final gap = await measurePaginationToRailHeadingGap(tester, size: const Size(402, 874));
    expect(gap, inInclusiveRange(16, 20), reason: 'gap=$gap');
  });

  testWidgets('iPad portrait: the real gap between the pagination row and "Verder kijken" is 16-24pt', (tester) async {
    final gap = await measurePaginationToRailHeadingGap(
      tester,
      size: const Size(834, 1194),
      platform: TargetPlatform.iOS,
    );
    expect(gap, inInclusiveRange(16, 24), reason: 'gap=$gap');
  });

  /// Pumps the real screen — real `HubSection`, real `ListView.builder`, real
  /// `MediaCard`s — with a continue-watching hub of eight 16:9 episodes and
  /// counts how many card rects land fully inside [width]. `find.byType`
  /// only returns what `ListView.builder` actually built (its viewport plus
  /// a small cache extent), so "fully inside the viewport" is a real
  /// left/right rect check, not an assumption about how many got built.
  /// Returns how many rail cards land fully inside [width], so the caller
  /// asserts the count itself.
  Future<int> countFullyVisibleRailCards(WidgetTester tester, {required double width, required double height}) async {
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

    expect(tester.takeException(), isNull, reason: 'width=$width rects=$rects');

    await tester.pumpWidget(const SizedBox.shrink());
    return fullyVisible;
  }

  testWidgets('iPad rail: exactly 3 full 16:9 cards at 768pt, default density', (tester) async {
    final cards = await countFullyVisibleRailCards(tester, width: 768, height: 1024);
    expect(cards, 3, reason: 'expected exactly 3 full cards at 768pt, got $cards');
  });

  testWidgets('iPad rail: exactly 3 full 16:9 cards at 834pt, default density', (tester) async {
    final cards = await countFullyVisibleRailCards(tester, width: 834, height: 1194);
    expect(cards, 3, reason: 'expected exactly 3 full cards at 834pt, got $cards');
  });

  testWidgets('iPad rail: exactly 3 full 16:9 cards at 1024pt, default density', (tester) async {
    final cards = await countFullyVisibleRailCards(tester, width: 1024, height: 1366);
    expect(cards, 3, reason: 'expected exactly 3 full cards at 1024pt, got $cards');
  });

  /// The hero's sharp artwork island is top-anchored, so on an iPhone its top
  /// edge used to land under the Dynamic Island, and after that fix, under the
  /// overlaid appbar's own title/actions row — a hard seam right under it, or
  /// a grey-blue haze if the fade-in band was stretched to hide it.
  /// `requestedSharpTop` now starts the layer at the hardware safe area and
  /// draws it *behind* the whole control row, fading it in across the row so
  /// it reaches full opacity `homeHeroArtworkTopGap` below it — gated to
  /// iPhone-portrait only.
  ///
  /// These drive the real screen, not the pure layout function: the gate reads
  /// `Theme.of(context).platform`, `MediaQuery.orientationOf` and
  /// `MediaQuery.viewPaddingOf`, none of which a unit test on
  /// `homeHeroArtGeometry` can exercise.
  ///
  /// Every case also re-checks the four things this change was explicitly not
  /// allowed to move: hero height, the content column's bottom anchor, the
  /// pagination row, and the "Verder kijken" heading below the hero. The
  /// expected numbers are the measured pre-change baseline.
  group('sharp layer runs behind the control row', () {
    /// Baseline captured before the change, with the same fixtures.
    const paginationBottomPortrait = 665.31, headingTopPortrait = 685.31;
    const paginationBottomLandscape = 313.64, headingTopLandscape = 333.64;
    const paginationBottomIpad = 957.64, headingTopIpad = 977.64;

    Future<Rect> pumpAndMeasureFrame(
      WidgetTester tester, {
      required Size size,
      required TargetPlatform platform,
      required double topViewPadding,
      required double expectedPaginationBottom,
      required double expectedHeadingTop,
      required double expectedFrameWidth,
      required double expectedFrameHeight,
      String? heroArtPath,
      bool checkControlRowGap = false,
    }) async {
      await pumpDiscover(
        tester,
        size: size,
        platform: platform,
        topViewPadding: topViewPadding,
        heroSquarePath: heroArtPath == null ? '/square' : null,
        heroArtPath: heroArtPath,
        continueWatching: [wideOnDeckItem()],
      );
      await tester.pump();
      await tester.pump();

      final label = 'size=$size platform=$platform viewPadding=$topViewPadding';
      expect(find.text('Movie 1'), findsOneWidget, reason: 'the hero rendered: $label');

      final frame = tester.getRect(find.byKey(HomeHeroArtwork.frameKey));
      expect(frame.width, closeTo(expectedFrameWidth, 0.5), reason: label);
      expect(frame.height, closeTo(expectedFrameHeight, 0.5), reason: label);
      expect(frame.center.dx, closeTo(size.width / 2, 0.5), reason: 'horizontally centred: $label');

      // Nothing below the artwork may move.
      final pagination = tester.getRect(find.byKey(DiscoverScreen.heroPaginationKey));
      final heading = tester.getRect(find.text(t.discover.continueWatching));
      expect(pagination.bottom, closeTo(expectedPaginationBottom, 0.5), reason: 'pagination moved: $label');
      expect(heading.top, closeTo(expectedHeadingTop, 0.5), reason: '"Verder kijken" moved: $label');

      if (checkControlRowGap) {
        // The anchor is the control row itself (the 48pt tap-target Row), not
        // the appbar's decorated box around it: the box's own bottom padding
        // belongs to its layout tail, not to the artwork above it.
        final controls = tester.getRect(find.byKey(DiscoverScreen.appBarControlsKey));
        // The layer's own top sits at the safe area and runs *behind* the
        // control row — it no longer clears it. What still lands
        // homeHeroArtworkTopGap below the row is the point where the top
        // blend finishes, i.e. frame.top + the blend band.
        final blend = homeHeroSharpTopAnchors(statusBarHeight: topViewPadding).blend;
        expect(frame.top, closeTo(topViewPadding, 0.5), reason: 'sharp layer starts at the safe area: $label');
        expect(
          frame.top + blend,
          closeTo(controls.bottom + homeHeroArtworkTopGap, 0.5),
          reason: 'sharp layer reaches full opacity homeHeroArtworkTopGap below the control row: $label',
        );
        expect(frame.top, lessThan(controls.bottom), reason: 'sharp layer runs behind the control row: $label');
        expect(frame.left, closeTo(0, 0.5), reason: 'still runs edge to edge: $label');
        expect(frame.width, closeTo(size.width, 0.5), reason: 'still full width, not shrunk: $label');

        final artwork = tester.getRect(find.byKey(HomeHeroArtwork.artworkKey));
        final ambient = tester.getRect(find.byKey(HomeHeroArtwork.ambientKey));
        expect(ambient.top, lessThanOrEqualTo(0), reason: 'ambient wash still covers y=0: $label');
        expect(
          ambient.bottom,
          greaterThanOrEqualTo(artwork.bottom),
          reason: 'ambient wash still covers the hero floor: $label',
        );
      }

      expect(tester.takeException(), isNull, reason: label);
      addTearDown(() async => tester.pumpWidget(const SizedBox.shrink()));
      return frame;
    }

    testWidgets('iPhone portrait with a 62pt safe area starts the sharp layer at the safe area', (tester) async {
      final frame = await pumpAndMeasureFrame(
        tester,
        size: const Size(402, 874),
        platform: TargetPlatform.iOS,
        topViewPadding: 62,
        expectedPaginationBottom: paginationBottomPortrait,
        expectedHeadingTop: headingTopPortrait,
        // Edge to edge: the full canvas width, square source so height == width.
        expectedFrameWidth: 402,
        expectedFrameHeight: 402,
        checkControlRowGap: true,
      );
      expect(frame.top, closeTo(62, 0.5), reason: 'viewPadding.top, not homeHeroSharpOpaqueInset(statusBarHeight: 62)');
      expect(frame.left, closeTo(0, 0.5), reason: 'starts at the left edge');
      expect(frame.right, closeTo(402, 0.5), reason: 'runs to the right edge');
    });

    testWidgets('iPhone portrait, widescreen source: full width behind the control row', (tester) async {
      // What the app actually shows most of the time — a 16:9 backdrop. This
      // is the case that regressed to a 320pt centred card.
      final frame = await pumpAndMeasureFrame(
        tester,
        size: const Size(402, 874),
        platform: TargetPlatform.iOS,
        topViewPadding: 62,
        expectedPaginationBottom: paginationBottomPortrait,
        expectedHeadingTop: headingTopPortrait,
        expectedFrameWidth: 402,
        expectedFrameHeight: 402 * 9 / 16,
        heroArtPath: '/backdrop',
        checkControlRowGap: true,
      );
      expect(frame.top, closeTo(62, 0.5), reason: 'viewPadding.top, not homeHeroSharpOpaqueInset(statusBarHeight: 62)');
      expect(frame.left, closeTo(0, 0.5));
      expect(frame.right, closeTo(402, 0.5));

      final images = tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)).toList();
      expect(images.last.fit, BoxFit.contain, reason: 'crop-free: cover would zoom the source and cut its sides');
    });

    testWidgets('iPad portrait keeps the sharp layer at 0', (tester) async {
      final frame = await pumpAndMeasureFrame(
        tester,
        size: const Size(834, 1194),
        platform: TargetPlatform.iOS,
        topViewPadding: 24,
        expectedPaginationBottom: paginationBottomIpad,
        expectedHeadingTop: headingTopIpad,
        expectedFrameWidth: 683.88,
        expectedFrameHeight: 683.88,
      );
      expect(frame.top, closeTo(0, 0.5), reason: 'shortestSide 834 is past the 600pt phone breakpoint');
    });

    testWidgets('iPhone landscape keeps the sharp layer at 0', (tester) async {
      final frame = await pumpAndMeasureFrame(
        tester,
        size: const Size(874, 402),
        platform: TargetPlatform.iOS,
        topViewPadding: 62,
        expectedPaginationBottom: paginationBottomLandscape,
        expectedHeadingTop: headingTopLandscape,
        // A wide box: full-bleed cover, which ignores the inset outright.
        expectedFrameWidth: 874,
        expectedFrameHeight: 329.64,
      );
      expect(frame.top, closeTo(0, 0.5), reason: 'the cutout is on the side in landscape');
    });

    testWidgets('Android portrait keeps the sharp layer at 0', (tester) async {
      final frame = await pumpAndMeasureFrame(
        tester,
        size: const Size(402, 874),
        platform: TargetPlatform.android,
        topViewPadding: 62,
        expectedPaginationBottom: paginationBottomPortrait,
        expectedHeadingTop: headingTopPortrait,
        expectedFrameWidth: 329.64,
        expectedFrameHeight: 329.64,
      );
      expect(frame.top, closeTo(0, 0.5), reason: 'isHandheldIOS is false on android');
    });

    testWidgets('iPhone portrait without a safe area: the control row is still there, at 64', (tester) async {
      // Proves the opaque anchor follows the safe area on top of a fixed
      // control-row block, not a constant on its own: with no hardware safe
      // area, the layer's top starts at y = 0 (nothing to clear), but the
      // control row is still there, so it only reaches full opacity at
      // homeHeroSharpOpaqueInset(statusBarHeight: 0) == 64, not 0 — that is
      // what checkControlRowGap verifies via the blend band. The composition
      // is unchanged — full width either way.
      final frame = await pumpAndMeasureFrame(
        tester,
        size: const Size(402, 874),
        platform: TargetPlatform.iOS,
        topViewPadding: 0,
        expectedPaginationBottom: paginationBottomPortrait,
        expectedHeadingTop: headingTopPortrait,
        expectedFrameWidth: 402,
        expectedFrameHeight: 402,
        checkControlRowGap: true,
      );
      expect(frame.top, closeTo(0, 0.5), reason: 'no safe area to start behind');
      expect(frame.left, closeTo(0, 0.5));
    });
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

  /// Empty URL on purpose: `CachedNetworkImage` then resolves straight through
  /// its `errorBuilder` to a `ColoredBox`, so the artwork layers lay out at
  /// their real geometry without any network in a widget test.
  @override
  String thumbnailUrl(String? path, {int? width, int? height}) => '';

  /// The hero's art-enrichment pass calls this when an item has artwork but no
  /// clear logo. Handing back the same item keeps that pass a no-op instead of
  /// letting it throw into `_enrichSpotlightArt`'s catch-all.
  @override
  Future<MediaItem?> fetchItem(String id) async => movie;

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
