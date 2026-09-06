/// CAT5: the catalog's controls live in a collapsible rail left of the grid
/// (DEC-093, mockup 28 D1/D2), not in a cluster right of the page heading.
///
/// ## The negative control DEC-093 asks for
///
/// "Een widgettest die Alle films pompt met de focus op kolom 0 en eist dat
/// LEFT de rail opent met de focus op Bronnen, dat RIGHT hem sluit met de focus
/// terug op dezelfde kaart, en dat de kop geen focusbare actie meer draagt."
/// Those are the first three tests below, and on the pre-CAT5 code all three
/// are red: LEFT off column 0 handed focus to the shell, RIGHT did nothing, and
/// the heading carried three focusable capsules.
///
/// It drives the real `TvMoviesScreen` (the wrapper that names the page) over
/// the real `TvUnifiedCatalogScreen`, `TvCatalogFilterRail` and
/// `TvUnifiedMediaGrid`, for the reason `tv_unified_catalog_focus_test.dart`
/// gives: a reconstruction of the traversal would only prove the
/// reconstruction. Focus assertions read the production nodes' own
/// `debugLabel`s.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
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
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_unified_media_card.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// One library that answers immediately, with enough titles that the first row
/// is a row at both column counts the rail switches between.
class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, {required this.items, this.alwaysFails = false});

  final String id;

  /// Mutable, so a test can take the catalog's content away underneath an open
  /// rail and reach the state that has no grid *and* nothing for the focus
  /// scope to fall back on.
  List<MediaItem> items;

  /// Every page fetch throws, which is how the page reaches the state that has
  /// a Retry and no grid at all (CAT6).
  final bool alwaysFails;

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
    if (alwaysFails) throw StateError('library unavailable');
    final end = (query.offset + query.limit).clamp(0, items.length);
    final slice = query.offset >= items.length ? const <MediaItem>[] : items.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: items.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _item(String id, {required String title}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: 'nas');

class _Harness {
  _Harness({bool failing = false}) {
    client = _FakeLibraryClient(
      'nas',
      items: [for (var i = 0; i < 18; i++) _item('i$i', title: 'Film $i')],
      alwaysFails: failing,
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films 4K',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'NAS',
        ),
      ]);
    hiddenLibraries = HiddenLibrariesProvider();
    catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);
  }

  late final _FakeLibraryClient client;
  late final MultiServerManager manager;
  late final MultiServerProvider multiServer;
  late final LibrariesProvider libraries;
  late final HiddenLibrariesProvider hiddenLibraries;
  late final UnifiedCatalogs catalogs;

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
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    await StorageService.getInstance();
  });

  Future<_Harness> pump(WidgetTester tester, {Size surfaceSize = const Size(1280, 720), bool failing = false}) async {
    tester.view.physicalSize = surfaceSize;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final harness = _Harness(failing: failing);
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
                child: const Scaffold(body: TvMoviesScreen()),
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

  /// The Retry button's own node, asked of the tree: it is built with an
  /// internal node, so there is no name to look it up by.
  FocusNode retryFocus(WidgetTester tester) =>
      Focus.maybeOf(tester.element(find.text(t.common.retry).first), scopeOk: true)!;

  void focusGrid(WidgetTester tester) =>
      tester.state<TvUnifiedMediaGridState>(find.byType(TvUnifiedMediaGrid)).focusGrid();

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// How many cards the top row holds, read off the rendered card rects rather
  /// than off the column resolver, because the point is what the viewer sees.
  int renderedColumns(WidgetTester tester) {
    final rects = tester
        .widgetList<TvUnifiedMediaCard>(find.byType(TvUnifiedMediaCard))
        .map((card) => tester.getTopLeft(find.byWidget(card)).dy)
        .toList();
    if (rects.isEmpty) return 0;
    final firstRowTop = rects.first;
    return rects.where((dy) => (dy - firstRowTop).abs() < 0.5).length;
  }

  // ---------------------------------------------------------------------------
  // DEC-093's three requirements
  // ---------------------------------------------------------------------------

  testWidgets('CAT5: LEFT from column 0 opens the rail with the focus on Bronnen', (tester) async {
    await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    expect(focusedLabel(), startsWith('TvUnifiedCard('), reason: 'sanity: the remote starts on a card');
    expect(find.byKey(tvCatalogFilterRailKey), findsNothing, reason: 'the rail starts collapsed');

    await press(tester, LogicalKeyboardKey.arrowLeft);

    expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget, reason: 'LEFT off column 0 opens the rail');
    expect(focusedLabel(), 'TvCatalogRailSources', reason: 'the rail opens with the focus on Bronnen');
  });

  testWidgets('CAT5: RIGHT closes the rail and the focus returns to the same card', (tester) async {
    await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    // One row down, so "the same card" is not the card `focusGrid`'s own
    // fallback would land on anyway, and still column 0, where LEFT opens the
    // rail. It is also the card whose column changes when the grid re-columns
    // from six to five underneath the open rail.
    await press(tester, LogicalKeyboardKey.arrowDown);
    final card = focusedLabel();
    expect(card, startsWith('TvUnifiedCard('));

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), 'TvCatalogRailSources');

    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(find.byKey(tvCatalogFilterRailKey), findsNothing, reason: 'RIGHT collapses the rail again');
    expect(focusedLabel(), card, reason: 'the focus returns to the card the rail was opened from');
  });

  // CAT6, and what these two pin is that it does *not* happen. `_closeRail`
  // hands the ring to the grid, and the three states that have no grid never
  // built one, so that request really is a silent no-op there — the review that
  // read the code was right about the mechanism. The outcome is still correct,
  // twice over: the empty state autofocuses its own action when it replaces the
  // grid, and the focus scope restores the child it had before the rail opened.
  // These tests exist because both of those are somebody else's behaviour. Take
  // the autofocus off the empty state, or change how the scope recovers, and
  // the ring lands nowhere with nothing in `_closeRail` to catch it.
  testWidgets('CAT6: the grid disappearing under an open rail does not leave the ring in it', (tester) async {
    final harness = await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), 'TvCatalogRailSources');

    // The card the scope would otherwise fall back on is gone by the time the
    // rail closes, so nothing implicit can rescue the ring here.
    harness.client.items = const [];
    await harness.catalogs.movies.refresh();
    await tester.pumpAndSettle();
    expect(find.byType(TvUnifiedMediaGrid), findsNothing);

    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(find.byKey(tvCatalogFilterRailKey), findsNothing);
    expect(
      FocusManager.instance.primaryFocus?.context,
      isNotNull,
      reason: 'the ring is on something that is actually on screen',
    );
    expect(focusedLabel(), isNot('TvCatalogRailSources'), reason: 'and not on the rail that just collapsed');
  });

  testWidgets('CAT6: closing the rail from a gridless state hands the ring back to its action', (tester) async {
    await pump(tester, failing: true);

    expect(find.byType(TvUnifiedMediaGrid), findsNothing, reason: 'sanity: the failed page has no grid');
    expect(find.text(t.common.retry), findsOneWidget);
    expect(retryFocus(tester).hasPrimaryFocus, isTrue, reason: 'the state focuses its own action on arrival');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
    expect(focusedLabel(), 'TvCatalogRailSources');

    await press(tester, LogicalKeyboardKey.arrowRight);

    expect(find.byKey(tvCatalogFilterRailKey), findsNothing, reason: 'RIGHT collapses the rail again');
    expect(retryFocus(tester).hasPrimaryFocus, isTrue, reason: 'and the ring is on the page, not in the closed rail');
  });

  testWidgets('CAT5: the page heading carries no focusable action any more', (tester) async {
    await pump(tester);

    expect(find.byType(TvCatalogHeaderBar), findsOneWidget, reason: 'sanity: the heading is still drawn');
    expect(
      find.descendant(of: find.byType(TvCatalogHeaderBar), matching: find.byType(FocusableWrapper)),
      findsNothing,
      reason: 'DEC-093: Bronnen, Filters en Sortering left the heading for the rail',
    );
  });

  // ---------------------------------------------------------------------------
  // The rest of the rail's contract
  // ---------------------------------------------------------------------------

  testWidgets('CAT5: Menu closes the rail the way RIGHT does', (tester) async {
    await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    final card = focusedLabel();

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);

    await press(tester, LogicalKeyboardKey.escape);
    expect(find.byKey(tvCatalogFilterRailKey), findsNothing);
    expect(focusedLabel(), card);
  });

  testWidgets('CAT5: UP and DOWN walk Bronnen ↔ Filters ↔ Sortering', (tester) async {
    await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), 'TvCatalogRailSources');

    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), 'TvCatalogRailFilters');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), 'TvCatalogRailSort');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedLabel(), 'TvCatalogRailFilters');
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedLabel(), 'TvCatalogRailSources');
  });

  testWidgets('CAT5: UP from Bronnen closes the rail and reaches for the top navigation', (tester) async {
    final harness = await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), 'TvCatalogRailSources');

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(harness.sidebarFocusCalls, 1, reason: 'the rail must never be a dead end');
    expect(find.byKey(tvCatalogFilterRailKey), findsNothing, reason: 'leaving upwards collapses the rail');
  });

  testWidgets('CAT5: UP from the first grid row reaches the top navigation, the heading no longer catching it', (
    tester,
  ) async {
    final harness = await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(harness.sidebarFocusCalls, 1);
  });

  testWidgets('CAT5: clearing from Wissen does not strand the focus on the row it removes', (tester) async {
    // Something has to be filtered for Wissen to exist at all. Written through
    // the production store, so the screen restores it the way it restores a
    // real viewer's setup.
    await UnifiedCatalogQueryStore.write(
      MediaKind.movie,
      const UnifiedCatalogPreferences(
        filters: UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched),
        sort: UnifiedCatalogSort.titleAsc,
      ),
    );
    await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedLabel(), 'TvCatalogRailClear', reason: 'a filtered catalog has a Wissen row under Sortering');

    await press(tester, LogicalKeyboardKey.select);
    await tester.pumpAndSettle();

    expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget, reason: 'the rail stays open after clearing');
    expect(
      focusedLabel(),
      'TvCatalogRailFilters',
      reason: 'the row it was standing on is gone, so the ring must have moved before the rebuild took it',
    );
  });

  // ---------------------------------------------------------------------------
  // The two measurements DEC-093 left open for this round
  // ---------------------------------------------------------------------------

  testWidgets('CAT5: six columns collapsed, five with the rail open', (tester) async {
    await pump(tester);

    focusGrid(tester);
    await tester.pumpAndSettle();
    expect(renderedColumns(tester), 6, reason: 'D1: the collapsed rail costs no column');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(renderedColumns(tester), 5, reason: 'D2: the open rail costs exactly one column');
  });

  testWidgets('CAT5: five columns still fit at the 1280x918 scale floor of CAT1', (tester) async {
    await pump(tester, surfaceSize: const Size(1280, 918));

    focusGrid(tester);
    await tester.pumpAndSettle();
    expect(renderedColumns(tester), 6);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(renderedColumns(tester), 5);
    expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
    expect(tester.takeException(), isNull, reason: 'no overflow at the lowest supported surface');
  });

  testWidgets('CAT5: the open rail keeps its whole panel inside hoofdstuk 8.1s safe band', (tester) async {
    await pump(tester, surfaceSize: const Size(1920, 1080));

    focusGrid(tester);
    await tester.pumpAndSettle();
    await press(tester, LogicalKeyboardKey.arrowLeft);

    final panel = tester.getRect(find.byKey(tvCatalogFilterRailKey));
    // 56 reference pixels is hoofdstuk 8.1's floor and the grid's own inset;
    // the panel starts on that line and never reaches across it.
    expect(panel.left, greaterThanOrEqualTo(56.0 - 0.5));
    expect(panel.top, greaterThanOrEqualTo(0.0));
  });
}
