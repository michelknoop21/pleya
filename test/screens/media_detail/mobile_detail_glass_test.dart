/// The iPhone film page with Liquid Glass (Liquid Glass Task 7, mockup LG-02).
///
/// On the real [MediaDetailScreen]: glass off is today's page (no glass, the
/// watchlist toggle in the action row); glass on is the full-bleed hero with a
/// prominent Resume capsule, a glass Download capsule and a round glass
/// watchlist button that calls the same toggle. Then contrast of the hero's
/// title, tags and glass buttons over the lightest real fixture (Big Buck
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

  testWidgets('glas uit: de filmpagina van vandaag, watchlist in de actierij', (tester) async {
    await _pumpDetail(tester, glass: false);

    expect(find.byType(GlassSurface), findsNothing);
    expect(find.byType(MobileDetailHero), findsNothing);
    expect(find.widgetWithText(FilledButton, 'Download'), findsOneWidget);
    expect(find.text(t.watchlist.add), findsOneWidget);
    expect(find.text(t.mediaMenu.rate), findsOneWidget);
  });

  testWidgets('glas aan: hero, prominente Resume, Download en ronde watchlist-knop', (tester) async {
    final source = await _pumpDetail(tester, glass: true);
    expect(glassTierFor(tester.element(find.byType(MobileDetailHero))), GlassTier.fake);

    // The hero runs behind the status bar and is 62% of the screen high.
    final hero = tester.getRect(find.byType(MobileDetailHero));
    expect(hero.top, 0);
    expect(hero.height, greaterThanOrEqualTo(852 * kMobileDetailHeroFraction));

    final resume = _surface(shape: StadiumBorder, prominent: true);
    expect(resume, findsOneWidget);
    expect(find.descendant(of: resume, matching: find.textContaining(t.common.resume)), findsOneWidget);
    final download = _surface(shape: StadiumBorder, prominent: false);
    expect(download, findsOneWidget);
    expect(find.descendant(of: download, matching: find.text('Download')), findsOneWidget);
    // Back, more and watchlist are glass circles; the flat app bar is gone.
    expect(_surface(shape: CircleBorder), findsNWidgets(3));
    expect(find.byTooltip(MaterialLocalizations.of(tester.element(resume)).backButtonTooltip), findsOneWidget);
    expect(find.byTooltip(MaterialLocalizations.of(tester.element(resume)).moreButtonTooltip), findsOneWidget);

    // The watchlist left the action row; rate stays.
    expect(find.text(t.watchlist.add), findsNothing);
    expect(find.text(t.mediaMenu.rate), findsOneWidget);

    // The round button sits right of Download, same height, and calls the
    // same toggle: the source gets the add and the icon flips.
    final watchlist = find.byTooltip(t.watchlist.add);
    expect(watchlist, findsOneWidget);
    expect(tester.getRect(watchlist).left, greaterThan(tester.getRect(download).right));
    expect(tester.getRect(watchlist).height, GlassCapsuleButton.height);
    await tester.tap(watchlist);
    await tester.pump();
    await tester.pump();
    expect(source.added, hasLength(1));
    expect(find.byTooltip(t.watchlist.remove), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_added_rounded), findsOneWidget);
  });

  testWidgets('glas aan, serie (DEC-131): hero met seizoenen-tag, geen Download, watchlist in de actierij', (
    tester,
  ) async {
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

    final hero = find.byType(MobileDetailHero);
    expect(hero, findsOneWidget);
    final seasons = '3 ${t.libraries.groupings.seasons.toLowerCase()}';
    expect(find.descendant(of: hero, matching: find.text(seasons)), findsOneWidget);
    // A series downloads per episode: no Download capsule, no round watchlist
    // button; the toggle stays in the action row as on the flat page.
    expect(_surface(shape: StadiumBorder, prominent: false), findsNothing);
    expect(find.descendant(of: hero, matching: find.byTooltip(t.watchlist.add)), findsNothing);
    expect(find.text(t.watchlist.add), findsOneWidget);
  });

  testWidgets('K8: de trailerknop heet "Trailer afspelen", niet "Extras"', (tester) async {
    await _pumpDetail(tester, glass: true, client: _TrailerClient());
    await tester.pump(const Duration(milliseconds: 300));

    expect(find.byTooltip(t.tooltips.playTrailer), findsOneWidget);
    expect(find.byTooltip(t.discover.extras), findsNothing);
  });

  testWidgets('B5: terug en meer blijven in beeld na scrollen', (tester) async {
    await _pumpDetail(tester, glass: true);
    final l10n = MaterialLocalizations.of(tester.element(find.byType(MobileDetailHero)));
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

  // B6: the real tier (liquid_glass_renderer) on the iPhone theme. Only
  // proves the package widgets build on each surface; contrast is measured
  // on tier fake above.
  testWidgets('rooktest echt glas op iOS: knoppenrij, Resume en downloadrij', (tester) async {
    await _pumpDetail(tester, glass: true, realTier: true);
    expect(glassTierFor(tester.element(find.byType(MobileDetailHero))), GlassTier.real);
    expect(tester.takeException(), isNull);

    int layersAbove(Finder f) => find.ancestor(of: f, matching: find.byType(LiquidGlassLayer)).evaluate().length;
    Finder platesIn(Finder layer) => find.descendant(of: layer, matching: find.byType(LiquidGlass));
    final l10n = MaterialLocalizations.of(tester.element(find.byType(MobileDetailHero)));
    final bar = find.ancestor(of: find.byTooltip(l10n.backButtonTooltip), matching: find.byType(LiquidGlassLayer));
    final resume = find.ancestor(of: find.textContaining(t.common.resume), matching: find.byType(LiquidGlassLayer));
    final download = find.ancestor(of: find.text('Download'), matching: find.byType(LiquidGlassLayer));

    // Each surface sits in exactly one layer of its own.
    expect(layersAbove(find.byTooltip(l10n.backButtonTooltip)), 1);
    expect(layersAbove(find.textContaining(t.common.resume)), 1);
    expect(layersAbove(find.text('Download')), 1);
    expect(find.byType(LiquidGlassLayer), findsNWidgets(3));
    // Back and more; Resume; Download and the watchlist circle.
    expect(platesIn(bar), findsNWidgets(2));
    expect(platesIn(resume), findsOneWidget);
    expect(platesIn(download), findsNWidgets(2));
    expect(find.byType(LiquidGlass), findsNWidgets(5));
  });

  testWidgets('contrast over Big Buck Bunny: titel, tags en glasknoppen', (tester) async {
    await glassPhone(tester, glass: true);
    const sceneKey = Key('scene');
    const backKey = Key('back'), downloadKey = Key('download'), watchKey = Key('watch'), resumeKey = Key('resume');

    // Every foreground is painted transparent with its shadow kept, so the
    // meter reads the background the real glyph sits on.
    await tester.pumpWidget(
      MaterialApp(
        theme: glassPhoneTheme(),
        home: RepaintBoundary(
          key: sceneKey,
          child: Material(
            color: Colors.black,
            child: Align(
              alignment: Alignment.topCenter,
              child: Stack(
                children: [
                  MobileDetailHero(
                    debugTransparentForeground: true,
                    artwork: RawImage(image: _lightSceneImage, fit: BoxFit.cover),
                    title: _kTitle,
                    chips: const ['2008', 'G', '9min', '1080p', 'AAC 5.1'],
                    actions: Column(
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
                        GlassLayer(
                          child: Row(
                            children: [
                              Expanded(
                                child: GlassCapsuleButton(
                                  key: downloadKey,
                                  icon: Icons.download_rounded,
                                  label: 'Download',
                                  foregroundColor: Colors.transparent,
                                  onPressed: () {},
                                ),
                              ),
                              const SizedBox(width: 12),
                              GlassCircleButton(
                                key: watchKey,
                                size: GlassCapsuleButton.height,
                                icon: Icons.add_rounded,
                                tooltip: 'Add',
                                foregroundColor: Colors.transparent,
                                onPressed: () {},
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  MobileDetailHeroBar(
                    leading: GlassCircleButton(
                      key: backKey,
                      icon: Icons.arrow_back_rounded,
                      tooltip: 'Back',
                      foregroundColor: Colors.transparent,
                      onPressed: () {},
                    ),
                  ),
                ],
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
      'title': await text(find.text(_kTitle)),
      for (final chip in const ['2008', 'G', '9min', '1080p', 'AAC 5.1']) 'chip $chip': await text(find.text(chip)),
      'resume label': await text(labelIn(resumeKey), color: Colors.black),
      'download label': await text(labelIn(downloadKey)),
      'back icon': await text(iconIn(backKey)),
      'watchlist icon': await text(iconIn(watchKey)),
    };
    debugPrint('LG-02 contrast: ${results.map((k, v) => MapEntry(k, v.toStringAsFixed(2)))}');

    for (final e in results.entries) {
      final floor = e.key.endsWith('icon') ? 3.0 : 4.5;
      expect(e.value, greaterThanOrEqualTo(floor), reason: '${e.key} ${e.value.toStringAsFixed(2)} < $floor');
    }
  });
}
