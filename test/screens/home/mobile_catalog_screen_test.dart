/// Covers `MobileCatalogScreen` against the frozen `03-alle-films.png` and
/// `04-filters-sheet.png` (iOS Unified 2026 fase 3,
/// `docs/ios-unified-2026-fase3-plan.md`). Mounted over the real
/// `UnifiedCatalogProvider`/`UnifiedCatalogs` stack, the same way
/// `unified_catalog_provider_test.dart` exercises the provider and
/// `mobile_landing_screen_test.dart` exercises a sibling mobile screen: a
/// fake `MediaServerClient` stands in for the network, everything else is
/// the real merge/query/filter pipeline.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/home/mobile_catalog_screen.dart';
import 'package:pleya/screens/home/mobile_catalog_widgets.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/services/unified_catalog/unified_artwork_prefetcher.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/widgets/focusable_filter_chip.dart';
import 'package:pleya/widgets/mobile/mobile_catalog_sort_sheet.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.id, {this.itemsByLibrary = const {}});

  final String id;
  final Map<String, List<MediaItem>> itemsByLibrary;
  bool shouldThrow = false;
  int fetchCalls = 0;

  @override
  ServerId get serverId => ServerId(id);

  @override
  String? get serverName => id;

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  void close() {}

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    fetchCalls++;
    if (shouldThrow) throw StateError('offline');
    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  Future<MediaItem?> fetchItem(String id) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(String id, {required String title, required String serverId}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: serverId, year: 2024);

MediaLibrary _library(String id, {required String serverId}) => MediaLibrary(
  id: id,
  backend: MediaBackend.plex,
  title: id,
  kind: MediaKind.movie,
  serverId: serverId,
  serverName: serverId,
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late _FakeLibraryClient client;
  late MultiServerManager manager;
  late MultiServerProvider multiServer;
  late HiddenLibrariesProvider hiddenLibraries;
  late LibrariesProvider libraries;
  late UnifiedCatalogs catalogs;

  // A second, empty-backed fixture, built once per test alongside the
  // populated one above rather than by disposing and rebuilding the first
  // mid-test. The empty-state tests select this one instead; nothing here
  // is ever torn down and reconstructed inside a single `testWidgets` body.
  late MultiServerManager emptyManager;
  late MultiServerProvider emptyMultiServer;
  late UnifiedCatalogs emptyCatalogs;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    // `UnifiedCatalogQueryStore.write` also reads `StorageService` (for the
    // profile scope in its key); primed here for the same reason as
    // `SettingsService` above, so its first-ever async platform round trip
    // runs inside this controlled `setUp` rather than mid-test.
    await StorageService.getInstance();
    // `UnifiedCatalogQueryStore.write`'s static write-lock future: see this
    // method's own doc comment for why leaving it alone here can hang every
    // later test in this file, not just flake one.
    UnifiedCatalogQueryStore.resetForTesting();

    client = _FakeLibraryClient(
      's1',
      itemsByLibrary: {
        'A': [
          _movie('a1', title: 'Alien', serverId: 's1'),
          _movie('a2', title: 'Dune', serverId: 's1'),
          _movie('a3', title: 'Civil War', serverId: 's1'),
        ],
      },
    );
    manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    hiddenLibraries = HiddenLibrariesProvider();
    await hiddenLibraries.ensureInitialized();
    libraries = LibrariesProvider()..debugSetLibraries([_library('A', serverId: 's1')]);
    catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hiddenLibraries);

    emptyManager = MultiServerManager()..debugRegisterClientForTesting(_FakeLibraryClient('s1'));
    emptyMultiServer = MultiServerProvider(emptyManager, DataAggregationService(emptyManager));
    emptyCatalogs = UnifiedCatalogs(
      multiServer: emptyMultiServer,
      libraries: libraries,
      hiddenLibraries: hiddenLibraries,
    );
  });

  tearDown(() {
    catalogs.dispose();
    emptyCatalogs.dispose();
    libraries.dispose();
    hiddenLibraries.dispose();
    multiServer.dispose();
    emptyMultiServer.dispose();
  });

  Future<void> pumpCatalog(
    WidgetTester tester, {
    MobileCatalogKind kind = MobileCatalogKind.movies,
    bool useEmpty = false,
    double width = 393,
    double textScale = 1,
    bool disableAnimations = false,
    bool pumpAfter = true,
  }) async {
    tester.view.physicalSize = Size(width, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: useEmpty ? emptyMultiServer : multiServer),
          Provider<UnifiedCatalogs>.value(value: useEmpty ? emptyCatalogs : catalogs),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          builder: (context, child) => MediaQuery(
            data: MediaQuery.of(
              context,
            ).copyWith(textScaler: TextScaler.linear(textScale), disableAnimations: disableAnimations),
            child: child!,
          ),
          home: OverlaySheetHost(
            child: MobileCatalogScreen(
              kind: kind,
              // A real prefetcher would dispatch a real `precacheImage`
              // network fetch the moment the grid renders, which nothing
              // here mocks; it hangs the test instead of failing it.
              debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
            ),
          ),
        ),
      ),
    );
    if (pumpAfter) await tester.pump();
  }

  /// Mounts the screen the way `_TitleRow` does: pushed with
  /// `Navigator.of(context).push` onto a navigator that sits *above* the
  /// screen holding the `OverlaySheetHost`. `MaterialApp.home` stands in for
  /// `MainScreen` here — same shape, one screen under a host, pushing onto the
  /// navigator over it.
  Future<void> pumpPushedCatalog(WidgetTester tester, {MobileCatalogKind kind = MobileCatalogKind.movies}) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          Provider<UnifiedCatalogs>.value(value: catalogs),
        ],
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: OverlaySheetHost(
            child: Builder(
              builder: (context) => Scaffold(
                body: Center(
                  child: TextButton(
                    onPressed: () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => MobileCatalogScreen(
                          kind: kind,
                          debugPrefetcher: UnifiedArtworkPrefetcher(clientFor: (_) => null, precache: (_, _) async {}),
                        ),
                      ),
                    ),
                    child: const Text('All movies'),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('All movies'));
    await tester.pumpAndSettle();
  }

  Future<void> settle(WidgetTester tester) async {
    // `pumpAndSettle` first: it drives the sheet-close animation and the
    // *awaited* half of `_updatePreferences` (`_applyQuery`, which restarts
    // the merge) to completion. The `runAsync` delay after it is the other
    // half: `_updatePreferences` also writes the query store
    // fire-and-forget, and that write needs real wall-clock time through a
    // real (mocked) platform channel round trip, which frame-pumping alone
    // does not provide.
    await tester.pumpAndSettle();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
  }

  /// Taps [finder]. The `ensureVisible` is a no-op for the chip row itself,
  /// which fits the viewport by construction, and is kept for the chips that
  /// a sheet puts inside a scrollable.
  Future<void> tapChip(WidgetTester tester, Finder finder) async {
    await tester.ensureVisible(finder);
    await tester.pump();
    await tester.tap(finder);
  }

  // The screen is not mounted the way the app mounts it. `MobileLandingScreen`
  // is a tab inside `MainScreen`, and `MainScreen.build` is what installs the
  // `OverlaySheetHost`; `_TitleRow` then pushes this screen with
  // `Navigator.of(context).push`, which resolves to the profile navigator
  // *above* `MainScreen`. The pushed route is therefore a sibling of the
  // screen that owns the host, not a descendant of it, and
  // `OverlaySheetController.of` finds nothing. In debug that trips an assert;
  // in a release build the assert is gone and `scope!` throws, the framework
  // swallows it, and every chip is simply dead. Michel on iOS, build 266:
  // "Filters werken helemaal niet bij alle films, kan er niet op drukken."
  //
  // `pumpCatalog` wraps the screen in a host directly, so it cannot see this;
  // this test pushes the screen the way the app does.
  testWidgets('every chip still opens its sheet when the screen is pushed as a route (CAT9)', (tester) async {
    await pumpPushedCatalog(tester);
    await settle(tester);

    await tapChip(tester, find.text(t.unifiedCatalog.filters.title));
    await tester.pumpAndSettle();
    expect(find.text(t.unifiedCatalog.filters.genre), findsOneWidget, reason: 'the Filters chip must open its sheet');
    // This fixture's clients name no audio languages, and since fase 1 of the
    // search-and-filters plan an Audiotaal category without values stays out
    // of the rail instead of showing an empty list.
    expect(find.text(t.libraries.filterCategories.audioLanguage), findsNothing);
    await tester.tap(find.text(t.unifiedCatalog.filters.apply));
    await settle(tester);

    await tapChip(tester, find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)));
    await tester.pumpAndSettle();
    expect(
      find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)),
      findsOneWidget,
      reason: 'and so must the Sort chip',
    );
  });

  testWidgets('shows a skeleton before the stored preferences and the first page have loaded', (tester) async {
    await pumpCatalog(tester);
    // One frame in: `_restorePreferences` has not resolved its first await yet.
    expect(find.byType(GridView), findsNothing);
    expect(find.text(t.unifiedCatalog.states.emptyTitle), findsNothing);
    await settle(tester);
  });

  group('top panel collapses on scroll (A-06)', () {
    Rect panel(WidgetTester tester) => tester.getRect(find.byKey(catalogTopMenuKey));
    bool shown(WidgetTester tester) => panel(tester).bottom > 80;
    bool hidden(WidgetTester tester) => panel(tester).bottom <= 0.5;

    Future<void> scrollBy(WidgetTester tester, double dy) async {
      await tester.drag(find.byType(CustomScrollView), Offset(0, dy));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    void films(int count) {
      client.itemsByLibrary['A'] = [for (var i = 0; i < count; i++) _movie('m$i', title: 'Film $i', serverId: 's1')];
    }

    Future<void> pumpWithInsets(WidgetTester tester) async {
      tester.view.padding = const FakeViewPadding(top: 47, bottom: 34);
      tester.view.viewPadding = const FakeViewPadding(top: 47, bottom: 34);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await pumpCatalog(tester);
      await settle(tester);
    }

    testWidgets('hides on scroll down, returns on any scroll up, fully shown at the top', (tester) async {
      films(18);
      await pumpCatalog(tester);
      await settle(tester);

      expect(shown(tester), isTrue);
      expect(panel(tester).top, 0);

      await scrollBy(tester, -300);
      expect(hidden(tester), isTrue, reason: 'scrolling down hides the panel');

      await scrollBy(tester, 60);
      expect(shown(tester), isTrue, reason: 'a short scroll up mid-list brings it back');

      await scrollBy(tester, -300);
      expect(hidden(tester), isTrue);
      await scrollBy(tester, 3000);
      expect(shown(tester), isTrue, reason: 'at offset 0 it is fully shown');
    });

    /// Scrolls with the finger kept down, so no fling moves the grid while
    /// the panel animates; the caller lifts it.
    Future<TestGesture> holdScroll(WidgetTester tester, double dy) async {
      final gesture = await tester.startGesture(tester.getCenter(find.byType(CustomScrollView)));
      final step = dy.sign * 20;
      for (var moved = 0.0; moved.abs() < dy.abs(); moved += step) {
        await gesture.moveBy(Offset(0, step));
      }
      return gesture;
    }

    /// Fraction of its own height the panel has moved up: 0 shown, 1 gone.
    double progress(WidgetTester tester) => -panel(tester).top / panel(tester).height;

    /// The panel's own fade: the one Opacity inside the panel that wraps the
    /// title. `tester.widget` throws if that ever matches more than one.
    double titleOpacity(WidgetTester tester) => tester
        .widget<Opacity>(
          find.descendant(
            of: find.byKey(catalogTopMenuKey),
            matching: find.ancestor(of: find.text(t.unifiedCatalog.moviesTitle), matching: find.byType(Opacity)),
          ),
        )
        .opacity;

    testWidgets('leaving is an eased slide and fade over several frames, and the grid stays put', (tester) async {
      films(18);
      await pumpCatalog(tester);
      await settle(tester);

      final gesture = await holdScroll(tester, -200);
      // The frame that flips the state starts the motion; the next one is
      // the ticker's first tick.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      final grid = tester.getRect(find.text('Film 6'));

      final steps = <double>[];
      final opacities = <double>[];
      for (var i = 0; i < 5; i++) {
        await tester.pump(const Duration(milliseconds: 40));
        steps.add(progress(tester));
        opacities.add(titleOpacity(tester));
        expect(tester.getRect(find.text('Film 6')), grid, reason: 'the panel moving must not move the grid');
      }
      expect(steps.first, inExclusiveRange(0, 1), reason: 'no jump: 40 ms in, the panel is on its way: $steps');
      for (var i = 1; i < steps.length; i++) {
        expect(steps[i], greaterThan(steps[i - 1]), reason: 'it keeps moving, frame by frame: $steps');
      }
      expect(
        steps[1] - steps[0],
        greaterThan(2 * (steps[4] - steps[3])),
        reason: 'eased out: fast start, soft end: $steps',
      );
      expect(opacities.first, inExclusiveRange(0, 1), reason: 'and fades on the way: $opacities');

      await tester.pump(catalogPanelHideDuration);
      expect(progress(tester), 1);
      expect(hidden(tester), isTrue);
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('it comes back quicker than it left', (tester) async {
      films(18);
      await pumpCatalog(tester);
      await settle(tester);

      final down = await holdScroll(tester, -300);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      final leftAfter100 = progress(tester);
      await tester.pump(const Duration(milliseconds: 400));
      await down.up();
      await tester.pumpAndSettle();
      expect(hidden(tester), isTrue);

      final up = await holdScroll(tester, 60);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 100));
      final backAfter100 = 1 - progress(tester);
      expect(backAfter100, inExclusiveRange(0, 1), reason: 'coming back is a motion too');
      expect(backAfter100, greaterThan(leftAfter100), reason: 'return $backAfter100 vs leave $leftAfter100');

      await tester.pump(catalogPanelShowDuration);
      expect(panel(tester).top, 0, reason: 'fully back within the show duration');
      await up.up();
      await tester.pumpAndSettle();
    });

    testWidgets('a reversal halfway turns back from where the panel is', (tester) async {
      films(18);
      await pumpCatalog(tester);
      await settle(tester);

      final gesture = await holdScroll(tester, -200);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 16));
      await tester.pump(const Duration(milliseconds: 60));
      final atFlip = progress(tester);
      expect(atFlip, inExclusiveRange(0, 1), reason: 'the flip lands mid-flight');

      // Same finger, now up: the panel turns around.
      for (var i = 0; i < 3; i++) {
        await gesture.moveBy(const Offset(0, 20));
      }
      final back = <double>[];
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 30));
        back.add(progress(tester));
      }
      expect(back.first, lessThanOrEqualTo(atFlip + 0.15), reason: 'no jump at the flip: $atFlip -> $back');
      for (var i = 1; i < back.length; i++) {
        expect(back[i], lessThanOrEqualTo(back[i - 1]), reason: 'only ever on its way back: $atFlip -> $back');
      }
      await tester.pump(catalogPanelShowDuration);
      expect(panel(tester).top, 0, reason: 'and fully back');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('reduce motion snaps the panel instead of animating it', (tester) async {
      films(18);
      await pumpCatalog(tester, disableAnimations: true);
      await settle(tester);

      final gesture = await holdScroll(tester, -200);
      await tester.pump();
      expect(hidden(tester), isTrue, reason: 'gone in the same frame, no in-between');
      await gesture.up();
      await tester.pumpAndSettle();
    });

    testWidgets('the grid scrolls under the status bar and the home indicator and stays reachable', (tester) async {
      films(18);
      await pumpWithInsets(tester);

      final scroll = tester.getRect(find.byType(CustomScrollView));
      expect(scroll.top, 0, reason: 'the grid reaches under the status bar');
      expect(scroll.bottom, 852, reason: 'and under the home indicator');
      final panelBottom = panel(tester).bottom;
      expect(
        tester.getRect(find.text('Film 0')).top,
        greaterThanOrEqualTo(panelBottom - 16),
        reason: 'at offset 0 the first row starts below the panel',
      );

      await scrollBy(tester, -4000);
      final last = tester.getRect(find.text('Film 17'));
      expect(last.bottom, lessThanOrEqualTo(852 - 34), reason: 'the last row scrolls clear of the home indicator');
    });

    testWidgets('in landscape the back button, the chips and the grid stay clear of the cutout', (tester) async {
      films(18);
      tester.view.padding = const FakeViewPadding(left: 59, right: 59, bottom: 21);
      tester.view.viewPadding = const FakeViewPadding(left: 59, right: 59, bottom: 21);
      addTearDown(tester.view.resetPadding);
      addTearDown(tester.view.resetViewPadding);
      await pumpCatalog(tester, width: 852);
      await settle(tester);

      final back = tester.getRect(find.byIcon(Symbols.arrow_back_rounded).first);
      expect(back.left, greaterThanOrEqualTo(59), reason: 'the back button is not under the cutout');
      for (final chip in tester.widgetList<Widget>(find.byType(FocusableFilterChip)).take(2)) {
        final rect = tester.getRect(find.byWidget(chip));
        expect(rect.left, greaterThanOrEqualTo(59), reason: 'a chip is not under the cutout');
      }
      final first = tester.getRect(find.text('Film 0'));
      expect(first.left, greaterThanOrEqualTo(59), reason: 'the first column is not under the cutout');
      final third = tester.getRect(find.text('Film 2'));
      expect(third.right, lessThanOrEqualTo(852 - 59), reason: 'the last column stays clear of the right edge');
    });

    testWidgets('pull-to-refresh starts below the panel, not behind it', (tester) async {
      films(18);
      await pumpWithInsets(tester);

      final indicator = tester.widget<RefreshIndicator>(find.byType(RefreshIndicator));
      expect(indicator.edgeOffset, greaterThan(100), reason: 'the spinner settles under the translucent panel');
      expect(
        indicator.edgeOffset,
        closeTo(tester.getRect(find.byKey(catalogTopMenuKey)).bottom - CatalogTopPanel.fadeTail, 1.5),
      );
    });

    testWidgets('the grid is not shown a frame before the panel is measured', (tester) async {
      films(18);
      await pumpCatalog(tester, pumpAfter: false);
      // First frame after mount: nothing is visible yet, so nothing can jump.
      expect(tester.widget<Opacity>(find.byKey(const ValueKey('catalog.body'))).opacity, 0);
      await settle(tester);
      expect(tester.widget<Opacity>(find.byKey(const ValueKey('catalog.body'))).opacity, 1);
    });

    testWidgets('a list that barely overflows never flaps', (tester) async {
      films(9);
      await pumpCatalog(tester);
      await settle(tester);

      final states = <bool>[];
      for (var i = 0; i < 4; i++) {
        await scrollBy(tester, -120);
        states.add(hidden(tester));
        await tester.pump(const Duration(milliseconds: 300));
        states.add(hidden(tester));
      }
      expect(states.toSet().length, 1, reason: 'the state never alternates while dragging down: $states');
      await scrollBy(tester, 400);
      expect(shown(tester), isTrue);
    });

    testWidgets('returns when the content stops overflowing while hidden', (tester) async {
      films(18);
      await pumpCatalog(tester);
      await settle(tester);

      await scrollBy(tester, -300);
      expect(hidden(tester), isTrue);

      tester.view.physicalSize = const Size(393, 4000);
      await tester.pump();
      // The metrics notification is dispatched after the frame that changed
      // them; the next frame carries the reaction.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(shown(tester), isTrue, reason: 'nothing left to scroll back with');
    });
  });

  testWidgets('shows the populated grid, the count line and the chip labels once loaded', (tester) async {
    await pumpCatalog(tester);
    await settle(tester);

    expect(find.text('Alien'), findsOneWidget);
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Civil War'), findsOneWidget);
    expect(find.text(t.unifiedCatalog.titlesLoaded(count: 3)), findsOneWidget);
    expect(find.text(t.unifiedCatalog.allSources), findsOneWidget);
    expect(find.text(t.unifiedCatalog.filters.title), findsOneWidget);
    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)), findsOneWidget);
  });

  testWidgets('shows the error state with a retry action when every library fails', (tester) async {
    client.shouldThrow = true;
    await pumpCatalog(tester);
    await settle(tester);

    expect(find.text(t.unifiedCatalog.states.errorTitle), findsOneWidget);
    expect(find.text(t.common.retry), findsOneWidget);
  });

  testWidgets('the sort chip opens the sort sheet and applying a choice re-labels the chip', (tester) async {
    await pumpCatalog(tester);
    await settle(tester);

    await tapChip(tester, find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)));
    await tester.pumpAndSettle();
    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget);

    await tester.tap(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)));
    // `settle`, not `pumpAndSettle`: the choice writes the query store
    // fire-and-forget, and that write needs real wall-clock time via
    // `runAsync` to actually land before this test ends; `pumpAndSettle`
    // alone does not guarantee that.
    await settle(tester);

    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget);
    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.titleAsc)), findsNothing);
  });

  testWidgets('the filters chip opens the filter sheet and Toepassen updates the badge count', (tester) async {
    await pumpCatalog(tester);
    await settle(tester);
    final callsBeforeFilter = client.fetchCalls;

    // The Filters chip opens the sheet on Status, unlike the sources chip
    // (which opens on Servers). Status is the one category whose options
    // do not depend on what the fake client happens to have loaded.
    await tapChip(tester, find.text(t.unifiedCatalog.filters.title));
    await tester.pumpAndSettle();
    expect(find.text(t.unifiedCatalog.filters.genre), findsOneWidget);

    await tester.tap(find.text(t.unifiedCatalog.filters.unwatched));
    await tester.tap(find.text(t.unifiedCatalog.filters.apply));
    // `settle`, not `pumpAndSettle`: see the sort-chip test above.
    await settle(tester);

    expect(client.fetchCalls, greaterThan(callsBeforeFilter));
    expect(find.text('1'), findsOneWidget);
  });

  testWidgets('a previously stored selection is restored on the next open', (tester) async {
    // `runAsync`, niet een kale await: de statische prefs-cache is in `setUp`
    // aangemaakt, dus in de echte zone. Een `testWidgets`-body draait in de
    // FakeAsync-zone, en een future die in een andere zone voltooide levert
    // daar zijn continuation nooit af. Zie de noot boven de laatste twee tests.
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.recentlyAdded),
      ),
    );

    await pumpCatalog(tester);
    await settle(tester);

    expect(find.text(mobileCatalogSortLabel(UnifiedCatalogSort.recentlyAdded)), findsOneWidget);
  });

  testWidgets('long catalog controls stay on one horizontally scrollable line', (tester) async {
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.recentlyAdded),
      ),
    );

    const width = 393.0;
    await pumpCatalog(tester, width: width);
    await settle(tester);

    final chips = tester.widgetList<FocusableFilterChip>(find.byType(FocusableFilterChip)).toList();
    final tops = chips.map((chip) => tester.getTopLeft(find.byWidget(chip)).dy).toSet();
    expect(tops, hasLength(1), reason: 'Movies and Series use one compact control line');

    final scroller = find.ancestor(
      of: find.byType(FocusableFilterChip).first,
      matching: find.byType(SingleChildScrollView),
    );
    expect(scroller, findsOneWidget);

    final first = find.byWidget(chips.first);
    final before = tester.getTopLeft(first).dx;
    await tester.drag(scroller, const Offset(-80, 0));
    await tester.pumpAndSettle();
    expect(tester.getTopLeft(first).dx, lessThan(before));
  });

  testWidgets('every chip stays within the screen at large accessibility text scales', (tester) async {
    const width = 393.0;
    await pumpCatalog(tester, width: width, textScale: 3);
    await settle(tester);

    expect(tester.takeException(), isNull);
    final tops = tester
        .widgetList<FocusableFilterChip>(find.byType(FocusableFilterChip))
        .map((chip) => tester.getTopLeft(find.byWidget(chip)).dy)
        .toSet();
    expect(tops, hasLength(1));
  });

  // The other half of the same rule: wrapping is what happens when there is no
  // room, not a second line the screen grows by default. Series' short labels
  // (`1 bron`, `Recent bekeken`) stay on one line, and so does everything else
  // that fits.
  testWidgets('chips that fit stay on a single line', (tester) async {
    await pumpCatalog(tester, width: 1200);
    await settle(tester);

    final tops = tester
        .widgetList<FocusableFilterChip>(find.byType(FocusableFilterChip))
        .map((chip) => tester.getTopLeft(find.byWidget(chip)).dy)
        .toSet();
    expect(tops, hasLength(1));
  });

  testWidgets('a stored library restriction naming a library that no longer exists is dropped on open', (tester) async {
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(
          filters: const UnifiedCatalogFilterSelection(libraryKeys: {'s1:ghost-library'}),
        ),
      ),
    );

    await pumpCatalog(tester);
    await settle(tester);

    final restored = (await tester.runAsync(() => UnifiedCatalogQueryStore.read(MediaKind.movie)))!;
    expect(restored.filters.libraryKeys, isEmpty, reason: 'a vanished library has no row left to untick it with');
    // The prune is also written back, so the badge does not keep counting a
    // restriction the panel can no longer show.
    expect(find.text(t.unifiedCatalog.filters.title), findsOneWidget);
  });

  // Deze twee stonden hier als laatste omdat de vastloop hierna toesloeg, en
  // dat is opgelost, niet omzeild. De oorzaak was geen omgeving en geen
  // flakiness: `setUp` maakt de statische prefs-cache aan
  // (`SettingsService.getInstance`, `StorageService.getInstance`) en dus in de
  // echte zone, terwijl een `testWidgets`-body in de FakeAsync-zone draait. Een
  // future die in de ene zone voltooide levert zijn continuation in de andere
  // nooit af, dus elke kale `await UnifiedCatalogQueryStore.write/read` in een
  // body hing stil en permanent, tot de timeout van tien minuten. Op CI net zo
  // goed als lokaal. De drie tests die zo'n directe aanroep doen gebruiken nu
  // `tester.runAsync`, dat in de echte zone draait; daarmee loopt dit bestand
  // in seconden in plaats van drie keer tien minuten. De volgorde hieronder is
  // sindsdien willekeurig en mag veranderen.
  testWidgets('shows the generic empty state when the catalog has nothing and no filter is active', (tester) async {
    await pumpCatalog(tester, useEmpty: true);
    await settle(tester);

    expect(find.text(t.unifiedCatalog.states.emptyTitle), findsOneWidget);
  });

  testWidgets('shows the filtered-empty state when a stored selection matches nothing', (tester) async {
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(filters: const UnifiedCatalogFilterSelection(genres: {'Horror'})),
      ),
    );

    await pumpCatalog(tester, useEmpty: true);
    await settle(tester);

    expect(find.text(t.unifiedCatalog.states.filterEmptyTitle), findsOneWidget);
    expect(find.text(t.unifiedCatalog.states.clearFilters), findsOneWidget);
  });
  testWidgets('the count row names every active filter, Leeftijd included', (tester) async {
    await tester.runAsync(
      () => UnifiedCatalogQueryStore.write(
        MediaKind.movie,
        UnifiedCatalogPreferences.defaults.copyWith(
          filters: const UnifiedCatalogFilterSelection(genres: {'Horror'}, officialRatings: {'gb/12|12', '6'}),
        ),
      ),
    );

    await pumpCatalog(tester);
    await settle(tester);

    expect(find.textContaining('Horror · 6, 12'), findsOneWidget);
  });
}
