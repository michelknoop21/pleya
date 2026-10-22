/// The iPhone film page with Liquid Glass (Liquid Glass Task 7, mockup LG-02).
///
/// On the real [MediaDetailScreen]: both glass settings open on the poster
/// hero (DEC-140). Glass off paints no glass; glass on only makes back and
/// more glass circles, Resume stays the solid white button (Plex look,
/// variant B). Then contrast of the back button over the lightest real
/// fixture (Big Buck Bunny), fake tier.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:drift/native.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
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
import 'package:pleya/theme/mono_theme.dart';
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
  ThemeData? theme,
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
          theme: theme ?? glassPhoneTheme(),
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

  testWidgets('glas aan: posterhero tot de bovenrand, solide witte Resume en glazen terug/meer', (tester) async {
    final source = await _pumpDetail(tester, glass: true);
    expect(glassTierFor(tester.element(find.byType(MobilePosterHero))), GlassTier.fake);

    // The hero is 640 high at the mockup's 402 wide; since variant B the
    // poster inside it fills the screen from the top edge.
    final hero = tester.getRect(find.byType(MobilePosterHero));
    expect(hero.top, 0);
    expect(hero.height, moreOrLessEquals(640 * hero.width / 402));
    final poster = tester.getRect(
      find.descendant(of: find.byType(MobilePosterHero), matching: find.byType(ShaderMask)),
    );
    expect(poster.top, 0);

    // Resume is the solid white button, glass or not (Plex look).
    final resume = find.byKey(const Key('media-detail.play'));
    expect(find.descendant(of: resume, matching: find.textContaining(t.common.resume)), findsOneWidget);
    expect(_surface(shape: StadiumBorder), findsNothing);
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
  // proves the package widgets build; since variant B only back and more are
  // glass, Resume is the solid white button.
  testWidgets('rooktest echt glas op iOS: terug/meer glas, Resume solide', (tester) async {
    await _pumpDetail(tester, glass: true, realTier: true);
    expect(glassTierFor(tester.element(find.byType(MobilePosterHero))), GlassTier.real);
    expect(tester.takeException(), isNull);

    // Back and more build their glass; Resume sits on no glass plate.
    expect(find.byType(LiquidGlassLayer), findsWidgets);
    expect(find.ancestor(of: find.textContaining(t.common.resume), matching: find.byType(LiquidGlass)), findsNothing);
    expect(
      find.ancestor(of: find.textContaining(t.common.resume), matching: find.byType(LiquidGlassLayer)),
      findsNothing,
    );
  });

  // Variant B (Plex look): the page is always dark and the play button is
  // solid white, also when the app runs the light theme.
  for (final dark in [false, true]) {
    testWidgets('variant B: pagina donker en witte hoofdknop bij app-thema dark=$dark', (tester) async {
      await _pumpDetail(
        tester,
        glass: false,
        theme: monoTheme(dark: dark).copyWith(platform: TargetPlatform.iOS),
      );
      final page = tester.element(find.byKey(const Key('media-detail.mobile-page')));
      expect(Theme.of(page).brightness, Brightness.dark);
      expect(Theme.of(page).colorScheme.onSurface, Colors.white);
      expect(tester.widget<Text>(find.text('2008')).style?.color, Colors.white);
      final play = tester.widget<FilledButton>(
        find.descendant(of: find.byKey(const Key('media-detail.play')), matching: find.byType(FilledButton)),
      );
      expect(play.style?.backgroundColor?.resolve({}), Colors.white);
      expect(play.style?.foregroundColor?.resolve({}), Colors.black);
      // Back and more keep their light circles with a dark glyph.
      final l10n = MaterialLocalizations.of(page);
      final back = find.descendant(of: find.byTooltip(l10n.backButtonTooltip), matching: find.byType(Icon));
      expect(tester.widget<Icon>(back).color, monoTheme(dark: false).colorScheme.onSurface);
    });
  }

  // Visual evidence of variant B: the real page with a real picture as
  // poster, art and glow, on the light app theme. Writes a PNG only when
  // PLEX_SHOT_DIR is set; PLEX_SHOT_POSTER swaps the picture for another file.
  testWidgets('variant B: schermafdruk van de echte pagina met een echte poster', (tester) async {
    final dir = Platform.environment['PLEX_SHOT_DIR'];
    // The image cache asks for a directory once real async work runs.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (_) async => Directory.systemTemp.path,
    );
    final posterFile = Platform.environment['PLEX_SHOT_POSTER'];
    final poster = posterFile == null
        ? _lightSceneImage
        : await tester.runAsync(() async {
            final codec = await ui.instantiateImageCodec(File(posterFile).readAsBytesSync());
            return (await codec.getNextFrame()).image;
          });
    final movie = _movie.copyWith(
      title: 'Rules of Engagement',
      artPath: 'https://x/bbb_art.jpg',
      year: 2007,
      genres: const ['Comedy', 'Romance'],
      contentRating: 'AL',
      summary:
          'A group of middle-aged people and friends deal with the challenges and difficulties of life while they '
          'are in the different stages of relationships.',
    );
    final light = monoTheme(dark: false).copyWith(platform: TargetPlatform.iOS);
    await _pumpDetail(tester, glass: false, metadata: movie, theme: light);

    // Serve the picture from the image cache under the exact providers the
    // page asked for, then build the page again so it resolves them.
    final providers = <ImageProvider>{
      for (final w in tester.widgetList<CachedNetworkImage>(find.byType(CachedNetworkImage)))
        CachedNetworkImageProvider(w.imageUrl, cacheManager: w.cacheManager),
      for (final w in tester.widgetList<Image>(find.byType(Image)))
        if (w.image is CachedNetworkImageProvider) w.image,
    };
    expect(providers, isNotEmpty);
    for (final provider in providers) {
      PaintingBinding.instance.imageCache.evict(provider);
      PaintingBinding.instance.imageCache.putIfAbsent(
        provider,
        () => OneFrameImageStreamCompleter(SynchronousFuture(ImageInfo(image: poster!.clone()))),
      );
    }
    // Unmount first, so the images resolve again instead of keeping the
    // pending stream of the first build.
    await tester.pumpWidget(const SizedBox());
    await _pumpDetail(tester, glass: false, metadata: movie, theme: light);
    await tester.pump(const Duration(milliseconds: 500));

    final page = tester.element(find.byKey(const Key('media-detail.mobile-page')));
    expect(Theme.of(page).brightness, Brightness.dark);
    // The helpers that take the screen's context (synopsis, genre line) read
    // the dark page theme too, not the light app theme above it.
    final genre = tester.widget<Text>(find.text('Comedy · Romance'));
    expect(genre.style?.color?.computeLuminance(), greaterThan(0.4));
    if (dir == null) return;
    await tester.runAsync(() async {
      final boundary = tester.renderObject<RenderRepaintBoundary>(
        find
            .ancestor(of: find.byKey(const Key('media-detail.mobile-page')), matching: find.byType(RepaintBoundary))
            .first,
      );
      final image = await boundary.toImage(pixelRatio: tester.view.devicePixelRatio);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/detail-variant-b-light-theme.png').writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  });

  testWidgets('contrast over Big Buck Bunny: glasknoppen', (tester) async {
    await glassPhone(tester, glass: true);
    const sceneKey = Key('scene');
    const backKey = Key('back');

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

    final results = <String, double>{'back icon': await text(iconIn(backKey))};
    debugPrint('LG-02 contrast: ${results.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}');

    for (final e in results.entries) {
      final floor = e.key.endsWith('icon') ? 3.0 : 4.5;
      expect(e.value, greaterThanOrEqualTo(floor), reason: '${e.key} ${e.value.toStringAsFixed(2)} < $floor');
    }
  });
}
