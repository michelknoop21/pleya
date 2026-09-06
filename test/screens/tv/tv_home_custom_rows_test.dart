/// ROW1 / [DEC-100](../../../docs/DECISIONS.md#dec-100): a Home row the viewer
/// defined themselves, out of a saved filter.
///
/// This file is the negative control the decision asked for, and it was
/// written before any of the production code existed: a `TvContentFeed` fed a
/// profile that already has one saved row must draw that row between the fixed
/// rows and the backend hubs, with Verder kijken still first and the billboard
/// untouched. On the code as it stood it failed on the assertion — the feed
/// drew Verder kijken, Recent uitgebracht and the hub, and nothing else — not
/// on a missing symbol.
///
/// The setup is deliberately storage-level. A saved row is a *preference*, and
/// the case worth proving is a profile that already had one before this
/// process started, so the fixture writes what an earlier session would have
/// left behind and lets the provider read it back. That also kept the
/// assertions stable across the build: the only line that changed after the
/// feature landed was the provider registration in [boot], never an
/// expectation.
///
/// What the merge does here is real. The fake client answers
/// `fetchLibraryPagedContent` the way a backend does, so the row's content
/// comes out of the same k-way merge and identity pipeline as the catalog's
/// own — a row filled from a hand-built list of groups would prove the layout
/// and nothing about the filter.
library;

import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/home_custom_rows_provider.dart';
import 'package:pleya/providers/home_layout_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/tv_home_projection_provider.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/unified_catalog/home_custom_row.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_content_feed.dart';
import 'package:pleya/widgets/tv/tv_content_row.dart';
import 'package:pleya/widgets/tv/tv_home_customize_footer.dart';
import 'package:pleya/widgets/tv/tv_home_customize_panel.dart';
import 'package:pleya/widgets/tv/tv_home_row_wizard.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

MediaItem _film(String id, {required String title, String genre = 'Science fiction', bool watched = false}) =>
    MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: title,
      year: 2024,
      genres: [genre],
      viewCount: watched ? 1 : 0,
      durationMs: 100 * 60 * 1000,
      serverId: 'nas',
      serverName: 'NAS',
      summary: '$title has enough prose for the rail context block.',
    );

MediaItem _episode(String id, {required String show}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode 1',
  grandparentTitle: show,
  grandparentId: 'show-$show',
  parentIndex: 1,
  index: 1,
  durationMs: 45 * 60 * 1000,
  viewOffsetMs: 10 * 60 * 1000,
  serverId: 'nas',
  serverName: 'NAS',
);

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

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: onDeck, succeededServerIds: const {'nas'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubs, succeededServerIds: const {'nas'});

  @override
  Future<OnDeckAggregationResult> getLatestMoviesFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: latestMovies, succeededServerIds: const {'nas'});
}

/// A backend that pages one library and honours the two item predicates the
/// saved filter can carry, so "the row shows what the filter asked for" is a
/// statement about the merge and not about the fixture.
class _FakeClient implements MediaServerClient {
  _FakeClient(this.catalog);

  final List<MediaItem> catalog;

  /// Every query the merge sent, so a test can prove the saved sort and the
  /// saved genre reached the wire rather than being applied afterwards.
  final List<LibraryQuery> queries = [];

  @override
  final ServerId serverId = ServerId('nas');

  @override
  String? get serverName => 'NAS';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    queries.add(query);
    final genres = query.genres;
    var items = catalog.where((item) {
      if (genres != null && genres.isNotEmpty && !genres.any((g) => item.genres?.contains(g) ?? false)) return false;
      if (query.includeWatched == false && (item.viewCount ?? 0) > 0) return false;
      return true;
    }).toList();
    items.sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
    if (query.sort?.direction == LibrarySortDirection.descending) items = items.reversed.toList();
    final page = items.skip(query.offset).take(query.limit).toList();
    return LibraryPage(items: page, totalCount: items.length, offset: query.offset);
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

  late HomeLayoutProvider layout;
  late _FakeClient client;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;

  /// The saved row an earlier session left behind, in the shape
  /// `HomeCustomRow.toJson` writes.
  String savedRowJson({
    String id = 'r1',
    String name = 'Nieuwe sci-fi',
    String kind = 'movie',
    Map<String, dynamic> query = const {
      'sort': 'titleAsc',
      'genres': ['Science fiction'],
      'watch': 'unwatched',
    },
  }) => jsonEncode({'id': id, 'kind': kind, 'name': name, 'query': query});

  Future<void> boot(WidgetTester tester, {List<String> savedRows = const [], List<MediaItem>? catalog}) async {
    // StorageService stores a string list as one JSON string, so the fixture
    // writes exactly what an earlier session would have left in that key.
    resetSharedPreferencesForTest(initialAsync: {if (savedRows.isNotEmpty) 'home_custom_rows': jsonEncode(savedRows)});
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);

    final manager = MultiServerManager();
    client = _FakeClient(
      catalog ??
          [
            _film('m1', title: 'Dune'),
            _film('m2', title: 'Arrival'),
            _film('m3', title: 'Solaris'),
            _film('m4', title: 'Seen It', watched: true),
            _film('m5', title: 'Casablanca', genre: 'Drama'),
          ],
    );
    manager.debugRegisterClientForTesting(client);

    final aggregation = _FakeAggregation(manager)
      ..onDeck = [_episode('e1', show: 'Severance')]
      ..latestMovies = [_film('m1', title: 'Dune')]
      ..hubs = [
        _hub('movie.recentlyadded', 'Recently Added', [_film('m5', title: 'Casablanca', genre: 'Drama')]),
      ];
    final multiServer = MultiServerProvider(manager, aggregation);
    hiddenLibraries = HiddenLibrariesProvider();
    libraries = LibrariesProvider()
      ..debugSetLibraries(const [
        MediaLibrary(
          id: 'films',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'NAS',
        ),
      ]);
    final discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
    addTearDown(discover.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    await discover.load();
    final projection = TvHomeProjectionProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: t.discover.continueWatching,
      latestMoviesTitle: t.discover.recentlyReleased,
    );
    addTearDown(projection.dispose);
    for (var i = 0; i < 80 && projection.isProjecting; i++) {
      await Future<void>.value();
    }

    layout = HomeLayoutProvider();
    addTearDown(layout.dispose);
    await layout.ensureInitialized();
    // The one line this file gained after the feature landed. Every assertion
    // below is the one that was red.
    final customRows = HomeCustomRowsProvider(
      layout: layout,
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
    );
    addTearDown(customRows.dispose);

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
          ChangeNotifierProvider<HomeLayoutProvider>.value(value: layout),
          ChangeNotifierProvider<HomeCustomRowsProvider>.value(value: customRows),
          ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
          ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hiddenLibraries),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(child: const Scaffold(body: TvContentFeed())),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  List<String> rowTitles(WidgetTester tester) =>
      tester.widgetList<TvContentRow>(find.byType(TvContentRow)).map((r) => r.hub.title).toList();

  List<String> cardTitles(WidgetTester tester, String rowTitle) => tester
      .widgetList<TvContentRow>(find.byType(TvContentRow))
      .firstWhere((r) => r.hub.title == rowTitle)
      .hub
      .groups
      .map((g) => g.representativeSource.item.title ?? '')
      .toList();

  FocusNode nodeLabelled(WidgetTester tester, String label) => tester
      .widgetList<Focus>(find.byType(Focus))
      .map((f) => f.focusNode)
      .whereType<FocusNode>()
      .firstWhere((n) => n.debugLabel == label);

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(key);
    await tester.sendKeyUpEvent(key);
    await tester.pump();
    await tester.pump();
  }

  /// Focuses [label]'s control and presses Select on it. `tester.tap` does
  /// nothing on a `FocusableWrapper`, which carries no tap handler.
  Future<void> activateByLabel(WidgetTester tester, String label) async {
    final focus = Focus.maybeOf(tester.element(find.text(label).first), scopeOk: true)!;
    focus.requestFocus();
    await tester.pump();
    SelectKeyUpSuppressor.clearSuppression();
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  Future<void> openPanel(WidgetTester tester) async {
    nodeLabelled(tester, 'tvHomeCustomizeFooter').requestFocus();
    await tester.pump();
    SelectKeyUpSuppressor.clearSuppression();
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  testWidgets('a saved row is drawn between the fixed rows and the backend hubs', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);

    expect(rowTitles(tester), [
      t.discover.continueWatching,
      'Nieuwe sci-fi',
      t.discover.recentlyReleased,
      'Recently Added',
    ]);
  });

  testWidgets('the saved filter decides the row content', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);

    // Casablanca is a drama and Seen It is watched, so the genre and the watch
    // filter each have to have excluded one title for this to hold.
    expect(cardTitles(tester, 'Nieuwe sci-fi'), ['Arrival', 'Dune', 'Solaris']);
    expect(client.queries.first.genres, ['Science fiction']);
    expect(client.queries.first.includeWatched, isFalse);
  });

  testWidgets('a profile with no saved rows draws the Home it always drew', (tester) async {
    await boot(tester);

    expect(rowTitles(tester), [t.discover.continueWatching, t.discover.recentlyReleased, 'Recently Added']);
  });

  testWidgets('the footer is the last stop on Home and DOWN off the last row reaches it', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);

    expect(find.byKey(tvHomeCustomizeFooterKey), findsOneWidget);

    // Down out of the bottom row rather than focusing the footer directly:
    // A1a's whole claim is that it is one DOWN away with no sideways aiming.
    final rows = tester.widgetList<TvContentRow>(find.byType(TvContentRow)).toList();
    final lastRail = rows.last.railKey.currentState!;
    expect(lastRail.focusCurrent(), isTrue, reason: 'the bottom row has to be able to hold the ring first');
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();

    expect(nodeLabelled(tester, 'tvHomeCustomizeFooter').hasPrimaryFocus, isTrue);
  });

  testWidgets('the panel draws the fixed rows locked and every other row movable', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await openPanel(tester);

    expect(find.byKey(tvHomeCustomizePanelKey), findsOneWidget);
    // Uitgelicht and Verder kijken, with the word that says why they have no
    // buttons. Recent uitgebracht is deliberately not among them (DEC-100 (4)).
    expect(find.text(t.unifiedCatalog.homeRows.featured), findsOneWidget);
    expect(find.text(t.unifiedCatalog.homeRows.alwaysFirst), findsOneWidget);
    expect(find.text(t.unifiedCatalog.homeRows.alwaysSecond), findsOneWidget);
    expect(find.text(t.unifiedCatalog.homeRows.fixed), findsNWidgets(2));

    // An own row offers Edit and Remove; a backend row offers Hide.
    expect(find.text(t.unifiedCatalog.homeRows.edit), findsOneWidget);
    expect(find.text(t.unifiedCatalog.homeRows.remove), findsOneWidget);
    expect(find.text(t.unifiedCatalog.homeRows.hide), findsNWidgets(2));
    expect(find.text(t.unifiedCatalog.homeRows.newRow), findsOneWidget);
  });

  // ROW1e. The panel's grid is the whole navigation: every column steps to the
  // same column one row on, and `_step` clamps to what the target row has. Two
  // of the four columns never got asked, because `TvPanelButton` had no
  // `onNavigateDown` to bind, so DOWN off Verbergen, Bewerken or Verwijderen
  // fell through to Flutter's geometric traversal, which is what the doc
  // comment on these tiles says the grid exists to prevent.
  testWidgets('DOWN off the primary action steps to the next row, not to geometry', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await openPanel(tester);

    nodeLabelled(tester, 'TvHomeCustomize.#custom:r1#primary').requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(nodeLabelled(tester, 'TvHomeCustomize.:pleya:home:latest-movies#primary').hasPrimaryFocus, isTrue);
  });

  testWidgets('DOWN off Verwijderen clamps to the column the next row has', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await openPanel(tester);

    // Only an own row carries Verwijderen, so the row below has no such column
    // and `_step` falls back to its last one.
    nodeLabelled(tester, 'TvHomeCustomize.#custom:r1#remove').requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(nodeLabelled(tester, 'TvHomeCustomize.:pleya:home:latest-movies#primary').hasPrimaryFocus, isTrue);
  });

  testWidgets('RIGHT off the primary action of a row without Verwijderen goes nowhere', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await openPanel(tester);

    // Verbergen is the last control on a backend row. Without a stop there,
    // RIGHT walks into the next row's first button.
    final hide = nodeLabelled(tester, 'TvHomeCustomize.:pleya:home:latest-movies#primary');
    hide.requestFocus();
    await tester.pump();
    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(hide.hasPrimaryFocus, isTrue);
  });

  testWidgets('moving a row down writes the order and Home follows it', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await openPanel(tester);

    // The own row is first in the panel, so its "move down" is the first one.
    final down = tester
        .widgetList<Focus>(find.byType(Focus))
        .map((f) => f.focusNode)
        .whereType<FocusNode>()
        .firstWhere((n) => n.debugLabel == 'TvHomeCustomize.#custom:r1#down');
    down.requestFocus();
    await tester.pump();
    SelectKeyUpSuppressor.clearSuppression();
    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(layout.order.first, ':pleya:home:latest-movies');
    expect(layout.order[1], '#custom:r1');

    // Closing the panel puts the rows on Home in the order the panel wrote.
    await activateByLabel(tester, t.unifiedCatalog.homeRows.done);
    expect(rowTitles(tester), [
      t.discover.continueWatching,
      t.discover.recentlyReleased,
      'Nieuwe sci-fi',
      'Recently Added',
    ]);
  });

  // ROW1g. The shipped string says a new row "lands directly under Continue
  // Watching", and DEC-100 (5) asks for the same. It did, right up until the
  // viewer moved anything: `move` writes every id into the order, and
  // `applyHomeLayoutToUnifiedRows` ranks an id the order has never seen as
  // `order.length`, which is last.
  testWidgets('a new row lands under Verder kijken even when an order was saved', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await layout.setOrder([':pleya:home:latest-movies', '#custom:r1']);
    await tester.pumpAndSettle();

    await layout.saveCustomRow(
      const HomeCustomRow(
        id: 'r2',
        kind: MediaKind.movie,
        name: 'Net binnen',
        preferences: UnifiedCatalogPreferences.defaults,
      ),
    );
    await tester.pumpAndSettle();

    expect(rowTitles(tester).take(2), [t.discover.continueWatching, 'Net binnen']);
  });

  testWidgets('editing a row leaves it where the viewer put it', (tester) async {
    await boot(
      tester,
      savedRows: [
        savedRowJson(),
        savedRowJson(id: 'r2', name: 'Net binnen'),
      ],
    );
    await layout.setOrder([':pleya:home:latest-movies', '#custom:r2', '#custom:r1']);
    await tester.pumpAndSettle();

    // Same id, new name: a rename is not a new row and must not jump the queue.
    await layout.saveCustomRow(
      const HomeCustomRow(
        id: 'r2',
        kind: MediaKind.movie,
        name: 'Andere naam',
        preferences: UnifiedCatalogPreferences.defaults,
      ),
    );
    await tester.pumpAndSettle();

    expect(layout.order.first, ':pleya:home:latest-movies');
    expect(layout.order.indexOf('#custom:r2'), 1);
  });

  testWidgets('hiding a backend row takes it off Home and leaves it in the panel', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await openPanel(tester);

    await activateByLabel(tester, t.unifiedCatalog.homeRows.hide);
    await tester.pumpAndSettle();

    // Still listed, now with the button that brings it back.
    expect(find.text(t.unifiedCatalog.homeRows.show), findsOneWidget);

    await activateByLabel(tester, t.unifiedCatalog.homeRows.done);
    expect(rowTitles(tester), [t.discover.continueWatching, 'Nieuwe sci-fi', 'Recently Added']);
  });

  testWidgets('removing an own row takes its stored layout entries with it', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);
    await layout.setOrder(['#custom:r1', ':pleya:home:latest-movies']);
    await layout.setRowHidden('#custom:r1', true);
    await tester.pumpAndSettle();

    await layout.removeCustomRow('r1');

    expect(layout.customRows, isEmpty);
    expect(layout.order, isNot(contains('#custom:r1')), reason: 'an order entry nothing can reach is invisible state');
    expect(layout.hiddenRowIds, isNot(contains('#custom:r1')));
  });

  // ROW1f. The wizard opened with the ring on Annuleren, one Select from
  // closing itself. `_footer(scale)` is built eagerly into the Column's
  // children while the step body sits in a `LayoutBuilder` that only runs
  // during layout, so `_nodeFor('footer.back')` was the first call and the
  // "first one wins" rule handed it the initial-focus node.
  testWidgets('the wizard opens on the step, not on Annuleren', (tester) async {
    await boot(tester);
    await openPanel(tester);
    await activateByLabel(tester, t.unifiedCatalog.homeRows.newRow);
    await tester.pumpAndSettle();

    // The adopted node keeps the host's own debugLabel, so this asks the tree
    // which control holds the ring rather than asking for a name.
    Focus focusOf(String label) => tester.widget<Focus>(
      find
          .ancestor(
            of: find.descendant(of: find.byKey(tvHomeRowWizardKey), matching: find.text(label)),
            matching: find.byType(Focus),
          )
          .first,
    );

    expect(focusOf(t.unifiedCatalog.moviesTitle).focusNode!.hasPrimaryFocus, isTrue);
    expect(
      focusOf(t.common.cancel).focusNode!.hasPrimaryFocus,
      isFalse,
      reason: 'one Select on Annuleren throws the whole wizard away',
    );
  });

  testWidgets('the new-row flow saves a row and Home draws it', (tester) async {
    await boot(tester);
    await openPanel(tester);

    await activateByLabel(tester, t.unifiedCatalog.homeRows.newRow);
    expect(find.byKey(tvHomeRowWizardKey), findsOneWidget);
    expect(find.text(t.unifiedCatalog.homeRows.stepName), findsWidgets);

    await activateByLabel(tester, t.unifiedCatalog.homeRows.next);
    expect(find.text(t.unifiedCatalog.homeRows.sorting), findsOneWidget);

    await activateByLabel(tester, t.unifiedCatalog.homeRows.next);
    await tester.pumpAndSettle();
    // The preview is the row's own question, so the count is the merge's and
    // not a promise: five films in the fixture, every library exhausted.
    // One Text carries count, kind, filters and sort on one line (mockup C3),
    // so this reads the line rather than a widget of its own.
    expect(find.textContaining(t.unifiedCatalog.titleCount(count: 5)), findsOneWidget);

    await activateByLabel(tester, t.unifiedCatalog.homeRows.addRow);
    await tester.pumpAndSettle();

    // Adding closes both the wizard and the panel (DEC-100 (5)), and the row is
    // on Home under the label its filter gives it.
    expect(find.byKey(tvHomeRowWizardKey), findsNothing);
    expect(find.byKey(tvHomeCustomizePanelKey), findsNothing);
    expect(layout.customRows, hasLength(1));
    expect(rowTitles(tester), [
      t.discover.continueWatching,
      t.unifiedCatalog.discovery.allMovies,
      t.discover.recentlyReleased,
      'Recently Added',
    ]);
  });

  testWidgets('the context menu on a Home card carries the same entry', (tester) async {
    await boot(tester, savedRows: [savedRowJson()]);

    final tile = tester
        .widgetList<Focus>(find.byType(Focus))
        .map((f) => f.focusNode)
        .whereType<FocusNode>()
        .firstWhere((n) => n.debugLabel?.startsWith('tvDiscoveryTile_') ?? false);
    tile.requestFocus();
    await tester.pump();
    SelectKeyUpSuppressor.clearSuppression();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.pump(const Duration(milliseconds: 600));
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    // By key, not by label: the footer behind the menu carries the same words,
    // which is the point of A1a and A1b being one entry in two places.
    final extra = find.byKey(const ValueKey('tvContextMenuExtraAction'));
    expect(extra, findsOneWidget);
    expect(find.descendant(of: extra, matching: find.text(t.unifiedCatalog.homeRows.customize)), findsOneWidget);

    // From the label inside the row, not from the row: `Focus.maybeOf` walks
    // up, and the row's own focus node lives below it.
    final focus = Focus.maybeOf(
      tester.element(find.descendant(of: extra, matching: find.text(t.unifiedCatalog.homeRows.customize))),
      scopeOk: true,
    )!;
    focus.requestFocus();
    await tester.pump();
    SelectKeyUpSuppressor.clearSuppression();
    await press(tester, LogicalKeyboardKey.select);
    // Twice: the menu's own close animation has to finish before the entry's
    // callback runs, which is deliberate — see `showTvUnifiedContextMenu`.
    await tester.pumpAndSettle();
    await tester.pumpAndSettle();

    expect(find.byKey(tvHomeCustomizePanelKey), findsOneWidget);
  });
}
