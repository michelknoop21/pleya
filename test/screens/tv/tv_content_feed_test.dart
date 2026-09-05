/// Fase 8: the production TV Home, over real providers.
///
/// Where `tv_hero_billboard_carousel_test.dart` proves the carousel's own
/// contract in isolation, this file proves the things that only exist once the
/// hero and the feed are mounted together and fed by
/// `TvHomeProjectionProvider`:
///
/// * **Row focus does not change the hero.** The regression guard for the
///   behaviour this phase exists to remove (hoofdstuk 7.3, 31.9; deferred here
///   by DEC-066 punt 3 and DEC-067 punt 3). It is a behavioural assertion, not
///   a grep: walk a content row with the remote and read the billboard back.
/// * **The two deferred fase-6 Home-row requirements**
///   (`docs/tvos-unified-fase6-home-rows-deviation.md`): no duplicate logical
///   title inside one Home row, and activation through the fase-4 coördinator
///   rather than `navigateToMediaItem`.
/// * Continue Watching keeps exact-episode identity; a row whose sources did
///   not all answer says so; the feed's lifecycle flag reaches the carousel.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_content_feed.dart';
import 'package:pleya/widgets/tv/tv_content_row.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_expandable_media_tile.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
import 'package:pleya/widgets/tv/tv_section_header.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_carousel.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

const _servers = [
  (id: 'nas', name: 'NAS', backend: MediaBackend.plex),
  (id: 'attic', name: 'Zolder', backend: MediaBackend.jellyfin),
];

MediaItem _film(
  String id, {
  required String title,
  String serverId = 'nas',
  MediaBackend backend = MediaBackend.plex,
  String? releasedAt,
  int year = 2024,
}) => MediaItem(
  id: id,
  backend: backend,
  kind: MediaKind.movie,
  title: title,
  year: year,
  originallyAvailableAt: releasedAt,
  summary: '$title has enough prose for the hero and the rail context block.',
  genres: const ['Drama'],
  durationMs: 100 * 60 * 1000,
  serverId: serverId,
  serverName: serverId,
);

MediaItem _episode(String id, {required String show, required int season, required int episode}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode $episode',
  grandparentTitle: show,
  grandparentId: 'show-${show.toLowerCase()}',
  parentIndex: season,
  index: episode,
  durationMs: 45 * 60 * 1000,
  viewOffsetMs: 15 * 60 * 1000,
  serverId: 'nas',
  serverName: 'nas',
);

MediaHub _hub(String id, String title, List<MediaItem> items, {String type = 'movie'}) => MediaHub(
  id: id,
  identifier: id,
  title: title,
  type: type,
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

  /// Which servers answered. `null` means all of them — the honest default for
  /// every scenario except the partial-coverage one.
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
  _FakeClient({String serverId = 'nas', this.backend = MediaBackend.plex, this.externalIds = const {}})
    : serverId = ServerId(serverId);

  /// External ids per item id, so a test can hand two rows of one series the
  /// same series-wide tmdb/tvdb — the evidence hoofdstuk 11.8 forbids folding
  /// two different episodes on.
  final Map<String, ExternalIds> externalIds;

  @override
  final ServerId serverId;

  @override
  String? get serverName => serverId.value;

  @override
  final MediaBackend backend;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => externalIds[itemId] ?? const ExternalIds();

  /// What `WatchActions.setWatched`'s server write should record, and what
  /// `DiscoverProvider.updateItem`'s follow-up refetch should answer with —
  /// two different calls on the same client, both needed to prove the
  /// context menu's write actually reaches the card: [markWatchedCalls] shows
  /// the write landed, [fetchItemCalls] plus [fetchItemResult] show whether
  /// anything asked the server for the refreshed item afterwards.
  final List<String> markWatchedCalls = [];
  final List<String> markUnwatchedCalls = [];
  final List<String> fetchItemCalls = [];

  /// Keyed by item id — what [fetchItem] answers, so a test can hand back the
  /// post-write item (e.g. `withWatchedFlag(true)`) the way a real server
  /// would once the mark-watched call above has landed.
  final Map<String, MediaItem> fetchItemResult = {};

  @override
  Future<void> markWatched(MediaItem item) async {
    markWatchedCalls.add(item.id);
  }

  @override
  Future<void> markUnwatched(MediaItem item) async {
    markUnwatchedCalls.add(item.id);
  }

  @override
  Future<MediaItem?> fetchItem(String id) async {
    fetchItemCalls.add(id);
    return fetchItemResult[id];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  late _FakeAggregation aggregation;
  late MultiServerProvider multiServer;
  late DiscoverProvider discover;
  late TvHomeProjectionProvider projection;
  late MultiServerManager manager;

  /// The fake client `boot()` registered for [serverId], so a test can
  /// program its write/refetch behaviour (`markWatchedCalls`,
  /// `fetchItemResult`) before driving a context-menu write.
  _FakeClient fakeClient(String serverId) => manager.getClient(ServerId(serverId)) as _FakeClient;

  Future<void> boot(
    WidgetTester tester, {
    List<MediaItem> latestMovies = const [],
    List<MediaItem> onDeck = const [],
    List<MediaHub> hubs = const [],
    Set<String>? succeeded,
    Map<String, ExternalIds> externalIds = const {},
  }) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    manager = MultiServerManager();
    for (final server in _servers) {
      manager.debugRegisterClientForTesting(
        _FakeClient(serverId: server.id, backend: server.backend, externalIds: externalIds),
      );
    }
    aggregation = _FakeAggregation(manager)
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
    // Microtask-only yield: under `testWidgets` a real `Timer` never fires
    // without an explicit pump, so `Future.delayed` here would hang.
    for (var i = 0; i < 80 && projection.isProjecting; i++) {
      await Future<void>.value();
    }

    setGoldenSurfaceSize(tester);
    final offlineMode = OfflineModeProvider(manager, multiServerProvider: multiServer);
    addTearDown(offlineMode.dispose);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<TvHomeProjectionProvider>.value(value: projection),
          ChangeNotifierProvider<OfflineModeProvider>.value(value: offlineMode),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(child: Scaffold(body: const TvContentFeed())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  UnifiedMediaGroup heroGroup(WidgetTester tester) =>
      tester.widget<TvHeroBillboardCard>(find.byType(TvHeroBillboardCard)).group;

  FocusNode heroNode(WidgetTester tester, String label) => tester
      .widgetList<Focus>(find.byType(Focus))
      .map((f) => f.focusNode)
      .whereType<FocusNode>()
      .firstWhere((n) => n.debugLabel == label);

  List<TvContentRow> rows(WidgetTester tester) => tester.widgetList<TvContentRow>(find.byType(TvContentRow)).toList();

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pump();
    await tester.pump();
  }

  /// A content-row tile's own focus node — `tv_discovery_rail.dart` labels it
  /// `tvDiscoveryTile_$groupId`, so a test can focus one card without walking
  /// the remote across every tile in front of it.
  FocusNode tileNode(WidgetTester tester, String groupId) => heroNode(tester, 'tvDiscoveryTile_$groupId');

  /// Holds Select past `FocusableWrapper`'s long-press threshold — the
  /// hoofdstuk 23 gesture that opens a card's context menu, per
  /// `tv_unified_context_menu_reachability_test.dart`.
  Future<void> holdSelect(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  /// Focuses the control showing [label] inside an open overlay sheet and
  /// presses Select on it — `FocusableWrapper`/`TvPanelButton` carry no tap
  /// handler, so `tester.tap` silently does nothing on one of these (see
  /// `media_detail_screen_test.dart`'s helper of the same name).
  Future<void> activateByLabel(WidgetTester tester, String label) async {
    final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
    focus.requestFocus();
    await tester.pump();
    expect(focus.hasPrimaryFocus, isTrue, reason: 'the control under test must actually hold the focus');
    SelectKeyUpSuppressor.clearSuppression();
    await press(tester, LogicalKeyboardKey.select);
  }

  List<MediaItem> twoRecentFilms() => [
    _film('dune-nas', title: 'Dune', releasedAt: '2024-03-01'),
    _film('arrival-nas', title: 'Arrival', releasedAt: '2024-02-01'),
  ];

  group('rowfocus is not hero state (hoofdstuk 7.3 / 31.9)', () {
    testWidgets('walking a content row leaves the featured slide exactly where it was', (tester) async {
      // The regression this phase exists to prevent. Before fase 8,
      // `TvBrowseRail.onFocusedItemChanged` fed `_setSpotlightDebounced` and
      // the billboard became whatever the remote passed over, 180ms later.
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [
            _film('tp1', title: 'Quarry Road'),
            _film('tp2', title: 'Arcade Midnight'),
            _film('tp3', title: 'Wintering'),
          ]),
        ],
      );

      final before = heroGroup(tester).groupId;
      expect(before, isNotEmpty);

      // Into the first row, then along it — three deliberate D-pad steps, and
      // well past the 180ms the old debounce used to wait.
      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      final firstCard = FocusManager.instance.primaryFocus?.debugLabel;
      expect(firstCard, startsWith('tvDiscoveryTile_'), reason: 'sanity: the remote really is in a content row');

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 600));
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        isNot(firstCard),
        reason: 'sanity: the walk really passed over other titles',
      );

      // Back up to the hero and read it. Coming back rather than reading in
      // place is not a workaround: focusing a row scrolls the feed, so the
      // billboard is off screen while the walk happens (33.2), and the claim
      // being made is precisely that it is unchanged when the viewer returns
      // to it.
      await press(tester, LogicalKeyboardKey.arrowUp);
      // The feed jumps back to the top and focuses the hero in a post-frame
      // callback, so the billboard is one more frame away than the key press.
      await tester.pump();
      await tester.pump();
      expect(heroGroup(tester).groupId, before, reason: 'row focus must not select the featured title');
      expect(
        heroNode(tester, 'tvHeroPlay').hasFocus || heroNode(tester, 'tvHeroMoreInfo').hasFocus,
        isTrue,
        reason: 'hoofdstuk 7.3: UP from the first row reaches the hero even after the feed scrolled it away',
      );
    });

    testWidgets('the hero keeps its slide across a row focus round trip', (tester) async {
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
        ],
      );

      // Advance the carousel deliberately, then go down and come back.
      heroNode(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      final chosen = heroGroup(tester).groupId;

      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pump(const Duration(milliseconds: 600));
      expect(heroGroup(tester).groupId, chosen);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(heroGroup(tester).groupId, chosen, reason: 'coming back must not reset the slide either');
      expect(
        heroNode(tester, 'tvHeroMoreInfo').hasFocus,
        isTrue,
        reason: 'hoofdstuk 7.3: UP from the first row returns to the last used CTA',
      );
    });

    testWidgets('a content row exposes no way to name a featured title', (tester) async {
      // The architectural half of the same guarantee, and the reason this is
      // not a brittle grep: `TvContentRow.onActivate` is
      // `ValueChanged<UnifiedMediaGroup>` and the row has no other callback at
      // all. There is no parameter through which a focused card could reach
      // the carousel, so the coupling cannot be reintroduced by wiring — only
      // by adding a new parameter, which changes this type.
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
        ],
      );

      for (final row in rows(tester)) {
        expect(row.onActivate, isA<ValueChanged<UnifiedMediaGroup>>());
        expect(row.onFocusedGroupChanged, isA<ValueChanged<String>?>());
      }
    });
  });

  group('Home rows are unified (fase-6 deviation, closed here)', () {
    testWidgets('one logical title on two servers is one card, carrying both sources', (tester) async {
      // The first deferred requirement. `getLatestMoviesFromAllServers`
      // collapses identical guids only, so two servers' copies under different
      // ids survive into `latestMovies` as two concrete films — and used to
      // take two cards in the Recently Released row, directly under a hero
      // that showed them as one slide.
      await boot(
        tester,
        latestMovies: [
          _film('dune-nas', title: 'Dune', releasedAt: '2024-03-01'),
          _film(
            'dune-attic',
            title: 'Dune',
            releasedAt: '2024-03-01',
            serverId: 'attic',
            backend: MediaBackend.jellyfin,
          ),
        ],
      );

      expect(discover.latestMovies, hasLength(2), reason: 'precondition: two concrete films');

      final recentRow = rows(tester).firstWhere((r) => r.hub.title == t.discover.recentlyReleased);
      expect(recentRow.hub.groups, hasLength(1), reason: 'one logical title, one card');
      expect(recentRow.hub.groups.single.sources, hasLength(2), reason: 'both concrete sources survive on the group');
      expect(recentRow.hub.groups.single.sources.map((s) => s.serverId).toSet(), {'nas', 'attic'});
    });

    testWidgets('a title the pipeline cannot prove equal stays two cards', (tester) async {
      // False merge is worse than false negative (fase-8 brief §13). Two
      // different films that merely share a genre must not be collapsed, and
      // nothing here adds a title-only fuzzy merge.
      await boot(
        tester,
        latestMovies: [
          _film('a', title: 'Alpha', releasedAt: '2024-03-01'),
          _film('b', title: 'Bravo', releasedAt: '2024-02-01'),
        ],
      );

      final recentRow = rows(tester).firstWhere((r) => r.hub.title == t.discover.recentlyReleased);
      expect(recentRow.hub.groups, hasLength(2));
    });

    testWidgets('every row activates through the group, never through a concrete item', (tester) async {
      // The second deferred requirement. The type is the proof — see the
      // architectural test above — and this asserts the wiring reaches every
      // row rather than only the first.
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        onDeck: [_episode('e1', show: 'Harbourlight', season: 2, episode: 4)],
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
        ],
      );

      expect(rows(tester), hasLength(3), reason: 'Continue Watching, Recently Released, Top Picks');
      for (final row in rows(tester)) {
        expect(row.hub.groups, isNotEmpty);
        expect(row.onActivate, isNotNull);
      }
    });
  });

  group('Continue Watching (fase-8 brief §14)', () {
    testWidgets('two episodes of one show stay two cards', (tester) async {
      // Series-level conflation is the failure: "Verder kijken" is a list of
      // places you are in, and two of them in one show are two places.
      //
      // Both rows hang off the same show id and both resolve the same
      // series-wide tmdb *and* tvdb, so this cannot pass merely because the
      // fake client had no external ids to offer — the exact-episode identity
      // of hoofdstuk 11.8 is what keeps them apart.
      await boot(
        tester,
        onDeck: [
          _episode('e1', show: 'Harbourlight', season: 2, episode: 4),
          _episode('e2', show: 'Harbourlight', season: 3, episode: 1),
        ],
        externalIds: {'show-harbourlight': const ExternalIds(tmdb: 95396, tvdb: 371980)},
      );

      final cw = rows(tester).firstWhere((r) => r.hub.title == t.discover.continueWatching);
      expect(cw.hub.groups, hasLength(2));
      final labels = [
        for (final g in cw.hub.groups)
          '${g.representativeSource.item.parentIndex}x${g.representativeSource.item.index}',
      ];
      expect(labels.toSet(), {'2x4', '3x1'});
    });

    testWidgets('Continue Watching leads the feed', (tester) async {
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        onDeck: [_episode('e1', show: 'Harbourlight', season: 2, episode: 4)],
      );
      expect(rows(tester).first.hub.title, t.discover.continueWatching);
    });
  });

  group('honest projection (fase-8 brief §21)', () {
    testWidgets('a row whose sources did not all answer says so, and still shows what it has', (tester) async {
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        // The attic never answered. The row is real, and partial.
        succeeded: {'nas'},
      );

      final recentRow = rows(tester).firstWhere((r) => r.hub.title == t.discover.recentlyReleased);
      expect(recentRow.hub.isPartial, isTrue);
      expect(recentRow.hub.groups, isNotEmpty, reason: 'healthy content stays fully usable (hoofdstuk 21.4)');
      // Hoofdstuk 41: a footnote, not a banner — the heading carries a glyph
      // with the wording on its semantics label, never a visible sentence
      // competing with the row title.
      // Hoofdstuk 41: the heading carries the state as a glyph with the wording
      // on its semantics label — a footnote, never a visible sentence competing
      // with the row title it annotates.
      final headers = tester
          .widgetList<TvSectionHeader>(find.byType(TvSectionHeader, skipOffstage: false))
          .where((h) => h.title == t.discover.recentlyReleased);
      expect(headers, hasLength(1));
      expect(headers.single.isPartial, isTrue);
      expect(headers.single.partialLabel, t.unifiedCatalog.discovery.partial);
      expect(find.text(t.unifiedCatalog.discovery.partial, skipOffstage: false), findsNothing);
    });
  });

  group('the empty and near-empty hero (fase-8 brief §22)', () {
    testWidgets('no recent films falls back to the first Continue Watching title', (tester) async {
      await boot(tester, onDeck: [_episode('e1', show: 'Harbourlight', season: 2, episode: 4)]);

      expect(find.byType(TvHeroBillboardCarousel), findsOneWidget);
      expect(heroGroup(tester).representativeSource.item.grandparentTitle, 'Harbourlight');
      // One slide, not a rotation over the library: this is a stand-in for a
      // featured title and must not claim these are new releases.
      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
      expect(heroGroup(tester).representativeSource.item.grandparentTitle, 'Harbourlight');
    });

    testWidgets('no hero and no rows at all is the empty state, not a blank page', (tester) async {
      await boot(tester);
      expect(find.byType(TvHeroBillboardCarousel), findsNothing);
      expect(find.text(t.discover.noContentAvailable), findsOneWidget);
    });

    testWidgets('a single-slide hero renders and does not rotate', (tester) async {
      await boot(
        tester,
        latestMovies: [_film('only', title: 'The Only Recent One', releasedAt: '2024-03-01')],
      );

      final only = heroGroup(tester).groupId;
      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
      expect(heroGroup(tester).groupId, only);
    });
  });

  group('lifecycle (hoofdstuk 9.6)', () {
    testWidgets('leaving the destination stops the rotation, and returning resumes it', (tester) async {
      await boot(tester, latestMovies: twoRecentFilms());

      final key = tester.state<TvContentFeedState>(find.byType(TvContentFeed));
      final first = heroGroup(tester).groupId;

      key.setDestinationActive(false);
      await tester.pump();
      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
      expect(heroGroup(tester).groupId, first, reason: 'a Home nobody is looking at must not rotate');

      key.setDestinationActive(true);
      await tester.pump();
      await tester.pump(TvHomeLayout.heroAutoAdvance);
      expect(heroGroup(tester).groupId, isNot(first), reason: 'and coming back resumes it');
    });

    testWidgets('a focused content row holds the rotation and fades the hero text', (tester) async {
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
        ],
      );

      final before = heroGroup(tester).groupId;
      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);

      await tester.pump(TvHomeLayout.heroAutoAdvance * 3);
      expect(heroGroup(tester).groupId, before, reason: 'hoofdstuk 9.6: a focused content row holds the timer');
      expect(
        tester.widget<TvHeroBillboardCard>(find.byType(TvHeroBillboardCard)).textOpacity,
        0,
        reason: '33.2: focus leaving the hero dims its text',
      );
    });
  });

  group('P1: the hero comes back into view, not just back into the focus tree', () {
    /// The feed's own scroll offset. Exposed by `TvContentFeedState` for this
    /// assertion specifically — the defect satisfied "a hero CTA is focused"
    /// while failing "the hero is on screen", so a test that checked only the
    /// first would have stayed green through the whole bug.
    double offset(WidgetTester tester) => tester.state<TvContentFeedState>(find.byType(TvContentFeed)).scrollOffset;

    Future<void> bootTallFeed(WidgetTester tester) => boot(
      tester,
      latestMovies: twoRecentFilms(),
      hubs: [
        _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road'), _film('tp2', title: 'Arcade Midnight')]),
        _hub('hidden-gems', 'Hidden Gems', [_film('hg1', title: 'Wintering'), _film('hg2', title: 'Salt Flats')]),
        _hub('for-you', 'For You', [_film('fy1', title: 'Longline'), _film('fy2', title: 'Nightjar')]),
      ],
    );

    testWidgets('UP from the first row restores the scroll position and the CTA together', (tester) async {
      await bootTallFeed(tester);

      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      expect(offset(tester), 0, reason: 'the feed opens at the top');

      // DOWN into the first row. One rail is ~57% of the canvas, so focusing it
      // scrolls the billboard off the top — which is the state UP has to
      // recover from, and the reason this is asserted rather than assumed.
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        offset(tester),
        greaterThan(0),
        reason: 'if the feed never scrolled, this test is not exercising the case it exists for',
      );

      await press(tester, LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(offset(tester), 0, reason: 'the billboard is back on screen, not merely back in the focus tree');
      expect(FocusManager.instance.primaryFocus?.debugLabel, anyOf('tvHeroPlay', 'tvHeroMoreInfo'));
    });

    testWidgets('and does it again on the second round trip', (tester) async {
      // The early return only fired while the carousel was still mounted, which
      // is exactly the *second* visit: the first UP may have found it disposed
      // and taken the post-frame path by luck.
      await bootTallFeed(tester);
      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();

      for (var round = 0; round < 2; round++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();
        expect(offset(tester), 0, reason: 'round $round left the hero off screen');
        expect(FocusManager.instance.primaryFocus?.debugLabel, anyOf('tvHeroPlay', 'tvHeroMoreInfo'));
      }
    });

    testWidgets('UP returns to the CTA the viewer last used, not always to Afspelen', (tester) async {
      // Hoofdstuk 7.3's actual wording. Restoring the scroll first must not cost
      // the "last used" half of it.
      await bootTallFeed(tester);
      heroNode(tester, 'tvHeroMoreInfo').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(offset(tester), 0);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroMoreInfo');
    });

    testWidgets('HERO4: DOWN out of the top navigation restores the scroll too', (tester) async {
      // `focusPrimary()` is what the shell calls for DOWN out of the bar
      // (`focusActiveTabIfReady`), and it reaches the hero without any
      // traversal in between — so nothing scrolls on its behalf. The feed it
      // arrives at is very often not at the top: leaving Home for another
      // destination keeps the scroll position (hoofdstuk 9.6), and so does
      // coming back from a pushed content route. Before this, the CTA took the
      // ring on a billboard 721 px above the fold, its button row drawn under
      // the opaque top band with no artwork behind it (HERO4, photographed on
      // hardware and measured in `/v1/ui_tree`).
      await bootTallFeed(tester);

      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        offset(tester),
        greaterThan(0),
        reason: 'if the feed never scrolled, this test is not exercising the case it exists for',
      );

      // The destination switch the shell performs, which is what leaves the
      // feed scrolled with the ring outside it.
      final feed = tester.state<TvContentFeedState>(find.byType(TvContentFeed));
      feed.setDestinationActive(false);
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      feed.setDestinationActive(true);
      await tester.pump();

      expect(feed.focusPrimary(), isTrue);
      await tester.pumpAndSettle();

      expect(offset(tester), 0, reason: 'the billboard is on screen under the CTA that just took the ring');
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');
    });

    testWidgets('HERO4: the billboard comes back into view whoever hands the CTA the ring', (tester) async {
      // The press the report was photographed on does not go through any entry
      // point of this widget, which is why hardening them was not enough.
      //
      // Play something from a Home row and come back. `onPlaybackReturned`
      // refreshes the item, Home re-projects, and the tile the push left from
      // is gone — so the shared content scope has no remembered child, and
      // `FocusScopeNode.requestFocus` descends into the *first focusable
      // descendant* of the content instead. Since DEC-095 the carousel is a
      // layer beside the list rather than a child of it, so it is mounted at
      // any scroll offset and that first descendant is the Afspelen pill. The
      // ring lands on it, `focusPrimary()` is never called, and the feed stays
      // 721 px down: artwork above the fold, the pill drawn at y=19 behind the
      // opaque top band. Measured over the real remote path in
      // `tvos.home.hero-return-after-playback`, focus-trace hop 14
      // (`play_button -> tvHeroPlay` on `key:Escape`).
      //
      // So the invariant is not "these three callers scroll first" but "the
      // billboard holding the ring means the billboard is on screen", and it
      // is asserted here the only way that distinguishes them: by focusing the
      // node directly, exactly as the scope does.
      await bootTallFeed(tester);

      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        offset(tester),
        greaterThan(0),
        reason: 'if the feed never scrolled, this test is not exercising the case it exists for',
      );

      // What the pop does: the remembered child is gone, the scope descends.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();
      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvHeroPlay');
      expect(offset(tester), 0, reason: 'the CTA holds the ring, so the billboard is under it');
    });
  });

  group('restoration (hoofdstuk 7.6 / fase-8 brief §19)', () {
    testWidgets('the feed returns the remote to the card it left, by group id', (tester) async {
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road'), _film('tp2', title: 'Arcade Midnight')]),
        ],
      );

      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      final left = FocusManager.instance.primaryFocus?.debugLabel;
      expect(left, startsWith('tvDiscoveryTile_'));

      // A destination switch: focus goes elsewhere, the feed stays mounted.
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pump();

      expect(tester.state<TvContentFeedState>(find.byType(TvContentFeed)).focusRestored(), isTrue);
      await tester.pump();
      expect(FocusManager.instance.primaryFocus?.debugLabel, left);
    });

    testWidgets('DOWN out of the hero lands on the first row on screen, not the first row ever built', (tester) async {
      // `_rowKeys` is a `putIfAbsent` map, so its iteration order is
      // first-ever-insertion. A Home-layout reorder changes what is drawn first
      // without changing that, and walking the keys would then hand DOWN to a
      // row further down the page. Simulated here by re-projecting with the
      // hubs in the other order, which is the same thing from the feed's side:
      // the row list changes, the key map does not.
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
          _hub('hidden-gems', 'Hidden Gems', [_film('hg1', title: 'Wintering')]),
        ],
      );
      expect(rows(tester).map((r) => r.hub.title), containsAllInOrder(['Top Picks', 'Hidden Gems']));

      aggregation.hubs = [
        _hub('hidden-gems', 'Hidden Gems', [_film('hg1', title: 'Wintering')]),
        _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
      ];
      await discover.load();
      for (var i = 0; i < 80 && projection.isProjecting; i++) {
        await Future<void>.value();
      }
      await tester.pumpAndSettle();

      final first = rows(tester).first;
      tester.state<TvContentFeedState>(find.byType(TvContentFeed)).focusPrimary();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'tvDiscoveryTile_${first.hub.groups.first.groupId}',
        reason: 'DOWN goes to the row the viewer can see at the top, whatever order the keys were made in',
      );
    });

    testWidgets('rows keep their own state identity across a re-projection', (tester) async {
      await boot(
        tester,
        latestMovies: twoRecentFilms(),
        hubs: [
          _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road')]),
        ],
      );

      final keysBefore = [for (final row in rows(tester)) row.railKey];
      // A rebuild with the same projection must not hand a row a different key
      // — that is what would remount its `TvDiscoveryRailState` and lose its
      // focus nodes and scroll offset.
      await tester.pump();
      final keysAfter = [for (final row in rows(tester)) row.railKey];
      expect(keysAfter, keysBefore);
      expect(keysBefore.toSet(), hasLength(keysBefore.length), reason: 'no two rows may share a GlobalKey');
      expect(rows(tester).map((r) => r.railKey), everyElement(isA<GlobalKey<TvDiscoveryRailState>>()));
    });
  });

  group('LAND4: a vertical step on Home arrives at the column it left from', () {
    List<MediaItem> films(String prefix, int count) => [
      for (var i = 0; i < count; i++) _film('$prefix$i', title: '$prefix $i'),
    ];

    Future<void> bootTwoRows(WidgetTester tester) => boot(
      tester,
      hubs: [_hub('top-picks', 'Top Picks', films('tp', 10)), _hub('hidden-gems', 'Hidden Gems', films('hg', 10))],
    );

    String? focusedTile() {
      final label = FocusManager.instance.primaryFocus?.debugLabel;
      const prefix = 'tvDiscoveryTile_';
      return label != null && label.startsWith(prefix) ? label.substring(prefix.length) : null;
    }

    testWidgets('DOWN out of a walked row lands under the card it left', (tester) async {
      await bootTwoRows(tester);
      final feedRows = rows(tester);
      expect(feedRows, hasLength(2), reason: 'sanity: two stacked rows');

      tileNode(tester, feedRows.first.hub.groups.first.groupId).requestFocus();
      await tester.pumpAndSettle();
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      await tester.pumpAndSettle();
      expect(focusedTile(), feedRows.first.hub.groups[4].groupId);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(focusedTile(), feedRows.last.hub.groups[4].groupId);
    });

    testWidgets('the row below may remember where it was left, but it does not decide', (tester) async {
      // The negative control at feed level: a row's scroll offset is its
      // memory, and geometry read that memory as a destination.
      await bootTwoRows(tester);
      final feedRows = rows(tester);

      tileNode(tester, feedRows.last.hub.groups.first.groupId).requestFocus();
      await tester.pumpAndSettle();
      for (var i = 0; i < 8; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
      }
      await tester.pumpAndSettle();
      expect(focusedTile(), feedRows.last.hub.groups[8].groupId, reason: 'sanity: the lower row is parked far right');

      tileNode(tester, feedRows.first.hub.groups[1].groupId).requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(focusedTile(), feedRows.last.hub.groups[1].groupId);
    });

    testWidgets('UP out of the top row still reaches the hero', (tester) async {
      // The edge the stack deliberately does not own: above the first row is
      // the billboard, and hoofdstuk 7.3 sends UP back to its last-used CTA.
      await bootTwoRows(tester);
      final feedRows = rows(tester);

      tileNode(tester, feedRows.first.hub.groups[3].groupId).requestFocus();
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();

      expect(focusedTile(), isNull, reason: 'the focus left the rows');
      expect(FocusManager.instance.primaryFocus?.debugLabel, isNot(startsWith('tvDiscoveryTile_')));
    });
  });

  group('hoofdstuk 23\'s menu reacts on every row, not only Continue Watching', () {
    testWidgets('marking a hub-row title watched updates that exact card', (tester) async {
      final movie = _film('dune-nas', title: 'Dune', releasedAt: '2024-01-01');
      await boot(
        tester,
        hubs: [
          _hub('top-picks', 'Top Picks', [movie]),
        ],
      );
      addTearDown(SelectKeyUpSuppressor.clearSuppression);

      final groupId = rows(tester).single.hub.groups.single.groupId;
      expect(rows(tester).single.hub.groups.single.watchState.isWatched, isFalse, reason: 'starts unwatched');

      // What the server answers once `markWatched` has actually landed —
      // proof the refresh this test is about really asked for it, not just
      // that a write happened somewhere.
      fakeClient('nas').fetchItemResult['dune-nas'] = movie.withWatchedFlag(true);

      tileNode(tester, groupId).requestFocus();
      await tester.pump();
      SelectKeyUpSuppressor.clearSuppression();
      await holdSelect(tester);
      expect(find.text(t.mediaMenu.markAsWatched), findsOneWidget, reason: 'the long press must open the menu');

      await activateByLabel(tester, t.mediaMenu.markAsWatched);
      // The write, the notify and the incremental refetch are all async;
      // settle every microtask/timer this scenario schedules.
      await tester.pumpAndSettle();

      expect(fakeClient('nas').markWatchedCalls, contains('dune-nas'), reason: 'the write itself must still happen');
      expect(
        fakeClient('nas').fetchItemCalls,
        contains('dune-nas'),
        reason:
            'onChanged must ask DiscoverProvider to refresh this exact item — '
            'refreshContinueWatching() never refetches hubs, so without this '
            'call nothing on this row ever asks the server again',
      );
      expect(
        rows(tester).single.hub.groups.single.watchState.isWatched,
        isTrue,
        reason: 'the card the user pressed menu on must show the mark it just made, not a stale badge',
      );
    });
  });
  group('HOME1 / DEC-095: the hero is full-bleed and the first rail peeks under it', () {
    Future<void> bootHome(WidgetTester tester) => boot(
      tester,
      latestMovies: twoRecentFilms(),
      hubs: [
        _hub('top-picks', 'Top Picks', [_film('tp1', title: 'Quarry Road'), _film('tp2', title: 'Arcade Midnight')]),
        _hub('hidden-gems', 'Hidden Gems', [_film('hg1', title: 'Wintering'), _film('hg2', title: 'Salt Flats')]),
        _hub('for-you', 'For You', [_film('fy1', title: 'Longline'), _film('fy2', title: 'Nightjar')]),
      ],
    );

    Rect feedRect(WidgetTester tester) => tester.getRect(find.byType(TvContentFeed));
    Rect headerRect(WidgetTester tester, String title) => tester.getRect(find.widgetWithText(TvSectionHeader, title));

    testWidgets('the billboard spans the feed edge to edge and at least its full height', (tester) async {
      await bootHome(tester);
      final feed = feedRect(tester);
      final card = tester.getRect(find.byType(TvHeroBillboardCard));
      expect(card.left, feed.left, reason: '9.2: the backdrop is full-bleed, no page inset on the left');
      expect(card.width, feed.width, reason: '9.2: the backdrop is full-bleed, no page inset on the right');
      expect(card.height, greaterThanOrEqualTo(feed.height), reason: '9.2: the backdrop covers the whole content box');
    });

    testWidgets('the landing shows the first rail label with its band only partly in view', (tester) async {
      await bootHome(tester);
      final feed = feedRect(tester);
      final header = tester.getRect(find.byType(TvSectionHeader).first);
      expect(header.bottom, lessThan(feed.bottom), reason: 'the label of the first rail is on screen');
      final tile = tester.getRect(find.byType(TvExpandableMediaTile).first);
      expect(tile.top, lessThan(feed.bottom), reason: 'the posters peek above the bottom edge');
      expect(tile.bottom, greaterThan(feed.bottom), reason: 'A1: the first rail is not fully in view on the landing');
    });

    testWidgets('DOWN out of the hero puts the first rail label under the top navigation', (tester) async {
      await bootHome(tester);
      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      final feed = feedRect(tester);
      // bootHome seeds no on-deck items, so the first row is Recently Released.
      final header = headerRect(tester, t.discover.recentlyReleased);
      expect(
        header.top - feed.top,
        closeTo(0, 1.0),
        reason: 'DEC-095 (3): no band is held open for the hero — the focused rail sits at the top',
      );
    });

    testWidgets('a focused row steps the backdrop back with a veil that stays fixed to the screen', (tester) async {
      await bootHome(tester);
      expect(tester.widget<TvHeroDimVeil>(find.byType(TvHeroDimVeil)).dim, 0, reason: 'nothing dims the landing');
      heroNode(tester, 'tvHeroPlay').requestFocus();
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(tester.widget<TvHeroDimVeil>(find.byType(TvHeroDimVeil)).dim, 1, reason: 'mockup 30 B: row focus dims');
      final feed = feedRect(tester);
      final veil = tester.getRect(find.byType(TvHeroDimVeil));
      expect(veil.top, feed.top, reason: 'the veil is screen-fixed while the picture scrolls under it');
      expect(veil.bottom, feed.bottom);
      final card = tester.getRect(find.byType(TvHeroBillboardCard));
      expect(card.top, lessThan(feed.top), reason: 'the picture itself did scroll with the list');
    });

    testWidgets('a rail deeper on the page anchors the same way, by the same rule', (tester) async {
      await bootHome(tester);
      final second = rows(tester)[2];
      tileNode(tester, second.hub.groups.first.groupId).requestFocus();
      await tester.pumpAndSettle();
      final feed = feedRect(tester);
      final header = headerRect(tester, second.hub.title);
      expect(
        header.top - feed.top,
        closeTo(0, 1.0),
        reason: 'DEC-095 (4): one anchor for every row, so the rail below the focused one is wholly on screen',
      );
    });
  });
}
