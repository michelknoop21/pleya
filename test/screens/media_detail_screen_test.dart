import 'dart:async';
import 'package:drift/native.dart';
import 'package:pleya/media/ids.dart';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/source_availability.dart';
import 'package:pleya/media/unified/source_coverage_state.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_route_context.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:pleya/screens/tv/tv_media_source_picker_route.dart';
import 'package:pleya/screens/tv/tv_unified_activation.dart';
import 'package:pleya/services/unified_catalog/source_preference_store.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:pleya/widgets/episode_card.dart';
import 'package:pleya/widgets/media_progress_bar.dart';
import 'package:pleya/widgets/tv_browse_rail.dart';
import 'package:provider/provider.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/profile_navigation.dart';
import '../test_helpers/notice_layer.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // A notice keeps an auto-dismiss timer, and the test framework fails a test
  // that leaves one pending.
  tearDown(resetNotices);

  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
    LocaleSettings.setLocaleSync(AppLocale.en);
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('TV detail scales fallback title to fit logo bounds', (tester) async {
    await SettingsService.getInstance();
    tester.view.physicalSize = const Size(800, 480);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const title = 'The Surprisingly Long Movie Title That Needs Two Whole Lines';
    final movie = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: title,
      summary: 'A compact viewport should make the fallback title shrink before it can overlap the detail text.',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();

    final titleText = tester.widget<Text>(find.text(title));
    final baseFontSize = 56 * TvLayoutConstants.scaleForSize(const Size(800, 480));
    expect(titleText.style?.fontSize, isNotNull);
    expect(titleText.style!.fontSize!, lessThan(baseFontSize));
  });

  testWidgets('TV detail reveals without waiting for directional input', (tester) async {
    await SettingsService.getInstance();

    final movie = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Idle Reveal Movie',
      summary: 'The detail foreground should appear without needing a D-pad frame.',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
        ),
      ),
    );

    final revealGate = find.byWidgetPredicate(
      (widget) => widget is AnimatedOpacity && widget.duration == const Duration(milliseconds: 160),
      description: 'TV detail reveal AnimatedOpacity',
    );
    expect(revealGate, findsOneWidget);
    expect(tester.widget<AnimatedOpacity>(revealGate).opacity, 0);

    await tester.pump();

    expect(tester.widget<AnimatedOpacity>(revealGate).opacity, 1);
  });

  testWidgets('TV detail shows Rotten Tomatoes rating badge in metadata line', (tester) async {
    await SettingsService.getInstance();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const movie = MediaItem.plex(
      id: 'movie_1',
      kind: MediaKind.movie,
      title: 'Rotten Tomatoes Movie',
      summary: 'The TV detail metadata line should use the rating source badge.',
      rating: 6.2,
      ratingImage: 'rottentomatoes://image.rating.ripe',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('62%'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
    expect(find.textContaining('★ 6.2', findRichText: true), findsNothing);
  });

  testWidgets('TV detail falls back to Rotten Tomatoes audience rating in metadata line', (tester) async {
    await SettingsService.getInstance();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const movie = MediaItem.plex(
      id: 'movie_1',
      kind: MediaKind.movie,
      title: 'Audience Rating Movie',
      summary: 'The TV detail metadata line should use the available audience source badge.',
      audienceRating: 8.7,
      audienceRatingImage: 'rottentomatoes://image.rating.upright',
    );

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('87%'), findsOneWidget);
    expect(find.byType(SvgPicture), findsOneWidget);
  });

  testWidgets('TV detail defaults to first regular season when specials precede it', (tester) async {
    await SettingsService.getInstance();

    final show = MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final specials = MediaItem(
      id: 'season_0',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Specials',
      index: 0,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season1 = MediaItem(
      id: 'season_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      index: 1,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final specialEpisode = MediaItem(
      id: 'episode_special_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Special 1',
      index: 1,
      parentId: specials.id,
      parentIndex: specials.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode1 = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 1',
      index: 1,
      parentId: season1.id,
      parentIndex: season1.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );

    final descendantsCompleter = Completer<List<MediaItem>>();
    final client = _FakeMediaServerClient(
      show: show,
      childrenByParent: {
        show.id: [specials, season1],
        specials.id: [specialEpisode],
        season1.id: [episode1],
      },
      pendingPlayableDescendants: descendantsCompleter.future,
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: SizedBox(width: 1280, height: 720, child: MediaDetailScreen(metadata: show)),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Specials'), findsNothing);
    expect(find.text('S1E1'), findsOneWidget);
  });

  testWidgets('TV detail summary uses light theme foreground color', (tester) async {
    await SettingsService.getInstance();
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    const summary = 'Light theme detail text should stay readable.';
    final movie = MediaItem(
      id: 'movie_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Readable Movie',
      summary: summary,
    );
    final theme = monoTheme(dark: false);

    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: theme,
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    final summaryText = tester.widget<Text>(find.text(summary));
    // This block sits on the fullscreen spotlight artwork, which does not flip
    // with the theme. Dimming that reads as "secondary" white-on-dark reads as
    // washed out when it is near-black over bright artwork, so light mode has
    // to keep noticeably more ink than dark's 0.78.
    final color = summaryText.style?.color;
    expect(color, isNotNull);
    expect(color!.r, theme.colorScheme.onSurface.r);
    expect(color.a, greaterThanOrEqualTo(0.9));
  });

  testWidgets('TV detail shows every season tab and prefetches adjacent first page', (tester) async {
    await SettingsService.getInstance();

    final show = MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final season1 = MediaItem(
      id: 'season_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      index: 1,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season2 = MediaItem(
      id: 'season_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 2',
      index: 2,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode1 = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 1',
      index: 1,
      parentId: season1.id,
      parentIndex: season1.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode2 = MediaItem(
      id: 'episode_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 2',
      index: 1,
      parentId: season2.id,
      parentIndex: season2.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );

    final client = _FakeMediaServerClient(
      show: show,
      childrenByParent: {
        show.id: [season1, season2],
        season1.id: [episode1],
        season2.id: [episode2],
      },
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: SizedBox(width: 1280, height: 720, child: MediaDetailScreen(metadata: show)),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Every season tab is derived from the season list, so both appear
    // immediately. TV warms only the selected first page plus the adjacent first
    // page; it still does not walk the whole show or load page 2+.
    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
    expect(client.childrenPageCalls.map((call) => call.parentId), containsAll([season1.id, season2.id]));
    expect(client.childrenPageCalls.every((call) => call.start == 0 && call.size == 200), isTrue);
  });

  testWidgets('TV detail keeps every season tab when a season episode load fails', (tester) async {
    await SettingsService.getInstance();

    final show = MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final season1 = MediaItem(
      id: 'season_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      index: 1,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season2 = MediaItem(
      id: 'season_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 2',
      index: 2,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode1 = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 1',
      index: 1,
      parentId: season1.id,
      parentIndex: season1.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode2 = MediaItem(
      id: 'episode_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 2',
      index: 1,
      parentId: season2.id,
      parentIndex: season2.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );

    final client = _FakeMediaServerClient(
      show: show,
      childrenByParent: {
        show.id: [season1, season2],
        season1.id: [episode1],
        season2.id: [episode2],
      },
      childrenPageErrors: {season1.id: Exception('season cache failed')},
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: SizedBox(width: 1280, height: 720, child: MediaDetailScreen(metadata: show)),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Season 1'), findsOneWidget);
    expect(find.text('Season 2'), findsOneWidget);
  });

  testWidgets('TV detail completes adjacent prefetch after focus moves to that season', (tester) async {
    await SettingsService.getInstance();

    final show = MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: 'server_1',
      serverName: 'Server',
    );
    final season1 = MediaItem(
      id: 'season_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 1',
      index: 1,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season2 = MediaItem(
      id: 'season_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season 2',
      index: 2,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode1 = MediaItem(
      id: 'episode_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 1',
      index: 1,
      parentId: season1.id,
      parentIndex: season1.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final episode2 = MediaItem(
      id: 'episode_2',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode 2',
      index: 1,
      parentId: season2.id,
      parentIndex: season2.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );
    final season2Completer = Completer<List<MediaItem>>();
    final client = _FakeMediaServerClient(
      show: show,
      childrenByParent: {
        show.id: [season1, season2],
        season1.id: [episode1],
      },
      childrenPageFutures: {season2.id: season2Completer.future},
    );
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final provider = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(provider.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<MultiServerProvider>.value(
          value: provider,
          child: MaterialApp(
            builder: withNoticeLayer(),
            theme: monoTheme(dark: true),
            home: withProfileNavigationScope(
              child: SizedBox(width: 1280, height: 720, child: MediaDetailScreen(metadata: show)),
            ),
          ),
        ),
      ),
    );

    await tester.pump();
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    tester.state<TvBrowseRailState>(find.byType(TvBrowseRail)).requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    expect(find.text('Episode 2'), findsNothing);

    season2Completer.complete([episode2]);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    expect(find.text('Episode 2'), findsOneWidget);
  });

  group('watch state freshness (phone layout)', () {
    MediaItem buildShow() => MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      leafCount: 4,
      viewedLeafCount: 0,
      serverId: 'server_1',
      serverName: 'Server',
    );

    MediaItem buildSeason(MediaItem show, int index) => MediaItem(
      id: 'season_$index',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season $index',
      index: index,
      leafCount: 2,
      viewedLeafCount: 0,
      parentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );

    MediaItem buildEpisode(MediaItem show, MediaItem season, int index) => MediaItem(
      id: '${season.id}_episode_$index',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.episode,
      title: 'Episode S${season.index}E$index',
      index: index,
      durationMs: 30 * 60 * 1000,
      parentId: season.id,
      parentIndex: season.index,
      grandparentId: show.id,
      serverId: show.serverId,
      serverName: show.serverName,
    );

    Future<void> pumpPhoneDetail(
      WidgetTester tester,
      _FakeMediaServerClient client,
      MediaItem show, {
      String? initialSeasonId,
      int? initialSeasonIndex,
      String? initialEpisodeId,
    }) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(1100, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

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

      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      final watchStateOverlay = WatchStateStore();

      addTearDown(() async {
        watchStateOverlay.dispose();
        downloadProvider.dispose();
        downloadManager.dispose();
        multiServerProvider.dispose();
        await db.close();
      });

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
              ChangeNotifierProvider<WatchStateStore>.value(value: watchStateOverlay),
            ],
            child: MaterialApp(
              builder: withNoticeLayer(),
              theme: monoTheme(dark: true),
              home: withProfileNavigationScope(
                child: MediaDetailScreen(
                  metadata: show,
                  initialSeasonId: initialSeasonId,
                  initialSeasonIndex: initialSeasonIndex,
                  initialEpisodeId: initialEpisodeId,
                ),
              ),
            ),
          ),
        ),
      );

      await tester.pump();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
    }

    Finder episodeCardFor(String title) => find.ancestor(of: find.text(title), matching: find.byType(EpisodeCard));

    bool episodeRowWatched(WidgetTester tester, String title) {
      final card = episodeCardFor(title);
      expect(card, findsOneWidget, reason: 'episode row "$title" should be visible');
      return tester.any(find.descendant(of: card, matching: find.byIcon(Symbols.check_rounded)));
    }

    bool episodeRowHasProgress(WidgetTester tester, String title) {
      final card = episodeCardFor(title);
      expect(card, findsOneWidget, reason: 'episode row "$title" should be visible');
      return tester.any(find.descendant(of: card, matching: find.byType(MediaProgressBar)));
    }

    Future<void> emit(WidgetTester tester, void Function() send) async {
      send();
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
    }

    testWidgets('phone detail focuses requested season tab', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: [buildEpisode(show, season1, 1)],
          season2.id: [buildEpisode(show, season2, 1)],
        },
      );

      await pumpPhoneDetail(tester, client, show, initialSeasonId: season2.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Episode S2E1'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'season_tab_1');
    });

    testWidgets('phone detail focuses requested episode row', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final episode2 = buildEpisode(show, season2, 2);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: [buildEpisode(show, season1, 1)],
          season2.id: [buildEpisode(show, season2, 1), episode2, buildEpisode(show, season2, 3)],
        },
      );

      await pumpPhoneDetail(
        tester,
        client,
        show,
        initialSeasonId: season2.id,
        initialSeasonIndex: season2.index,
        initialEpisodeId: episode2.id,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      expect(find.text('Episode S2E2'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'initial_episode');
    });

    testWidgets('phone detail keeps the first-episode role node when it is the target', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final episode1 = buildEpisode(show, season2, 1);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: [buildEpisode(show, season1, 1)],
          season2.id: [episode1, buildEpisode(show, season2, 2), buildEpisode(show, season2, 3)],
        },
      );

      await pumpPhoneDetail(
        tester,
        client,
        show,
        initialSeasonId: season2.id,
        initialSeasonIndex: season2.index,
        initialEpisodeId: episode1.id,
      );
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));

      // The first row keeps _firstEpisodeFocusNode (so season-tab DOWN keeps
      // working) and the initial focus lands on that node instead.
      expect(find.text('Episode S2E1'), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'first_episode');
    });

    testWidgets('marking the show watched flips every visible episode row', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final episodes = [buildEpisode(show, season1, 1), buildEpisode(show, season1, 2)];
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: episodes,
          season2.id: [buildEpisode(show, season2, 1), buildEpisode(show, season2, 2)],
        },
      );

      await pumpPhoneDetail(tester, client, show);
      expect(episodeRowWatched(tester, 'Episode S1E1'), isFalse);
      expect(episodeRowWatched(tester, 'Episode S1E2'), isFalse);

      await emit(tester, () => WatchStateNotifier().notifyWatched(item: show, isNowWatched: true));

      expect(episodeRowWatched(tester, 'Episode S1E1'), isTrue);
      expect(episodeRowWatched(tester, 'Episode S1E2'), isTrue);
    });

    testWidgets('container mark overrides an older per-episode patch', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final episode1 = buildEpisode(show, season1, 1);
      final episode2 = buildEpisode(show, season1, 2);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, buildSeason(show, 2)],
          season1.id: [episode1, episode2],
        },
      );

      await pumpPhoneDetail(tester, client, show);

      // Seed a session patch for one episode (e.g. user toggled it earlier).
      await emit(tester, () => WatchStateNotifier().notifyWatched(item: episode1, isNowWatched: false));
      expect(episodeRowWatched(tester, 'Episode S1E1'), isFalse);

      await emit(tester, () => WatchStateNotifier().notifyWatched(item: show, isNowWatched: true));

      expect(episodeRowWatched(tester, 'Episode S1E1'), isTrue);
      expect(episodeRowWatched(tester, 'Episode S1E2'), isTrue);
    });

    testWidgets('marking a season watched flips its episode rows', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: [buildEpisode(show, season1, 1), buildEpisode(show, season1, 2)],
          season2.id: [buildEpisode(show, season2, 1)],
        },
      );

      await pumpPhoneDetail(tester, client, show);

      await emit(tester, () => WatchStateNotifier().notifyWatched(item: season1, isNowWatched: true));

      expect(episodeRowWatched(tester, 'Episode S1E1'), isTrue);
      expect(episodeRowWatched(tester, 'Episode S1E2'), isTrue);
    });

    testWidgets('container mark clears progress, including after a season tab round-trip', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final episode1 = buildEpisode(show, season1, 1);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: [episode1, buildEpisode(show, season1, 2)],
          season2.id: [buildEpisode(show, season2, 1)],
        },
      );

      await pumpPhoneDetail(tester, client, show);

      // Played partway earlier in the session.
      await emit(
        tester,
        () => WatchStateNotifier().notifyProgress(item: episode1, viewOffset: 600000, duration: 1800000),
      );
      expect(episodeRowHasProgress(tester, 'Episode S1E1'), isTrue);

      await emit(tester, () => WatchStateNotifier().notifyWatched(item: show, isNowWatched: true));
      expect(episodeRowHasProgress(tester, 'Episode S1E1'), isFalse);
      expect(episodeRowWatched(tester, 'Episode S1E1'), isTrue);

      // Round-trip through another season tab; the cached page restore must not
      // resurrect the dead progress offset.
      await tester.tap(find.text('Season 2'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.tap(find.text('Season 1'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(episodeRowHasProgress(tester, 'Episode S1E1'), isFalse);
      expect(episodeRowWatched(tester, 'Episode S1E1'), isTrue);
    });

    MediaDetailPlaybackRefresh refresherFor(WidgetTester tester) =>
        tester.state(find.byType(MediaDetailScreen)) as MediaDetailPlaybackRefresh;

    testWidgets('refreshAfterPlayback reveals a server-side episode without a season jump or spinner', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final season2 = buildSeason(show, 2);
      final episode10 = buildEpisode(show, season1, 10);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1, season2],
          season1.id: [for (var i = 1; i <= 10; i++) buildEpisode(show, season1, i)],
          season2.id: [buildEpisode(show, season2, 1)],
        },
      );

      await pumpPhoneDetail(tester, client, show);
      expect(find.text('Episode S1E10'), findsOneWidget);
      expect(find.text('Episode S1E11'), findsNothing);

      // Server gained an episode while the screen stayed mounted — the
      // scenario the player's own episode queue already saw fresh, but the
      // detail screen's pager never re-fetched.
      client.childrenByParent[season1.id] = [for (var i = 1; i <= 11; i++) buildEpisode(show, season1, i)];

      await refresherFor(tester).refreshAfterPlayback(playedItemId: episode10.id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Episode S1E11'), findsOneWidget);
      // Still season 1 — a season jump would mean _loadFullMetadata/_loadSeasons
      // ran and rewrote _selectedSeasonIndex to the on-deck season.
      expect(find.text('Episode S1E1'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    testWidgets('revalidation grows the request past an exact page boundary (200 -> 201)', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1],
          season1.id: [for (var i = 1; i <= 200; i++) buildEpisode(show, season1, i)],
        },
      );

      await pumpPhoneDetail(tester, client, show);
      expect(find.text('Episode S1E200'), findsOneWidget);
      expect(find.text('Episode S1E201'), findsNothing);
      // Sanity: the initial load already asked for exactly one page (200);
      // hasMore was therefore false (200/200), which is what should trigger
      // growth below. max(pageSize, loaded) would ask for 200 again here and
      // miss the 201st episode entirely.
      expect(client.childrenPageCalls.where((c) => c.parentId == season1.id).last.size, 200);

      client.childrenByParent[season1.id] = [for (var i = 1; i <= 201; i++) buildEpisode(show, season1, i)];

      await refresherFor(tester).refreshAfterPlayback(playedItemId: 'season_1_episode_200');
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text('Episode S1E201'), findsOneWidget);
      expect(client.childrenPageCalls.where((c) => c.parentId == season1.id).last.size, greaterThan(200));
    });

    testWidgets('refreshAfterPlayback makes exactly one season-page request and skips fetchItem when covered', (
      tester,
    ) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final episodes = [buildEpisode(show, season1, 1), buildEpisode(show, season1, 2), buildEpisode(show, season1, 3)];
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1],
          season1.id: episodes,
        },
      );

      await pumpPhoneDetail(tester, client, show);
      final pageCallsBefore = client.childrenPageCalls.where((c) => c.parentId == season1.id).length;

      await refresherFor(tester).refreshAfterPlayback(playedItemId: episodes[1].id);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final pageCallsAfter = client.childrenPageCalls.where((c) => c.parentId == season1.id).length;
      expect(pageCallsAfter - pageCallsBefore, 1, reason: 'exactly one structural refresh, no duplicate');
      expect(client.fetchItemCalls, isEmpty, reason: 'the played episode was already in the revalidated page');
    });

    testWidgets('refreshAfterPlayback without a playedItemId (shuffle) still revalidates, never calls fetchItem', (
      tester,
    ) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final episodes = [buildEpisode(show, season1, 1), buildEpisode(show, season1, 2)];
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1],
          season1.id: episodes,
        },
      );

      await pumpPhoneDetail(tester, client, show);
      final pageCallsBefore = client.childrenPageCalls.where((c) => c.parentId == season1.id).length;

      await refresherFor(tester).refreshAfterPlayback();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      final pageCallsAfter = client.childrenPageCalls.where((c) => c.parentId == season1.id).length;
      expect(pageCallsAfter - pageCallsBefore, 1);
      expect(client.fetchItemCalls, isEmpty);
    });

    testWidgets('two concurrent refreshAfterPlayback calls do not leave the list stuck loading', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final episodes = [buildEpisode(show, season1, 1), buildEpisode(show, season1, 2)];
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1],
          season1.id: episodes,
        },
      );

      await pumpPhoneDetail(tester, client, show);
      final refresher = refresherFor(tester);

      // Fired back-to-back, not awaited individually: the second call's
      // beginFirstPageLoad guard must see the first still in flight and skip,
      // rather than bumping the generation out from under it.
      final first = refresher.refreshAfterPlayback(playedItemId: episodes.first.id);
      final second = refresher.refreshAfterPlayback(playedItemId: episodes.first.id);
      await Future.wait([first, second]);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.byType(CircularProgressIndicator), findsNothing);
      expect(find.text('Episode S1E1'), findsOneWidget);
      expect(find.text('Episode S1E2'), findsOneWidget);
    });

    testWidgets('app resume revalidates the visible episodes, with a cooldown against repeat probes', (tester) async {
      final show = buildShow();
      final season1 = buildSeason(show, 1);
      final client = _FakeMediaServerClient(
        show: show,
        childrenByParent: {
          show.id: [season1],
          season1.id: [buildEpisode(show, season1, 1)],
        },
      );

      await pumpPhoneDetail(tester, client, show);
      expect(find.text('Episode S1E2'), findsNothing);

      client.childrenByParent[season1.id] = [buildEpisode(show, season1, 1), buildEpisode(show, season1, 2)];

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.paused);
      await tester.pump();
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.inactive);
      await tester.pump();
      expect(find.text('Episode S1E2'), findsNothing, reason: 'paused/inactive must not trigger a revalidation');

      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Episode S1E2'), findsOneWidget);

      // A second resume right after must be suppressed by the cooldown, not
      // fire another request.
      client.childrenByParent[season1.id] = [
        buildEpisode(show, season1, 1),
        buildEpisode(show, season1, 2),
        buildEpisode(show, season1, 3),
      ];
      final pageCallsBeforeSecondResume = client.childrenPageCalls.where((c) => c.parentId == season1.id).length;
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(find.text('Episode S1E3'), findsNothing);
      expect(client.childrenPageCalls.where((c) => c.parentId == season1.id).length, pageCallsBeforeSecondResume);
    });
  });

  group('metadata loading is escapable', () {
    // The loading state used to be a PopScope(canPop: false) with an empty
    // callback around a Focus with no node and no focusable child — no back
    // key, no button, nothing. On a hanging network that stranded the user
    // until the (formerly 120s) receive timeout expired.
    testWidgets('a hanging metadata fetch still offers a way back', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final movie = MediaItem(
        id: 'movie_1',
        backend: MediaBackend.jellyfin,
        kind: MediaKind.movie,
        title: 'Stuck Movie',
        serverId: 'server_1',
        serverName: 'Server',
      );
      final client = _HangingMetadataClient();
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      var popped = false;
      await tester.pumpWidget(
        TranslationProvider(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(
              builder: withNoticeLayer(),
              theme: monoTheme(dark: true),
              home: Navigator(
                onDidRemovePage: (_) => popped = true,
                pages: [
                  MaterialPage<void>(
                    child: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
                  ),
                ],
              ),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Still loading — and the escape hatch is present and focusable.
      expect(find.byType(CircularProgressIndicator), findsWidgets);
      final cancel = find.text(t.common.cancel);
      expect(cancel, findsOneWidget);

      await tester.tap(cancel);
      await tester.pump();
      expect(popped, isTrue);

      // Let the abandoned request's timeout timer expire.
      await tester.pump(const Duration(seconds: 30));
    });
  });

  // F19/A14 (hoofdstuk 21.7): a detail load that genuinely fails — not
  // hangs — must offer "Andere bron kiezen" explicitly when the group has
  // another usable source, through the exact hoofdstuk 15 picker callback.
  group('F19/A14: detail load failure offers an alternative source', () {
    UnifiedMediaRouteContext routeContext({required List<String> sourceKeys, required String sourceKey}) =>
        UnifiedMediaRouteContext(
          groupId: 'g1',
          identity: CanonicalMediaIdentity.movie(title: 'Sintel', year: 2010),
          sourceKey: sourceKey,
          availableSourceKeys: sourceKeys,
          coverage: SourceCoverageState.complete(sourceKeys.toSet()),
          intent: UnifiedActivationIntent.details,
        );

    MediaItem sintel() => MediaItem(
      id: 'movie_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Sintel',
      serverId: 'server_1',
      serverName: 'Server',
    );

    /// Wraps [child] the way `TvRootShell` wraps every pushed detail route in
    /// production: `InputModeTracker` + `OverlaySheetHost` above it. Without
    /// this, `showAdaptive` falls back to a plain `showModalBottomSheet`,
    /// which constrains this TV-styled panel to a width/height no real TV
    /// route would ever hand it.
    Widget harness(MultiServerProvider provider, Widget child) => TranslationProvider(
      child: ChangeNotifierProvider<MultiServerProvider>.value(
        value: provider,
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: OverlaySheetHost(child: withProfileNavigationScope(child: child)),
          ),
        ),
      ),
    );

    testWidgets('a failed fetch with an alternative source shows the explicit offer', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final movie = sintel();
      final client = _ThrowingMetadataClient();
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      var chooseAnotherCalled = false;
      await tester.pumpWidget(
        harness(
          provider,
          MediaDetailScreen(
            metadata: movie,
            unifiedRouteContext: routeContext(
              sourceKeys: ['server_1:movie_1', 'server_2:movie_1'],
              sourceKey: 'server_1:movie_1',
            ),
            onChangeSource: (_) async => chooseAnotherCalled = true,
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text(t.sourcePicker.detailLoadFailedTitle), findsOneWidget);
      final chooseAnother = find.text(t.sourcePicker.chooseAnotherSource);
      expect(chooseAnother, findsOneWidget);

      await _activateByLabel(tester, t.sourcePicker.chooseAnotherSource);

      expect(chooseAnotherCalled, isTrue);
    });

    testWidgets('closing the offer leaves the page usable, not a dead end', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final movie = sintel();
      final client = _ThrowingMetadataClient();
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        harness(
          provider,
          MediaDetailScreen(
            metadata: movie,
            unifiedRouteContext: routeContext(
              sourceKeys: ['server_1:movie_1', 'server_2:movie_1'],
              sourceKey: 'server_1:movie_1',
            ),
            onChangeSource: (_) async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      await _activateByLabel(tester, t.common.close);

      // No silent failover happened: the same (stale-fallback) metadata is
      // still what is on screen, not a swapped-in different source.
      expect(find.text('Sintel'), findsWidgets);
    });

    testWidgets('a failed fetch with no alternative source never opens the panel', (tester) async {
      // Hoofdstuk 21.7: "bestaande foutafhandeling" only, when there is
      // nothing to offer — this must not invent a picker that has nowhere
      // to send the user.
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final movie = sintel();
      final client = _ThrowingMetadataClient();
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      // No unifiedRouteContext, no onChangeSource — the plain, non-unified
      // entry point this screen has always had.
      await tester.pumpWidget(harness(provider, MediaDetailScreen(metadata: movie)));
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(t.sourcePicker.detailLoadFailedTitle), findsNothing);
    });

    testWidgets('a single-source route never opens the panel either', (tester) async {
      // onChangeSource is only ever non-null when hasAlternativeSources is
      // true (hoofdstuk 15's own gate), so this mirrors that: nothing to
      // switch to means nothing to offer, even with a route context present.
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final movie = sintel();
      final client = _ThrowingMetadataClient();
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        harness(
          provider,
          MediaDetailScreen(
            metadata: movie,
            unifiedRouteContext: routeContext(sourceKeys: ['server_1:movie_1'], sourceKey: 'server_1:movie_1'),
            // No onChangeSource passed — matches the production gate.
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      await tester.pump();

      expect(find.text(t.sourcePicker.detailLoadFailedTitle), findsNothing);
    });

    testWidgets('a successful load never shows the failure panel', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final movie = sintel();
      final client = _FakeMediaServerClient(show: movie, childrenByParent: const {});
      final manager = MultiServerManager()..debugRegisterClientForTesting(client);
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      await tester.pumpWidget(
        harness(
          provider,
          MediaDetailScreen(
            metadata: movie,
            unifiedRouteContext: routeContext(
              sourceKeys: ['server_1:movie_1', 'server_2:movie_1'],
              sourceKey: 'server_1:movie_1',
            ),
            onChangeSource: (_) async {},
          ),
        ),
      );
      await tester.pump();
      await tester.pump();
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }

      expect(find.text(t.sourcePicker.detailLoadFailedTitle), findsNothing);
    });
  });

  // D14 + the second half of F19/A14's seam: what actually happens when the
  // offer is taken. The tests above prove the offer appears and the callback
  // fires; nothing proved that taking it lands you on the other source.
  //
  // Driven through the real `activateUnifiedMediaGroup`, so `onChangeSource`
  // is the production closure (`_changeSourceFromDetail`) and not a stub.
  group('D14: switching source on an open series detail', () {
    MediaItem show(String serverId) => MediaItem(
      id: 'show_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.show,
      title: 'The Show',
      serverId: serverId,
      serverName: serverId,
    );

    MediaItem season(String serverId, int index) => MediaItem(
      id: 'season_$index',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.season,
      title: 'Season $index',
      index: index,
      leafCount: 1,
      parentId: 'show_1',
      serverId: serverId,
      serverName: serverId,
    );

    UnifiedMediaSource source(String serverId) =>
        UnifiedMediaSource.fromItem(show(serverId), availability: SourceAvailability.online);

    UnifiedMediaGroup group() {
      final sources = [source('server_1'), source('server_2')];
      return UnifiedMediaGroup(
        groupId: 'g1',
        identity: CanonicalMediaIdentity.show(title: 'The Show'),
        sources: sources,
        representativeSourceKey: sources.first.sourceKey,
        watchState: UnifiedWatchState(representativeSourceKey: sources.first.sourceKey),
      );
    }

    /// server_1 has one season, server_2 has two — so which source the page is
    /// reading from is visible on screen rather than inferred.
    _FakeMediaServerClient clientFor(String serverId, {required int seasons}) => _FakeMediaServerClient(
      id: serverId,
      name: serverId,
      show: show(serverId),
      childrenByParent: {
        'show_1': [for (var i = 1; i <= seasons; i++) season(serverId, i)],
      },
    );

    testWidgets('taking the offer replaces the route and rebuilds the page from the chosen source', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(clientFor('server_1', seasons: 1))
        ..debugRegisterClientForTesting(clientFor('server_2', seasons: 2));
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      final observer = _RouteLog();
      final unified = group();

      await tester.pumpWidget(
        TranslationProvider(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(
              navigatorObservers: [observer],
              // The scope and the overlay host go *above* the navigator, not
              // inside `home`: the detail route is pushed on this navigator,
              // so anything it needs — `ProfileNavigationScope`, the sheet
              // host the picker opens into — has to be an ancestor of the
              // navigator rather than a sibling of the route it pushes.
              builder: withNoticeLayer(
                (context, child) => InputModeTracker(
                  child: OverlaySheetHost(child: withProfileNavigationScope(child: child!)),
                ),
              ),
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FocusableWrapper(
                      semanticLabel: 'open',
                      onSelect: () => unawaited(
                        activateUnifiedMediaGroup(
                          context,
                          group: unified,
                          intent: UnifiedActivationIntent.details,
                          environment: buildUnifiedActivationEnvironment(
                            group: unified,
                            health: unifiedServerHealth(isOnline: (_) => true, authErrorServerIds: const {}),
                            catalogServerIds: const {'server_1', 'server_2'},
                            availabilityRevision: ValueNotifier<int>(0),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      // Two online sources: the coordinator asks rather than guessing.
      await _activateByLabel(tester, 'open');
      await tester.pumpAndSettle();
      expect(find.text(t.sourcePicker.detailsTitle), findsOneWidget);

      await _activateByLabel(tester, 'server_1');
      await tester.pumpAndSettle();
      expect(
        find.text(t.sourcePicker.sourceLabel(source: 'server_1')),
        findsOneWidget,
        reason: 'the page says which concrete source it is reading',
      );
      expect(find.text('Season 2'), findsNothing, reason: 'server_1 only has one season');

      final pushesBefore = observer.pushes;
      final popsBefore = observer.pops;

      // Hoofdstuk 15's always-visible "[ Wijzigen ]" chip.
      await _activateByLabel(tester, t.sourcePicker.change);
      await tester.pumpAndSettle();
      expect(find.text(t.sourcePicker.detailsTitle), findsOneWidget, reason: 'the same picker, in details mode');

      await _activateByLabel(tester, 'server_2');
      await tester.pumpAndSettle();

      expect(
        find.text(t.sourcePicker.sourceLabel(source: 'server_2')),
        findsOneWidget,
        reason: 'the page is now reading the chosen source, not the one it was opened on',
      );
      expect(find.text('Season 2'), findsWidgets, reason: 'and the whole season path came with it (hoofdstuk 15)');
      expect(
        observer.pops - popsBefore,
        1,
        reason: 'the route is replaced, not stacked: Back must not walk back through the old source',
      );
      expect(observer.pushes - pushesBefore, 1);

      await tester.runAsync(() async {
        expect(await SourcePreferenceStore.read(unified.identity), 'server_2:show_1');
      });
    });

    testWidgets('F19/A14: the failure panel is the other door to the same switch', (tester) async {
      // The tests in the group above stop where the callback fires. This one
      // takes the offer: the whole chapter-21.7 flow, end to end, through the
      // production closure — failed load → "Andere bron kiezen" → the picker
      // → the alternative source's detail page.
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(_ThrowingMetadataClient())
        ..debugRegisterClientForTesting(clientFor('server_2', seasons: 2));
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      final observer = _RouteLog();
      final unified = group();

      await tester.pumpWidget(
        TranslationProvider(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(
              navigatorObservers: [observer],
              builder: withNoticeLayer(
                (context, child) => InputModeTracker(
                  child: OverlaySheetHost(child: withProfileNavigationScope(child: child!)),
                ),
              ),
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FocusableWrapper(
                      semanticLabel: 'open',
                      onSelect: () => unawaited(
                        activateUnifiedMediaGroup(
                          context,
                          group: unified,
                          intent: UnifiedActivationIntent.details,
                          environment: buildUnifiedActivationEnvironment(
                            group: unified,
                            health: unifiedServerHealth(isOnline: (_) => true, authErrorServerIds: const {}),
                            catalogServerIds: const {'server_1', 'server_2'},
                            availabilityRevision: ValueNotifier<int>(0),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await _activateByLabel(tester, 'open');
      await tester.pumpAndSettle();
      await _activateByLabel(tester, 'server_1');
      await tester.pumpAndSettle();
      // The panel itself opens from a post-frame callback once the failed load
      // has settled, which pumpAndSettle above does not wait for.
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 16));
      }
      expect(find.text(t.sourcePicker.detailLoadFailedTitle), findsOneWidget);

      await _activateByLabel(tester, t.sourcePicker.chooseAnotherSource);
      await tester.pumpAndSettle();
      expect(find.text(t.sourcePicker.detailsTitle), findsOneWidget, reason: 'the offer opens the real picker');

      await _activateByLabel(tester, 'server_2');
      await tester.pumpAndSettle();

      expect(
        find.text(t.sourcePicker.sourceLabel(source: 'server_2')),
        findsOneWidget,
        reason: 'taking the offer actually lands on the alternative source',
      );
      expect(
        find.text(t.sourcePicker.detailLoadFailedTitle),
        findsNothing,
        reason: 'and the failed page is gone rather than stacked behind the good one',
      );
    });

    testWidgets('re-picking the source already open changes nothing at all', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(2560, 1440);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final manager = MultiServerManager()
        ..debugRegisterClientForTesting(clientFor('server_1', seasons: 1))
        ..debugRegisterClientForTesting(clientFor('server_2', seasons: 2));
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);

      final observer = _RouteLog();
      final unified = group();

      await tester.pumpWidget(
        TranslationProvider(
          child: ChangeNotifierProvider<MultiServerProvider>.value(
            value: provider,
            child: MaterialApp(
              navigatorObservers: [observer],
              // The scope and the overlay host go *above* the navigator, not
              // inside `home`: the detail route is pushed on this navigator,
              // so anything it needs — `ProfileNavigationScope`, the sheet
              // host the picker opens into — has to be an ancestor of the
              // navigator rather than a sibling of the route it pushes.
              builder: withNoticeLayer(
                (context, child) => InputModeTracker(
                  child: OverlaySheetHost(child: withProfileNavigationScope(child: child!)),
                ),
              ),
              theme: monoTheme(dark: true),
              home: Builder(
                builder: (context) => Scaffold(
                  body: Center(
                    child: FocusableWrapper(
                      semanticLabel: 'open',
                      onSelect: () => unawaited(
                        activateUnifiedMediaGroup(
                          context,
                          group: unified,
                          intent: UnifiedActivationIntent.details,
                          environment: buildUnifiedActivationEnvironment(
                            group: unified,
                            health: unifiedServerHealth(isOnline: (_) => true, authErrorServerIds: const {}),
                            catalogServerIds: const {'server_1', 'server_2'},
                            availabilityRevision: ValueNotifier<int>(0),
                          ),
                        ),
                      ),
                      child: const Text('open'),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      await _activateByLabel(tester, 'open');
      await tester.pumpAndSettle();
      await _activateByLabel(tester, 'server_1');
      await tester.pumpAndSettle();

      final pushesBefore = observer.pushes;
      final popsBefore = observer.pops;

      await _activateByLabel(tester, t.sourcePicker.change);
      await tester.pumpAndSettle();
      await _activateByLabel(tester, 'server_1');
      await tester.pumpAndSettle();

      expect(
        observer.pops - popsBefore,
        0,
        reason: 'picking the source already open must not replace the route with an identical one',
      );
      expect(observer.pushes - pushesBefore, 0);
      expect(find.text(t.sourcePicker.sourceLabel(source: 'server_1')), findsOneWidget);
    });
  });

  group('back/menu suppression after a child route pops', () {
    // Non-AppleTV only: handleBackKeyAction's AppleTV branch fires onBack on
    // KeyDownEvent and swallows every KeyUpEvent unconditionally regardless
    // of origin (see its own doc comment and BackKeySuppressorObserver's),
    // so the orphaned-KeyUp race these tests exercise cannot happen there —
    // this suite runs as "phone", matching pumpPhoneDetail's pattern.
    MediaItem buildMovie() => MediaItem(
      id: 'movie_1',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.movie,
      title: 'Back Suppression Movie',
    );

    Future<NavigatorState> pumpDetailUnderPushableRoot(
      WidgetTester tester, {
      required MediaItem movie,
      required RouteObserver<PageRoute<dynamic>> routeObserver,
      required NavigatorObserver popObserver,
    }) async {
      TvDetectionService.debugSetAppleTVOverride(false);
      await SettingsService.getInstance();

      // The phone/non-TV build reaches a Consumer<DownloadProvider> that the
      // TV build (this file's other, default-AppleTV tests) never does —
      // pumpPhoneDetail's own provider stack, trimmed to what a plain movie
      // with no serverId needs.
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
      final manager = MultiServerManager();
      final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      final watchStateStore = WatchStateStore();
      addTearDown(() async {
        watchStateStore.dispose();
        downloadProvider.dispose();
        downloadManager.dispose();
        multiServerProvider.dispose();
        await db.close();
      });

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
              ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
            ],
            // BackKeyPressTracker only learns a back key is physically down
            // through InputModeTracker's global HardwareKeyboard handler — the
            // same wiring production has above MaterialApp in main.dart.
            // Without it here, tester.sendKeyDownEvent/sendKeyUpEvent would
            // still reach Focus.onKeyEvent handlers via the focus tree, but
            // the tracker these tests are exercising would never move off its
            // initial state.
            child: InputModeTracker(
              child: MaterialApp(
                builder: withNoticeLayer(),
                theme: monoTheme(dark: true),
                navigatorObservers: [routeObserver, popObserver],
                home: const Scaffold(body: Center(child: Text('root'))),
              ),
            ),
          ),
        ),
      );
      await tester.pump();

      final navigator = tester.state<NavigatorState>(find.byType(Navigator));
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'detail'),
            builder: (_) => withProfileNavigationScope(
              routeObserver: routeObserver,
              child: MediaDetailScreen(metadata: movie),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // A plain movie has no initial-focus target on phone layout
      // (_scheduleInitialMobileDetailFocus only ever targets a show's season
      // tabs or episode rows), so nothing holds focus here otherwise —
      // dispatched key events would have nowhere to bubble from and
      // Focus(onKeyEvent: _handleMediaDetailBackKey) would never see them.
      // The root screen behind media-detail has its own Scaffold too, so this
      // must resolve against media-detail's specifically, not the first match.
      final detailScaffold = find.descendant(of: find.byType(MediaDetailScreen), matching: find.byType(Scaffold));
      Focus.of(tester.element(detailScaffold)).requestFocus();
      await tester.pump();

      return navigator;
    }

    testWidgets('a stray KeyUp from the press that closed the player does not also pop media-detail', (tester) async {
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      final routeObserver = RouteObserver<PageRoute<dynamic>>();
      final popObserver = _RecordingPopObserver();
      final navigator = await pumpDetailUnderPushableRoot(
        tester,
        movie: buildMovie(),
        routeObserver: routeObserver,
        popObserver: popObserver,
      );

      expect(find.text('Back Suppression Movie'), findsOneWidget);

      // Stand-in for the video player, pushed on top of media-detail.
      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'player'),
            builder: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // The press that is about to close the player is still physically
      // down at the moment of pop (its KeyUp hasn't been dispatched yet) —
      // InputModeTracker records that globally, same as it would for the
      // real KeyDownEvent that triggered this pop.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      expect(BackKeyPressTracker.isBackKeyDown, isTrue);
      navigator.pop();
      // One pump: enough for the pop's own transition (and focus returning
      // to media-detail) to settle, but not enough for didPopNext's window
      // to clear — that needs a *second* addPostFrameCallback, chained from
      // inside the one this first pump runs.
      await tester.pump();

      // That same press's KeyUp now arrives on the newly-visible media-detail
      // screen, orphaned. It must not be treated as a fresh back press.
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();

      expect(popObserver.popped, ['player']);
      expect(find.text('Back Suppression Movie'), findsOneWidget);
    });

    testWidgets('a fresh Menu press right after an automatic player return pops media-detail immediately', (
      tester,
    ) async {
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      final routeObserver = RouteObserver<PageRoute<dynamic>>();
      final popObserver = _RecordingPopObserver();
      final navigator = await pumpDetailUnderPushableRoot(
        tester,
        movie: buildMovie(),
        routeObserver: routeObserver,
        popObserver: popObserver,
      );

      unawaited(
        navigator.push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: 'player'),
            builder: (_) => const SizedBox(),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      // Playback reaches its own end and pops itself — no back key involved,
      // so nothing should arm any suppression at all.
      expect(BackKeyPressTracker.isBackKeyDown, isFalse);
      navigator.pop();
      await tester.pump();
      await tester.pump();

      expect(popObserver.popped, ['player']);
      expect(find.text('Back Suppression Movie'), findsOneWidget);

      // The user's own, brand-new Menu press right after landing back on the
      // detail screen must work on the first try, not be eaten by leftover
      // suppression from the automatic return above.
      await tester.sendKeyDownEvent(LogicalKeyboardKey.escape);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.escape);
      await tester.pump();
      await tester.pump();

      expect(popObserver.popped, ['player', 'detail']);
      expect(find.text('Back Suppression Movie'), findsNothing);
    });
  });

  group('watchlist action button', () {
    testWidgets('flips to Remove on the store, without asking the sources again', (tester) async {
      await SettingsService.getInstance();
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);

      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      final source = _CountingWatchlistSource();
      final watchlistProvider = WatchlistProvider(
        snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
        repository: WatchlistRepository(sources: [source]),
      );
      final watchlistStore = WatchlistStore();
      final manager = MultiServerManager();
      final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
      final watchStateStore = WatchStateStore();
      addTearDown(() async {
        watchStateStore.dispose();
        multiServerProvider.dispose();
        manager.dispose();
        watchlistStore.dispose();
        watchlistProvider.dispose();
        await db.close();
      });

      // Load through runAsync: the snapshot store talks to real sqlite, which
      // the test binding's fake async never advances. After this the screen's
      // own ensureLoaded is a no-op, so the fetch count below stays readable.
      await tester.runAsync(() => watchlistProvider.load());
      expect(source.fetches, 1);

      final movie = MediaItem(
        id: 'movie_1',
        backend: MediaBackend.plex,
        kind: MediaKind.movie,
        title: 'Sintel',
        guid: 'plex://movie/abc',
        serverId: 'server_1',
      );

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
              ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
              ChangeNotifierProvider<WatchlistProvider>.value(value: watchlistProvider),
              ChangeNotifierProvider<WatchlistStore>.value(value: watchlistStore),
            ],
            child: MaterialApp(
              builder: withNoticeLayer(),
              theme: monoTheme(dark: true),
              home: withProfileNavigationScope(child: MediaDetailScreen(metadata: movie)),
            ),
          ),
        ),
      );
      await tester.pump();
      await tester.pump();

      expect(find.byIcon(Symbols.bookmark_add_rounded), findsOneWidget);
      expect(find.byIcon(Symbols.bookmark_remove_rounded), findsNothing);

      await tester.tap(find.byIcon(Symbols.bookmark_add_rounded));
      await tester.pump();
      await tester.pump();

      expect(source.added, hasLength(1));
      expect(find.byIcon(Symbols.bookmark_remove_rounded), findsOneWidget);
      expect(find.byIcon(Symbols.bookmark_add_rounded), findsNothing);
      // The icon turned over on the optimistic patch; nothing was re-read.
      expect(source.fetches, 1);
    });
  });
}

Future<void> _press(WidgetTester tester, LogicalKeyboardKey key) async {
  await tester.sendKeyDownEvent(key);
  await tester.sendKeyUpEvent(key);
  // A bounded settle, not `pumpAndSettle()`: the detail screen behind this
  // panel runs its own long-lived animations unrelated to this interaction,
  // and letting the test wait for every scheduled frame to stop entirely can
  // walk it through an intermediate layout state that legitimately overflows
  // — a pre-existing fragility in that screen's hero layout, not something
  // this test is about.
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 16));
  }
}

/// Focuses the control showing [label] and presses Select on it.
///
/// `FocusableWrapper`/`TvPanelButton` are D-pad widgets and carry no tap
/// handler at all, so `tester.tap` on one of these silently does nothing —
/// which is also the honest way to drive a 10-foot surface in a test.
Future<void> _activateByLabel(WidgetTester tester, String label) async {
  final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
  focus.requestFocus();
  await tester.pump();
  expect(focus.hasPrimaryFocus, isTrue, reason: 'the control under test must actually hold the focus');
  SelectKeyUpSuppressor.clearSuppression();
  await _press(tester, LogicalKeyboardKey.select);
}

/// A watchlist source that counts what it was asked for, so a test can tell a
/// local patch apart from a round trip.
class _CountingWatchlistSource implements WatchlistSource {
  int fetches = 0;
  final added = <MediaItem>[];

  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'acc', userId: 'usr');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    fetches++;
    return const [];
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    added.add(item);
    return WatchlistMembership(scope: scope, remoteKey: 'abc');
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

/// Records the `settings.name` of every route this observer sees popped, in
/// order — lets a test assert exactly which route closed and how many times,
/// rather than inferring it from what's left on screen.
class _RecordingPopObserver extends NavigatorObserver {
  final List<String?> popped = [];

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    popped.add(route.settings.name);
  }
}

/// Never answers `fetchItemWithOnDeck`, standing in for the flaky-network case.
class _HangingMetadataClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) {
    return Completer<({MediaItem? item, MediaItem? onDeckEpisode})>().future;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _FakeMediaServerClient implements MediaServerClient {
  final MediaItem show;
  final Map<String, List<MediaItem>> childrenByParent;
  final Map<String, Future<List<MediaItem>>> childrenPageFutures;
  final Map<String, Object> childrenPageErrors;
  final Future<List<MediaItem>>? pendingPlayableDescendants;
  final childrenPageCalls = <({String parentId, int? start, int? size})>[];
  final fetchItemCalls = <String>[];

  _FakeMediaServerClient({
    required this.show,
    required this.childrenByParent,
    this.childrenPageFutures = const {},
    this.childrenPageErrors = const {},
    this.pendingPlayableDescendants,
    this.id = 'server_1',
    this.name = 'Server',
  });

  /// D14 mounts two of these at once, so the server a fake speaks for has to
  /// be a parameter rather than a constant.
  final String id;
  final String name;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => name;

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async {
    return (item: show, onDeckEpisode: null);
  }

  @override
  Future<List<MediaItem>> fetchChildren(String parentId) async {
    return childrenByParent[parentId] ?? const [];
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    childrenPageCalls.add((parentId: parentId, start: start, size: size));
    final error = childrenPageErrors[parentId];
    if (error != null) throw error;
    final all =
        await (childrenPageFutures[parentId] ?? Future.value(childrenByParent[parentId] ?? const <MediaItem>[]));
    final offset = start ?? 0;
    final limit = size ?? all.length;
    final end = (offset + limit).clamp(0, all.length).toInt();
    final items = offset >= all.length ? const <MediaItem>[] : all.sublist(offset, end);
    return LibraryPage(items: items, totalCount: all.length, offset: offset);
  }

  @override
  Future<LibraryPage<MediaItem>> fetchPlayableDescendantsPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    final items = await pendingPlayableDescendants!;
    return LibraryPage(items: items, totalCount: items.length, offset: start ?? 0);
  }

  @override
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];

  @override
  Future<MediaItem?> fetchItem(String id) async {
    fetchItemCalls.add(id);
    if (id == show.id) return show;
    for (final items in childrenByParent.values) {
      for (final item in items) {
        if (item.id == id) return item;
      }
    }
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Always throws from `fetchItemWithOnDeck` — the genuine-failure case, as
/// distinct from `_HangingMetadataClient`'s never-resolves one.
class _ThrowingMetadataClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async {
    throw StateError('server unreachable');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Counts route pushes and pops so "the route is replaced, not stacked" can be
/// asserted as a number rather than inferred from what happens to be on screen.
class _RouteLog extends NavigatorObserver {
  int pushes = 0;
  int pops = 0;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushes++;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => pops++;
}
