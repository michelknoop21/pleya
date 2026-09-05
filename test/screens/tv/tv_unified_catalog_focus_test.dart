/// Remote reachability for the Films/Series catalog controls (hoofdstuk 7.4 of
/// docs/tvos-unified-experience.md as CAT5 rewrote it), and the page heading
/// DEC-068 made load-bearing.
///
/// ## Why this file exists next to the goldens
///
/// `tv_unified_catalog_golden_test.dart` pictures the header, and
/// `tv_unified_catalog_states_golden_test.dart` pictures the four content
/// states. Neither proves the header can be *operated*: the first composes its
/// own `_page()` stand-in with three throwaway `FocusNode`s and no navigation
/// callbacks at all, and the second only pumps the real screen for states whose
/// body has no grid to traverse out of. So the one path a viewer on a sofa
/// depends on — grid → controls → grid, and out to the sidebar — was wired
/// correctly in `tv_unified_catalog_screen.dart` and covered by nothing.
///
/// That is the gap this file closes, and it closes it against the real
/// `TvMoviesScreen`/`TvSeriesScreen`, not a reconstruction: the wrapper is what
/// chooses the heading, and the shared screen is what owns `_openRail`,
/// `_closeRail`, `_focusGrid` and the per-row `onNavigate*` callbacks.
/// Reconstructing either would prove the reconstruction.
///
/// Focus assertions read `FocusManager.instance.primaryFocus?.debugLabel`,
/// which is the production node's own label (`TvCatalogRailSources`,
/// `TvCatalogRailFilters`, `TvCatalogRailSort`, `TvUnifiedCard(<groupId>)`)
/// rather than a test-side handle — so a rename in the screen surfaces here as
/// a failure instead of a silent pass against a stale assumption.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/tv/tv_movies_screen.dart';
import 'package:pleya/screens/tv/tv_series_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// One library that answers immediately, so the grid has real cards to focus.
///
/// Twelve items rather than a handful: the traversal under test only means
/// something when the first row is a *row* (six columns at the golden surface
/// width) with more underneath it, so that UP from the top row is the header
/// exit and not simply "the only card there is".
class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, {required this.items});

  final String id;
  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

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
    final end = (query.offset + query.limit).clamp(0, items.length);
    final slice = query.offset >= items.length ? const <MediaItem>[] : items.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: items.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String id, {required String title, required MediaKind kind}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: kind, title: title, serverId: 'nas');

/// Everything the real screen needs behind it, torn down together.
class _Harness {
  _Harness(MediaKind kind)
    : client = _FakeLibraryClient(
        'nas',
        items: [
          for (var i = 0; i < 12; i++)
            _item('i$i', title: kind == MediaKind.movie ? 'Film $i' : 'Serie $i', kind: kind),
        ],
      ) {
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: kind == MediaKind.movie ? 'Films 4K' : 'Series 4K',
          kind: kind,
          serverId: 'nas',
          serverName: 'NAS',
        ),
      ]);
    hiddenLibraries = HiddenLibrariesProvider();
    catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);
  }

  final _FakeLibraryClient client;
  late final MultiServerManager manager;
  late final MultiServerProvider multiServer;
  late final LibrariesProvider libraries;
  late final HiddenLibrariesProvider hiddenLibraries;
  late final UnifiedCatalogs catalogs;

  /// Set by the shell whenever the screen asks the root shell for the sidebar,
  /// which is the only observable end of `_focusSidebar` outside `MainScreen`.
  int sidebarFocusCalls = 0;

  void dispose() {
    catalogs.dispose();
    hiddenLibraries.dispose();
    libraries.dispose();
    multiServer.dispose();
  }
}

void main() {
  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  setUp(() async {
    // The screen reads `UnifiedCatalogQueryStore` before its first fetch;
    // leaving it on whatever a previous test wrote would make the traversal
    // depend on execution order (a stored source restriction changes which
    // libraries participate, and an empty grid has nothing to traverse).
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  /// Pumps the real wrapper — `TvMoviesScreen` or `TvSeriesScreen` — inside the
  /// providers the profile subtree gives it, on the TV surface size.
  Future<_Harness> pump(WidgetTester tester, {required MediaKind kind}) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = _Harness(kind);
    addTearDown(harness.dispose);

    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: harness.multiServer),
            Provider<UnifiedCatalogs>.value(value: harness.catalogs),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: MainScreenFocusScope(
                focusSidebar: () => harness.sidebarFocusCalls++,
                focusContent: () {},
                isSidebarFocused: false,
                sideNavigationWidth: 0,
                child: Scaffold(body: kind == MediaKind.movie ? const TvMoviesScreen() : const TvSeriesScreen()),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return harness;
  }

  String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  /// Puts focus on the first card the way the header's DOWN exit does, so a
  /// test about leaving the grid starts from the state the screen itself
  /// produces rather than from a hand-placed focus.
  void focusGrid(WidgetTester tester) =>
      tester.state<TvUnifiedMediaGridState>(find.byType(TvUnifiedMediaGrid)).focusGrid();

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pump();
  }

  // ---------------------------------------------------------------------------
  // The heading (DEC-068 / hoofdstuk 33.5)
  // ---------------------------------------------------------------------------

  testWidgets('the complete catalog is headed "All movies", not the landing\'s "Movies"', (tester) async {
    await pump(tester, kind: MediaKind.movie);

    expect(find.text(t.unifiedCatalog.discovery.allMovies), findsOneWidget);
    // The whole point of DEC-068: the two levels must not share a heading, or
    // pressing "All movies ›" on the landing lands on a page still called
    // "Movies" and the viewer cannot tell which level they are on.
    expect(t.unifiedCatalog.discovery.allMovies, isNot(t.unifiedCatalog.moviesTitle));
    expect(find.text(t.unifiedCatalog.moviesTitle), findsNothing);
  });

  testWidgets('the complete series catalog is headed "All series", not "Series"', (tester) async {
    await pump(tester, kind: MediaKind.show);

    expect(find.text(t.unifiedCatalog.discovery.allSeries), findsOneWidget);
    expect(t.unifiedCatalog.discovery.allSeries, isNot(t.unifiedCatalog.seriesTitle));
    expect(find.text(t.unifiedCatalog.seriesTitle), findsNothing);
  });

  // ---------------------------------------------------------------------------
  // Grid → header (hoofdstuk 7.4, and 7.6's default slot)
  // ---------------------------------------------------------------------------
  // Grid → rail → grid (CAT5 / DEC-093)
  //
  // The three requirements DEC-093 states, and the column arithmetic, live in
  // `tv_catalog_filter_rail_test.dart`. What is proven here is the part that
  // has to hold for *every* row rather than for the one the rail opens on: no
  // row is a dead end, and none of them reaches for the bar by accident.
  // ---------------------------------------------------------------------------

  /// Opens the rail from the first card and walks down to [row].
  Future<void> openRailAt(WidgetTester tester, String row) async {
    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
    const order = ['TvCatalogRailSources', 'TvCatalogRailFilters', 'TvCatalogRailSort'];
    for (var i = 0; i < order.indexOf(row); i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
    }
    expect(focusedLabel(), row);
  }

  testWidgets('RIGHT from every rail row returns to the grid', (tester) async {
    await pump(tester, kind: MediaKind.movie);

    for (final row in ['TvCatalogRailSources', 'TvCatalogRailFilters', 'TvCatalogRailSort']) {
      await openRailAt(tester, row);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(focusedLabel(), startsWith('TvUnifiedCard('), reason: 'RIGHT from $row should return to the grid');
    }
  });

  testWidgets('LEFT from every rail row reaches for the top navigation, and takes the rail down with it', (
    tester,
  ) async {
    final harness = await pump(tester, kind: MediaKind.movie);

    var expectedCalls = 0;
    for (final row in ['TvCatalogRailSources', 'TvCatalogRailFilters', 'TvCatalogRailSort']) {
      await openRailAt(tester, row);
      expect(harness.sidebarFocusCalls, expectedCalls, reason: 'walking within the rail must not reach for the bar');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(++expectedCalls, harness.sidebarFocusCalls, reason: 'LEFT from $row should ask for the bar');
      // The screen asks; it does not move the ring itself. Moving focus here
      // too would race the shell and leave the ring somewhere neither owns.
      // The rail does close, because a rail standing open with the focus
      // elsewhere costs the grid a column for nothing the viewer can see.
      expect(find.byKey(tvCatalogFilterRailKey), findsNothing);
    }
  });

  testWidgets('DOWN off the last rail row is an edge, not a wrap', (tester) async {
    await pump(tester, kind: MediaKind.movie);

    // Nothing is filtered, so there is no Wissen row under Sortering.
    await openRailAt(tester, 'TvCatalogRailSort');
    await press(tester, LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'TvCatalogRailSort');
  });
}
