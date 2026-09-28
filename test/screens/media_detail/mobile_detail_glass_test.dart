/// The iPhone film page with Liquid Glass (Liquid Glass Task 7, mockup LG-02).
///
/// On the real [MediaDetailScreen]: both glass settings open on the poster
/// hero (DEC-140). Glass off paints no glass; glass on adds a prominent
/// Resume capsule, a glass Download capsule and glass back/more circles. Then
/// contrast of the glass buttons over the lightest real fixture (Big Buck
/// Bunny), fake tier.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/download_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/watch_state_store.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/providers/watchlist_store.dart';
import 'package:pleya/screens/media_detail/mobile/mobile_poster_hero.dart';
import 'package:pleya/screens/media_detail/mobile_detail_hero.dart';
import 'package:pleya/screens/media_detail_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/download_manager_service.dart';
import 'package:pleya/services/download_storage_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/notice_layer.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/profile_navigation.dart';

late final ui.Image _lightSceneImage;

const _kTitle = 'Big Buck Bunny';

final _movie = MediaItem(
  id: 'movie_bbb',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: _kTitle,
  guid: 'plex://movie/bbb',
  serverId: 'server_1',
  thumbPath: 'https://x/bbb_poster.jpg',
  year: 2008,
  durationMs: 9 * 60 * 1000,
  viewOffsetMs: 2 * 60 * 1000,
);

/// Counts adds, like `media_detail_screen_test.dart`'s watchlist source.
class _CountingWatchlistSource implements WatchlistSource {
  final added = <MediaItem>[];

  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'acc', userId: 'usr');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async => const [];

  @override
  Future<WatchlistMembership> add(MediaItem item) async {
    added.add(item);
    return WatchlistMembership(scope: scope, remoteKey: 'bbb');
  }

  @override
  Future<void> remove(WatchlistMembership membership) async {}

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

/// A server that only answers what the film page asks for: the film itself
/// and one trailer among its extras.
class _TrailerClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.jellyfin;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.jellyfin;

  @override
  Future<({MediaItem? item, MediaItem? onDeckEpisode})> fetchItemWithOnDeck(String id) async =>
      (item: _movie, onDeckEpisode: null);

  @override
  Future<List<MediaItem>> fetchExtras(String id) async => [
    MediaItem(
      id: 'trailer_bbb',
      backend: MediaBackend.jellyfin,
      kind: MediaKind.clip,
      title: 'Trailer',
      raw: const {'ExtraType': 'Trailer'},
    ),
  ];

  // The film now carries a poster URL, which the hero asks the client to size.
  @override
  String externalImageUrl(String url, {int? width, int? height}) => url;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The real detail screen on an iPhone 17 Pro, glass [glass].
Future<_CountingWatchlistSource> _pumpDetail(
  WidgetTester tester, {
  required bool glass,
  bool realTier = false,
  MediaServerClient? client,
  MediaItem? metadata,
}) async {
  TvDetectionService.debugSetAppleTVOverride(false);
  await glassPhone(tester, glass: glass, realTier: realTier);

  final db = AppDatabase.forTesting(NativeDatabase.memory());
  PlexApiCache.initialize(db);
  final downloadManager = DownloadManagerService(
    database: db,
    storageService: DownloadStorageService.instance,
    clientResolver: (serverId, {clientScopeId}) => null,
  );
  downloadManager.recoveryFuture = Future<void>.value();
  final downloadProvider = DownloadProvider.forTesting(downloadManager: downloadManager, database: db);
  await tester.runAsync(downloadProvider.ensureInitialized);
  final source = _CountingWatchlistSource();
  final watchlistProvider = WatchlistProvider(
    snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
    repository: WatchlistRepository(sources: [source]),
  );
  final watchlistStore = WatchlistStore();
  final manager = MultiServerManager();
  if (client != null) manager.debugRegisterClientForTesting(client);
  final multiServerProvider = MultiServerProvider(manager, DataAggregationService(manager));
  final watchStateStore = WatchStateStore();
  addTearDown(() async {
    watchStateStore.dispose();
    multiServerProvider.dispose();
    manager.dispose();
    watchlistStore.dispose();
    watchlistProvider.dispose();
    downloadProvider.dispose();
    downloadManager.dispose();
    await db.close();
  });
  await tester.runAsync(watchlistProvider.load);

  await tester.pumpWidget(
    TranslationProvider(
      child: MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServerProvider),
          ChangeNotifierProvider<DownloadProvider>.value(value: downloadProvider),
          ChangeNotifierProvider<WatchStateStore>.value(value: watchStateStore),
          ChangeNotifierProvider<WatchlistProvider>.value(value: watchlistProvider),
          ChangeNotifierProvider<WatchlistStore>.value(value: watchlistStore),
        ],
        child: MaterialApp(
          builder: withNoticeLayer(),
          theme: glassPhoneTheme(),
          home: withProfileNavigationScope(child: MediaDetailScreen(metadata: metadata ?? _movie)),
        ),
      ),
    ),
  );
  await tester.pump();
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
  return source;
}

Finder _surface({required Type shape, bool? prominent}) => find.byWidgetPredicate(
  (w) => w is GlassSurface && w.shape.runtimeType == shape && (prominent == null || w.prominent == prominent),
);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    _lightSceneImage = (await codec.getNextFrame()).image;
  });
  setUp(() {
    resetNotices();
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });
  tearDown(() {
    resetNotices();
    TvDetectionService.debugSetAppleTVOverride(null);
  });

  testWidgets('glas uit: posterhero zonder glas, watchlist in de actierij', (tester) async {
    await _pumpDetail(tester, glass: false);

    expect(find.byType(MobilePosterHero), findsOneWidget);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byKey(const Key('media-detail.action.download')), findsOneWidget);
    expect(find.byKey(const Key('media-detail.action.watchlist')), findsOneWidget);
    expect(find.byKey(const Key('media-detail.action.rate')), findsOneWidget);
  });

  testWidgets('glas aan: posterhero, prominente Resume en glazen terug/meer', (tester) async {
    final source = await _pumpDetail(tester, glass: true);
    expect(glassTierFor(tester.element(find.byType(MobilePosterHero))), GlassTier.fake);

    // The hero is 640 high at the mockup's 402 wide; the poster inside it
    // starts under the status bar and the back/more bar.
    final hero = tester.getRect(find.byType(MobilePosterHero));
    final barBottom = tester.view.padding.top / tester.view.devicePixelRatio + 60;
    expect(hero.top, 0);
    expect(hero.height, moreOrLessEquals(640 * hero.width / 402));
    final poster = tester.getRect(
      find.descendant(of: find.byType(MobilePosterHero), matching: find.byType(ShaderMask)),
    );
    expect(poster.top, moreOrLessEquals(barBottom));

    final resume = _surface(shape: StadiumBorder, prominent: true);
    expect(resume, findsOneWidget);
    expect(find.descendant(of: resume, matching: find.textContaining(t.common.resume)), findsOneWidget);
    // Download is an icon in the action row now (D-01), not a glass capsule.
    expect(_surface(shape: StadiumBorder, prominent: false), findsNothing);
    expect(tester.getRect(resume).top, greaterThanOrEqualTo(hero.bottom));
    // Back and more are glass circles.
    expect(_surface(shape: CircleBorder), findsNWidgets(2));
    expect(find.byTooltip(MaterialLocalizations.of(tester.element(resume)).backButtonTooltip), findsOneWidget);
    expect(find.byTooltip(MaterialLocalizations.of(tester.element(resume)).moreButtonTooltip), findsOneWidget);

    // The watchlist is in the action row and calls the same toggle.
    expect(find.byKey(const Key('media-detail.action.rate')), findsOneWidget);
    final watchlist = find.byKey(const Key('media-detail.action.watchlist'));
    expect(find.bySemanticsLabel(t.watchlist.add), findsOneWidget);
    await tester.ensureVisible(watchlist);
    await tester.pump();
    await tester.tap(watchlist);
    await tester.pump();
    await tester.pump();
    expect(source.added, hasLength(1));
    expect(find.bySemanticsLabel(t.watchlist.remove), findsOneWidget);
  });

  testWidgets('glas aan, serie (DEC-131): hero met seizoenen, geen Download, watchlist in de actierij', (tester) async {
    final series = MediaItem(
      id: 'show_bbb',
      backend: MediaBackend.plex,
      kind: MediaKind.show,
      title: 'Bunny Tales',
      guid: 'plex://show/bbb',
      serverId: 'server_1',
      year: 2008,
      childCount: 3,
    );
    await _pumpDetail(tester, glass: true, metadata: series);

    final hero = find.byType(MobilePosterHero);
    expect(hero, findsOneWidget);
    expect(find.descendant(of: hero, matching: find.text(t.unifiedCatalog.seasons(count: 3))), findsOneWidget);
    // A series downloads per episode: no download action.
    expect(find.byKey(const Key('media-detail.action.download')), findsNothing);
    expect(find.byKey(const Key('media-detail.action.watchlist')), findsOneWidget);
  });

  testWidgets('K8: de trailerknop heet "Trailer afspelen", niet "Extras"', (tester) async {
    await _pumpDetail(tester, glass: true, client: _TrailerClient());
    await tester.pump(const Duration(milliseconds: 300));

    // The trailer sits in the action row (D-01); VoiceOver reads what it does.
    final trailer = find.byKey(const Key('media-detail.action.trailer'));
    expect(trailer, findsOneWidget);
    expect(tester.getSemantics(trailer).label, t.tooltips.playTrailer);
  });

  testWidgets('B5: terug en meer blijven in beeld na scrollen', (tester) async {
    await _pumpDetail(tester, glass: true);
    final l10n = MaterialLocalizations.of(tester.element(find.byType(MobilePosterHero)));
    final back = find.byTooltip(l10n.backButtonTooltip);
    final more = find.byTooltip(l10n.moreButtonTooltip);
    final before = (tester.getRect(back), tester.getRect(more));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -400));
    await tester.pump();
    final position = tester.state<ScrollableState>(find.byType(Scrollable).first).position;
    expect(position.pixels, greaterThan(200), reason: 'the page must actually have scrolled');

    // Same place on screen, and still the thing a tap there hits.
    expect(tester.getRect(back), before.$1);
    expect(tester.getRect(more), before.$2);
    expect(back.hitTestable(), findsOneWidget);
    expect(more.hitTestable(), findsOneWidget);
  });

  testWidgets('B5/D-03b: de balk krijgt titel en achtergrond pas na de hero', (tester) async {
    await _pumpDetail(tester, glass: true);
    final bar = find.byType(MobileDetailHeroBar);
    double titleOpacity() => tester
        .widget<Opacity>(
          find
              .ancestor(
                of: find.descendant(of: bar, matching: find.text(_movie.displayTitle)),
                matching: find.byType(Opacity),
              )
              .first,
        )
        .opacity;
    expect(find.descendant(of: bar, matching: find.text(_movie.displayTitle)), findsNothing);
    expect(tester.widget<MobileDetailHeroBar>(bar).collapseProgress, lessThanOrEqualTo(0));

    await tester.drag(find.byType(CustomScrollView), const Offset(0, -900));
    await tester.pump();
    expect(titleOpacity(), 1);
    final title = tester.widget<Text>(find.descendant(of: bar, matching: find.text(_movie.displayTitle)));
    expect(title.style?.fontSize, 17);
    expect(title.style?.fontWeight, FontWeight.w700);
    // Back stays tappable over the opaque bar.
    final l10n = MaterialLocalizations.of(tester.element(bar));
    expect(find.byTooltip(l10n.backButtonTooltip).hitTestable(), findsOneWidget);
  });

  // B6: the real tier (liquid_glass_renderer) on the iPhone theme. Only
  // proves the package widgets build on each surface; contrast is measured
  // on tier fake above.
  testWidgets('rooktest echt glas op iOS: knoppenrij en Resume', (tester) async {
    await _pumpDetail(tester, glass: true, realTier: true);
    expect(glassTierFor(tester.element(find.byType(MobilePosterHero))), GlassTier.real);
    expect(tester.takeException(), isNull);

    int layersAbove(Finder f) => find.ancestor(of: f, matching: find.byType(LiquidGlassLayer)).evaluate().length;
    Finder platesIn(Finder layer) => find.descendant(of: layer, matching: find.byType(LiquidGlass));
    final l10n = MaterialLocalizations.of(tester.element(find.byType(MobilePosterHero)));
    final bar = find.ancestor(of: find.byTooltip(l10n.backButtonTooltip), matching: find.byType(LiquidGlassLayer));
    final resume = find.ancestor(of: find.textContaining(t.common.resume), matching: find.byType(LiquidGlassLayer));

    // Each surface sits in exactly one layer of its own.
    expect(layersAbove(find.byTooltip(l10n.backButtonTooltip)), 1);
    expect(layersAbove(find.textContaining(t.common.resume)), 1);
    expect(find.byType(LiquidGlassLayer), findsNWidgets(2));
    // Back and more; Resume.
    expect(platesIn(bar), findsNWidgets(2));
    expect(platesIn(resume), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNWidgets(3));
  });

  testWidgets('contrast over Big Buck Bunny: glasknoppen', (tester) async {
    await glassPhone(tester, glass: true);
    const sceneKey = Key('scene');
    const backKey = Key('back'), downloadKey = Key('download'), resumeKey = Key('resume');

    // Every foreground is painted transparent with its shadow kept, so the
    // meter reads the background the real glyph sits on. On the page the
    // capsules sit under the poster; here they get the bright scene itself,
    // the worst case.
    await tester.pumpWidget(
      MaterialApp(
        theme: glassPhoneTheme(),
        home: RepaintBoundary(
          key: sceneKey,
          child: Material(
            color: Colors.black,
            child: Align(
              alignment: Alignment.topCenter,
              child: SizedBox(
                height: 528,
                child: Stack(
                  children: [
                    Positioned.fill(
                      child: RawImage(image: _lightSceneImage, fit: BoxFit.cover),
                    ),
                    Positioned(
                      left: 16,
                      right: 16,
                      bottom: 24,
                      child: Column(
                        children: [
                          GlassCapsuleButton(
                            key: resumeKey,
                            prominent: true,
                            icon: Icons.play_arrow_rounded,
                            label: 'Resume · 7m left',
                            foregroundColor: Colors.transparent,
                            onPressed: () {},
                          ),
                          const SizedBox(height: 12),
                          GlassCapsuleButton(
                            key: downloadKey,
                            icon: Icons.download_rounded,
                            label: 'Download',
                            foregroundColor: Colors.transparent,
                            onPressed: () {},
                          ),
                        ],
                      ),
                    ),
                    Positioned(
                      top: 0,
                      left: 0,
                      right: 0,
                      child: MobileDetailHeroBar(
                        leading: GlassCircleButton(
                          key: backKey,
                          icon: Icons.arrow_back_rounded,
                          tooltip: 'Back',
                          foregroundColor: Colors.transparent,
                          onPressed: () {},
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();

    final boundary = find.byKey(sceneKey);
    Future<double> text(Finder area, {Color color = Colors.white}) =>
        textContrastOverBackground(tester, area: area, textColor: color, boundary: boundary);
    Finder iconIn(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(Icon));
    Finder labelIn(Key key) => find.descendant(of: find.byKey(key), matching: find.byType(Text));

    final results = <String, double>{
      'resume label': await text(labelIn(resumeKey), color: Colors.black),
      'download label': await text(labelIn(downloadKey)),
      'back icon': await text(iconIn(backKey)),
    };
    debugPrint('LG-02 contrast: ${results.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}');

    for (final e in results.entries) {
      final floor = e.key.endsWith('icon') ? 3.0 : 4.5;
      expect(e.value, greaterThanOrEqualTo(floor), reason: '${e.key} ${e.value.toStringAsFixed(2)} < $floor');
    }
  });
}
