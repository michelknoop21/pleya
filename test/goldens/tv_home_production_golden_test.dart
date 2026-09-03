/// Fase 8: production visual acceptance for the TV Home
/// (`docs/assets/tvos-unified/northstar/01-home.jpg` and `02-home-rail-focus.jpg`,
/// binding per [DEC-065]).
///
/// The renders come from the real widgets and the real providers — a
/// `TvContentFeed` inside the fase-7 `TvRootShell`, fed by a real
/// `TvHomeProjectionProvider` projecting fixture `DiscoverProvider` data
/// through `HomeProjectionService`. There is deliberately no parallel
/// "home fixture screen" reconstructing the layout: a picture produced by a
/// stand-in proves the stand-in.
///
/// The shell is included rather than cropped away because 33.1's binding list
/// is about the *page* — a rounded card inset from the edges, under a top
/// navigation, with the first row peeking below it — and a render of the feed
/// alone could not show any of those relationships.
///
/// Regenerate after an intentional visual change:
/// `flutter test --update-goldens test/goldens/tv_home_production_golden_test.dart`
library;

import 'package:flutter/material.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';
import 'package:pleya/widgets/tv/tv_content_feed.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_expandable_media_tile.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:provider/provider.dart';

import '../test_helpers/golden.dart';
import '../test_helpers/prefs.dart';
import '../test_helpers/tv_discovery_artwork.dart';

// Two poolable backends, so a fixture meant to prove a real cross-server merge
// actually can merge (hoofdstuk 4.2 never merges `pleyaServer`/`local`).
const _servers = [
  (id: 'nas', name: 'NAS', backend: MediaBackend.plex),
  (id: 'attic', name: 'Zolder', backend: MediaBackend.jellyfin),
];

MediaItem _film(
  String id, {
  required String title,
  required TvDiscoveryMood mood,
  String genre = 'Drama',
  int year = 2024,
  String? releasedAt,
  String serverId = 'nas',
  MediaBackend backend = MediaBackend.plex,
  String? summary,
  bool posterOnly = false,
}) {
  final artwork = TvDiscoveryArtwork.indexOfMood(mood);
  return MediaItem(
    id: id,
    backend: backend,
    kind: MediaKind.movie,
    title: title,
    year: year,
    originallyAvailableAt: releasedAt,
    summary: summary ?? '$title is a $genre film with enough prose to fill the billboard and the rail context block.',
    genres: [genre],
    durationMs: 106 * 60 * 1000,
    serverId: serverId,
    serverName: serverId,
    thumbPath: TvDiscoveryArtwork.pathFor(artwork),
    // Hoofdstuk 9.4 "Alleen poster": no wide art at all, so `tvHeroArtFor`
    // resolves to [TvHeroArtKind.posterFill] rather than cover-cropping a 2:3
    // poster across a 2.465:1 card.
    artPath: posterOnly ? null : TvDiscoveryArtwork.widePathFor(artwork),
  );
}

MediaItem _episode(
  String id, {
  required String show,
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
    grandparentTitle: show,
    grandparentId: 'show-$id',
    parentIndex: season,
    index: episode,
    durationMs: 48 * 60 * 1000,
    viewOffsetMs: 20 * 60 * 1000,
    summary: '$show keeps a viewer mid-episode, so the card has a real offset to show.',
    genres: const ['Drama'],
    serverId: 'nas',
    serverName: 'nas',
    thumbPath: TvDiscoveryArtwork.widePathFor(artwork),
    grandparentThumbPath: TvDiscoveryArtwork.pathFor(artwork),
    artPath: TvDiscoveryArtwork.widePathFor(artwork),
  );
}

MediaHub _hub(String id, String title, List<MediaItem> items) => MediaHub(
  id: id,
  identifier: id,
  title: title,
  type: 'movie',
  items: items,
  size: items.length,
  serverId: 'nas',
  serverName: 'NAS',
);

class _FakeAggregation extends DataAggregationService {
  _FakeAggregation(super.serverManager);

  List<MediaItem> onDeck = const [];
  List<MediaHub> hubs = const [];
  List<MediaItem> latestMovies = const [];
  Set<String>? succeeded;

  Set<String> get _all => {for (final s in _servers) s.id};

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: onDeck, succeededServerIds: succeeded ?? serverIds ?? _all);

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubs, succeededServerIds: succeeded ?? serverIds ?? _all);

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: latestMovies, succeededServerIds: succeeded ?? serverIds ?? _all);
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

  late MultiServerProvider multiServer;
  late DiscoverProvider discover;
  late TvHomeProjectionProvider projection;
  late TvNavigationCoordinator coordinator;
  late FocusMemoryTracker navNodes;
  late FocusScopeNode navScope;
  late FocusScopeNode contentScope;

  Future<void> boot(
    WidgetTester tester, {
    List<MediaItem> latestMovies = const [],
    List<MediaItem> onDeck = const [],
    List<MediaHub> hubs = const [],
    Set<String>? succeeded,
    Locale? locale,
    bool dark = true,
    // Hoofdstuk 29's `reduce-motion` scenario. Passed as a `MediaQuery`
    // override rather than an accessibility-feature flag because that is the
    // value `reduceMotion()` and the carousel's `_canRotate` actually read.
    bool disableAnimations = false,
    List<({MediaBackend backend, String id, String name})> servers = _servers,
  }) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final manager = MultiServerManager();
    for (final server in servers) {
      manager.debugRegisterClientForTesting(_FakeClient(serverId: server.id, backend: server.backend));
    }
    final aggregation = _FakeAggregation(manager)
      ..latestMovies = latestMovies
      ..onDeck = onDeck
      ..hubs = hubs
      ..succeeded = succeeded;
    multiServer = MultiServerProvider(manager, aggregation);
    final hiddenLibraries = HiddenLibrariesProvider();
    final libraries = LibrariesProvider();
    discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
    addTearDown(discover.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    await discover.load();
    projection = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: t.discover.continueWatching,
      latestMoviesTitle: t.discover.recentlyReleased,
    );
    addTearDown(projection.dispose);
    for (var i = 0; i < 80 && projection.isProjecting; i++) {
      await Future<void>.value();
    }

    coordinator = TvNavigationCoordinator(initial: TvDestinationId.home)
      ..updateConditions(const TvNavConditions(hasLiveTv: false))
      ..activate(TvDestinationId.home);
    navNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
    navScope = FocusScopeNode(debugLabel: 'nav');
    contentScope = FocusScopeNode(debugLabel: 'content');
    addTearDown(coordinator.dispose);
    addTearDown(navNodes.dispose);
    addTearDown(navScope.dispose);
    addTearDown(contentScope.dispose);

    setGoldenSurfaceSize(tester);
    final theme = monoTheme(dark: dark);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            locale: locale,
            builder: disableAnimations
                ? (context, child) =>
                      MediaQuery(data: MediaQuery.of(context).copyWith(disableAnimations: true), child: child!)
                : null,
            home: Scaffold(
              backgroundColor: theme.extension<MonoTokens>()!.bg,
              body: InputModeTracker(
                child: TvRootShell(
                  coordinator: coordinator,
                  contentFocus: TvContentFocusAuthority(),
                  navNodes: navNodes,
                  navFocusScope: navScope,
                  contentFocusScope: contentScope,
                  isNavFocused: false,
                  profile: null,
                  onSelectDestination: (_) {},
                  onFocusDestination: coordinator.activate,
                  onFocusContent: ({bool restorePreviousFocus = true}) {},
                  onFocusNav: () {},
                  onOpenProfiles: () {},
                  onOverlaySheetOpenChanged: (_) {},
                  onKeyEvent: (_) => KeyEventResult.ignored,
                  selectLibrary: null,
                  openSettings: null,
                  dismissNestedRoute: ([_]) {},
                  child: const TvContentFeed(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    // The wordmark is an `Image.asset` and decoding is asynchronous; without
    // this it lands in the slower pictures and misses the faster ones. Both
    // layers, and named by the widget rather than by string, so a renamed asset
    // cannot leave this precache silently pointing at nothing.
    for (final asset in PleyaWordmark.assets) {
      await tester.runAsync(() => precacheImage(AssetImage(asset), tester.element(find.byType(TvRootShell))));
    }
    await tester.pumpAndSettle();
  }

  TvContentFeedState feed(WidgetTester tester) => tester.state<TvContentFeedState>(find.byType(TvContentFeed));

  FocusNode heroNode(WidgetTester tester, String label) => tester
      .widgetList<Focus>(find.byType(Focus))
      .map((f) => f.focusNode)
      .whereType<FocusNode>()
      .firstWhere((n) => n.debugLabel == label);

  /// The title the billboard is currently showing, read the way
  /// `tv_hero_billboard_carousel_test.dart` reads it.
  String heroTitle(WidgetTester tester) =>
      heroTitleFor(tester.widget<TvHeroBillboardCard>(find.byType(TvHeroBillboardCard)).group);

  Future<void> shoot(WidgetTester tester, String name) =>
      expectMatchesGolden(find.byType(MaterialApp), 'tv_home_production_$name');

  List<MediaItem> recentFilms() => [
    _film(
      'dune',
      title: 'Blue Signal',
      mood: TvDiscoveryMood.brightBlue,
      genre: 'Science fiction',
      releasedAt: '2024-08-01',
    ),
    _film(
      'canopy',
      title: 'Under the Canopy',
      mood: TvDiscoveryMood.greenNature,
      genre: 'Documentary',
      releasedAt: '2024-07-01',
    ),
    _film('harbour', title: 'The Long Harbour', mood: TvDiscoveryMood.warmOrange, releasedAt: '2024-06-01'),
    _film('arcade', title: 'Arcade Midnight', mood: TvDiscoveryMood.neon, genre: 'Thriller', releasedAt: '2024-05-01'),
  ];

  List<MediaItem> continueWatching() => [
    _episode('harbourlight', show: 'Harbourlight', mood: TvDiscoveryMood.warmOrange, season: 2, episode: 4),
    _film('cw-kite', title: 'Paper Kite Parade', mood: TvDiscoveryMood.familyAnimation, genre: 'Animation'),
    _film('cw-neighbours', title: 'The Neighbours Downstairs', mood: TvDiscoveryMood.lightComedy, genre: 'Comedy'),
    _film('cw-wintering', title: 'Wintering', mood: TvDiscoveryMood.coldNoir),
  ];

  List<MediaHub> recommendationHubs() => [
    _hub('top-picks', 'Top Picks for You', [
      _film('quarry', title: 'Quarry Road', mood: TvDiscoveryMood.darkDrama),
      _film('salt', title: 'Salt and Compass', mood: TvDiscoveryMood.desertEpic, genre: 'Adventure'),
      _film('lantern', title: 'Lantern Hour', mood: TvDiscoveryMood.pastelRomance, genre: 'Romance'),
      _film('atlas', title: 'Atlas Unbound', mood: TvDiscoveryMood.brightBlue, genre: 'Science fiction'),
    ]),
  ];

  Future<void> bootFull(WidgetTester tester, {Locale? locale, Set<String>? succeeded}) => boot(
    tester,
    latestMovies: recentFilms(),
    onDeck: continueWatching(),
    hubs: recommendationHubs(),
    locale: locale,
    succeeded: succeeded,
  );

  testWidgets('Home at rest', (tester) async {
    await bootFull(tester);
    // 33.1: a rounded card in the page, the first row's label and the tops of
    // its cards below it, and nothing between the bar and the card.
    await shoot(tester, 'default');
  });

  testWidgets('Home with the Afspelen pill focused', (tester) async {
    await bootFull(tester);
    feed(tester).focusPrimary();
    await tester.pumpAndSettle();
    await shoot(tester, 'play_focused');
  });

  testWidgets('Home with the Meer info pill focused', (tester) async {
    await bootFull(tester);
    heroNode(tester, 'tvHeroMoreInfo').requestFocus();
    await tester.pumpAndSettle();
    await shoot(tester, 'more_info_focused');
  });

  testWidgets('Home with the first content row focused', (tester) async {
    await bootFull(tester);
    // 33.2: the hero scrolls away under the bar, its text fades, and the
    // focused card expands to 16:9 beside its 2:3 neighbours with the metadata
    // block underneath.
    final rails = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).toList();
    rails.first.focusCurrent();
    await tester.pumpAndSettle();
    await shoot(tester, 'first_row_focused');
  });

  testWidgets('Home with a later content row focused', (tester) async {
    await bootFull(tester);
    final rails = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).toList();
    rails[2].focusCurrent();
    await tester.pumpAndSettle();
    await shoot(tester, 'later_row_focused');
  });

  testWidgets('Home with a single-slide hero', (tester) async {
    await boot(
      tester,
      latestMovies: [
        _film('only', title: 'The Only Recent One', mood: TvDiscoveryMood.desertEpic, releasedAt: '2024-08-01'),
      ],
      onDeck: continueWatching(),
      hubs: recommendationHubs(),
    );
    await shoot(tester, 'single_slide_hero');
  });

  testWidgets('Home with no recent films at all', (tester) async {
    // Hoofdstuk 9.5's last sentence: the billboard falls through to the first
    // Continue Watching title rather than collapsing.
    await boot(tester, onDeck: continueWatching(), hubs: recommendationHubs());
    await shoot(tester, 'fallback_hero');
  });

  // ---------------------------------------------------------------------------
  // Hoofdstuk 29's remaining automatable Home scenarios. Each of these has
  // behavioural proof elsewhere; what was missing was the deterministic
  // picture hoofdstuk 29 asks every scenario for.
  // ---------------------------------------------------------------------------

  // `tvos.home.unified.single-server`, and deliberately **not** a golden.
  //
  // Captured as a picture it came out byte-identical to `default`, for a
  // reason worth writing down rather than working around: every title in this
  // fixture lives on `nas`, so the second registered server contributes no
  // items and nothing on the page is drawn from provenance. A golden that
  // cannot differ cannot fail, and this file already carries one lesson of
  // that kind (see the long-titles test below).
  //
  // What is worth asserting is the thing that would actually break: a lone
  // source must never present itself as several.
  testWidgets('Home with a single server behind it offers no multi-source affordance', (tester) async {
    await boot(
      tester,
      latestMovies: recentFilms(),
      onDeck: continueWatching(),
      hubs: recommendationHubs(),
      servers: const [(id: 'nas', name: 'NAS', backend: MediaBackend.plex)],
    );
    expect(find.byType(TvContentFeed), findsOneWidget);
    expect(find.byType(TvDiscoveryRail), findsWidgets);
    expect(find.byType(TvSourceCountBadge), findsNothing, reason: 'one server cannot produce a multi-source group');
  });

  // `tvos.home.unified.light`. Hoofdstuk 8.2's light surface under the whole
  // composition, not just under the billboard: `tv_hero_billboard_light_theme`
  // pictures the hero card alone, so the bar, the row labels and the card
  // footers on a light ground were never rendered together.
  testWidgets('Home on the light palette', (tester) async {
    await boot(
      tester,
      latestMovies: recentFilms(),
      onDeck: continueWatching(),
      hubs: recommendationHubs(),
      dark: false,
    );
    // Mechanism before picture, the way the other light-theme goldens in this
    // suite do it: the bar must be drawing the split lockup here, not the
    // undivided file whose white letters this palette swallows (J18).
    final tk = Theme.of(tester.element(find.byType(TvRootShell))).extension<MonoTokens>()!;
    expect(tk.isLight, isTrue);
    expect(
      tester
          .widgetList<Image>(find.byType(Image))
          .where((i) => i.image is AssetImage && (i.image as AssetImage).assetName == PleyaWordmark.letteringAsset)
          .single
          .color,
      tk.text,
      reason: 'the tinted lettering layer is what makes the wordmark readable on light',
    );
    await shoot(tester, 'light');
  });

  // `tvos.home.unified.reduce-motion`, and deliberately not a golden either —
  // for the opposite reason to the one above. Settled and at rest, Reduce
  // Motion is *supposed* to change nothing about the composition, so its
  // picture is byte-identical to `default` by design. The regression it has to
  // catch is a timer, and a still frame cannot see one.
  //
  // So this makes the pair of assertions a picture cannot: the billboard
  // stands still when motion is suppressed and moves when it is not, from the
  // same fixture with autoplay left on in both runs.
  testWidgets('Home under Reduce Motion keeps the billboard still, and moves it otherwise', (tester) async {
    Future<String?> slideAfterAnAdvanceWindow({required bool disableAnimations}) async {
      await boot(
        tester,
        latestMovies: recentFilms(),
        onDeck: continueWatching(),
        hubs: recommendationHubs(),
        disableAnimations: disableAnimations,
      );
      expect(
        tester.widget<TvHeroBillboardCarousel>(find.byType(TvHeroBillboardCarousel)).autoplayEnabled,
        isTrue,
        reason: 'autoplay is on in both runs; Reduce Motion is what stops it, not the caller',
      );
      // Past a full auto-advance window, so a carousel that rotates has had
      // every chance to.
      await tester.pump(TvHomeLayout.heroAutoAdvance + const Duration(seconds: 1));
      await tester.pumpAndSettle();
      return heroTitle(tester);
    }

    final still = await slideAfterAnAdvanceWindow(disableAnimations: true);
    final moved = await slideAfterAnAdvanceWindow(disableAnimations: false);

    expect(still, isNotNull);
    expect(still, recentFilms().first.title, reason: 'Reduce Motion must leave the billboard on its first slide');
    expect(moved, isNot(still), reason: 'without Reduce Motion the same window must advance it');
  });

  // `tvos.home.unified.poster-fallback`. Hoofdstuk 9.4 "Alleen poster": the
  // poster sharp at its own 2:3 over a blurred, darkened wash of itself.
  // `tv_hero_artwork_test.dart` proves the *kind* resolves to `posterFill`;
  // this is the only place that shows what that draws.
  testWidgets('Home with a hero that has only a poster', (tester) async {
    await boot(
      tester,
      latestMovies: [
        _film(
          'poster-only',
          title: 'The Cartographer',
          mood: TvDiscoveryMood.coldNoir,
          releasedAt: '2024-08-01',
          posterOnly: true,
        ),
        ...recentFilms(),
      ],
      onDeck: continueWatching(),
      hubs: recommendationHubs(),
    );
    await shoot(tester, 'poster_fallback');
  });

  testWidgets('Home with a source that did not answer', (tester) async {
    await bootFull(tester, succeeded: {'nas'});
    final rails = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail)).toList();
    rails.first.focusCurrent();
    await tester.pumpAndSettle();
    await shoot(tester, 'partial_sources');
  });

  testWidgets('Home with long titles and prose', (tester) async {
    // This was a "long locale" render until an audit pointed out it could not
    // be one: slang's translations are deferred and a test binary has only the
    // base locale loaded, so passing a Material `Locale` changed nothing on a
    // page whose every string is either app copy or fixture data — the picture
    // came out byte-identical to `play_focused` and could not fail on a
    // long-string regression.
    //
    // What it can honestly stress is the half that *is* fixture data, and that
    // is the half at risk: the hero's title band and capped prose column, the
    // CTA row beside them, and a rail's metadata block. All of them reserve
    // fixed height, so a string that overruns has to ellipsize rather than push
    // the layout.
    await boot(
      tester,
      latestMovies: [
        _film(
          'long',
          title: 'Het Onvoorstelbaar Lange Verhaal van de Noordelijke Getijden en Alles Daarna',
          mood: TvDiscoveryMood.desertEpic,
          genre: 'Wetenschappelijke fictie en avontuur',
          releasedAt: '2024-08-01',
          summary:
              'Een uitzonderlijk lange synopsis die ver voorbij de twee regels loopt die de hero '
              'ervoor reserveert, zodat zichtbaar wordt dat hij afkapt in plaats van de knoppenrij '
              'eronder weg te duwen, en dat de tekstkolom zijn eigen breedte respecteert.',
        ),
        ...recentFilms(),
      ],
      onDeck: continueWatching(),
      hubs: recommendationHubs(),
    );
    feed(tester).focusPrimary();
    await tester.pumpAndSettle();
    await shoot(tester, 'long_titles');
  });
}
