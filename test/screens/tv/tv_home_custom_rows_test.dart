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
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_content_feed.dart';
import 'package:pleya/widgets/tv/tv_content_row.dart';
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
    final hiddenLibraries = HiddenLibrariesProvider();
    final libraries = LibrariesProvider()
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
}
