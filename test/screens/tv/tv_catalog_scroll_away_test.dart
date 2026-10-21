/// A-06b: on Alle films and Alle series the page heading and the top
/// navigation glide away once the remote is past the first grid row, and come
/// back on the first row or in the bar.
///
/// Driven through the production [TvRootShell], [TvTopNavigation] and
/// [TvUnifiedCatalogScreen], with a real [SidebarFocusCoordinator] as the
/// nav-versus-content authority, wired the way `MainScreen` wires it (same
/// host as `tv_collapsible_top_nav_test.dart`). The route is opened with
/// [TvTopNavPresentation.scrollAway], exactly as `_openTvCompleteCatalog` does.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/navigation/sidebar_focus_coordinator.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalog_provider.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/screens/tv/tv_unified_catalog_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_scroll_away_page.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _window = Size(1920, 1080);

/// Where the folded grid starts at [_window], scale 1.0.
/// The Apple TV canvas as `_AppleTvScale` in `main.dart` builds it: a
/// 3840 x 2160 panel at a device pixel ratio of 2, a 1920 x 1080 surface the
/// app lays out at 1/1.85 of (1037.8 x 583.8, ten-foot scale clamped to
/// 0.85) and draws back up through a root `Transform.scale` (DEC-028).
const Size _appleTvPanel = Size(3840, 2160);
const double _appleTvRootScale = 1.85;

/// The logical size the last [pump] laid out at.
Size _view = _window;

/// The root scale the last [pump] drew through; rects come back divided by it.
double _rootScale = 1;

({double top, double overhang, double margin}) _frame() => TvScrollAwayPage.foldedGridFrame(size: _view);

/// Three rows of six at 1920 wide.
const int _titles = 18;

class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient(this.items);

  final List<MediaItem> items;

  @override
  ServerId get serverId => ServerId('nas');

  @override
  String? get serverName => 'nas';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async => LibraryPage<MediaItem>(
    items: items.skip(query.offset).take(query.limit).toList(),
    totalCount: items.length,
    offset: query.offset,
  );

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem _movie(int i) => MediaItem(
  id: 'm$i',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: 'T${i.toString().padLeft(2, '0')}',
  serverId: 'nas',
  serverName: 'nas',
);

/// `MainScreen`'s TV wiring, reduced to the parts the shell talks to.
class _Host extends StatefulWidget {
  const _Host({super.key, required this.coordinator});

  final TvNavigationCoordinator coordinator;

  @override
  State<_Host> createState() => _HostState();
}

class _HostState extends State<_Host> {
  final _focus = SidebarFocusCoordinator();
  final navNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');
  final _contentFocus = TvContentFocusAuthority();

  TvNavigationCoordinator get _nav => widget.coordinator;

  bool get isNavFocused => _focus.isSidebarFocused;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_rebuild);
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _focus.removeListener(_rebuild);
    _focus.dispose();
    navNodes.dispose();
    super.dispose();
  }

  void open(TvNestedRoute route) {
    _nav.pushNested(_nav.active, route);
    _focusContent(restorePreviousFocus: false);
  }

  void _focusNav() {
    _nav.activeNestedRoute?.surfaceKey.currentState?.cancelPendingEntry();
    _focus.focusSidebar(focusActiveItem: _focusActiveNavItem);
  }

  void _focusActiveNavItem() {
    final node = navNodes.get(_nav.focusedDestination.focusKey);
    if (node.canRequestFocus) node.requestFocus();
  }

  void _focusContent({bool restorePreviousFocus = true}) => _focus.focusContent(
    restorePreviousFocus: restorePreviousFocus,
    focusDefault: () => WidgetsBinding.instance.addPostFrameCallback((_) {
      _nav.activeNestedRoute?.surfaceKey.currentState?.focusEntry();
    }),
  );

  KeyEventResult _onKey(KeyEvent event) {
    if (event is! KeyDownEvent || event.logicalKey != LogicalKeyboardKey.escape) return KeyEventResult.ignored;
    switch (tvBackStep(hasNestedRoute: _nav.activeCanPop, isNavigationFocused: isNavFocused)) {
      case TvBackStep.popNested:
        _nav.popNested();
        WidgetsBinding.instance.addPostFrameCallback((_) => _focusContent());
      case TvBackStep.focusTopNavigation:
        _focusNav();
      case TvBackStep.rootContract:
        break;
    }
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) => TvRootShell(
    coordinator: _nav,
    contentFocus: _contentFocus,
    navNodes: navNodes,
    navFocusScope: _focus.sidebarScope,
    contentFocusScope: _focus.contentScope,
    isNavFocused: isNavFocused,
    profile: null,
    onSelectDestination: (destination) {
      _nav.activate(destination);
      _focusContent(restorePreviousFocus: false);
    },
    onFocusDestination: _nav.activate,
    onFocusContent: _focusContent,
    onFocusNav: _focusNav,
    onOpenProfiles: () {},
    onOverlaySheetOpenChanged: (_) {},
    onKeyEvent: _onKey,
    selectLibrary: null,
    openSettings: null,
    dismissNestedRoute: ([_]) {},
    child: const SizedBox.expand(child: Text('destination root')),
  );
}

void main() {
  late TvNavigationCoordinator coordinator;
  late MultiServerProvider multiServer;
  late UnifiedCatalogProvider catalog;
  late _FakeLibraryClient client;
  final hostKey = GlobalKey<_HostState>();

  setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    SelectKeyUpSuppressor.clearSuppression();

    coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    client = _FakeLibraryClient([for (var i = 0; i < _titles; i++) _movie(i)]);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'nas',
        ),
      ]);
    final hidden = HiddenLibrariesProvider();
    catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hidden,
      kind: MediaKind.movie,
    );
    addTearDown(() {
      catalog.dispose();
      libraries.dispose();
      hidden.dispose();
      multiServer.dispose();
      coordinator.dispose();
      SelectKeyUpSuppressor.clearSuppression();
    });
    await catalog.ensureStarted();
  });

  Future<void> pump(WidgetTester tester, {bool reduceMotion = false, bool appleTv = false}) async {
    tester.view.physicalSize = appleTv ? _appleTvPanel : _window;
    tester.view.devicePixelRatio = appleTv ? 2 : 1;
    _rootScale = appleTv ? _appleTvRootScale : 1;
    _view = (appleTv ? _appleTvPanel / 2 : _window) / _rootScale;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            builder: (context, child) {
              final media = MediaQuery.of(context).copyWith(disableAnimations: reduceMotion);
              if (_rootScale == 1) return MediaQuery(data: media, child: child!);
              return Transform.scale(
                scale: _rootScale,
                alignment: Alignment.topLeft,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: _view.width,
                  maxWidth: _view.width,
                  minHeight: _view.height,
                  maxHeight: _view.height,
                  child: MediaQuery(
                    data: media.copyWith(size: _view, devicePixelRatio: media.devicePixelRatio * _rootScale),
                    child: child!,
                  ),
                ),
              );
            },
            home: InputModeTracker(
              child: _Host(key: hostKey, coordinator: coordinator),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openCatalog(WidgetTester tester, {TvTopNavPresentation topNav = TvTopNavPresentation.scrollAway}) async {
    final screenKey = GlobalKey(debugLabel: 'tvCatalog_movies');
    hostKey.currentState!.open(
      TvNestedRoute(
        id: 'tvCatalog_movies',
        screenKey: screenKey,
        topNav: topNav,
        builder: (_) => TvUnifiedCatalogScreen(key: screenKey, catalog: catalog, title: 'All movies'),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  /// A rect in the app's own logical pixels, under any root scale.
  Rect logical(Rect r) => _rootScale == 1
      ? r
      : Rect.fromLTRB(r.left / _rootScale, r.top / _rootScale, r.right / _rootScale, r.bottom / _rootScale);
  Rect navRect(WidgetTester tester) => logical(tester.getRect(find.byType(TvTopNavigation)));
  Rect headerRect(WidgetTester tester) => logical(tester.getRect(find.byType(TvCatalogHeaderBar)));
  Rect gridRect(WidgetTester tester) => logical(tester.getRect(find.byType(TvCatalogCardGrid)));
  double headerOpacity(WidgetTester tester) => tester
      .widget<FadeTransition>(
        find.ancestor(of: find.byType(TvCatalogHeaderBar), matching: find.byType(FadeTransition)).first,
      )
      .opacity
      .value;
  FocusNode? primary() => FocusManager.instance.primaryFocus;
  String cardLabel(int index) => 'TvUnifiedCard(${catalog.snapshot.groups[index].groupId})';

  /// The bar is fully above the window.
  bool barHidden(WidgetTester tester) => navRect(tester).bottom <= 0;

  void expectShown(WidgetTester tester) {
    expect(navRect(tester).top, 0, reason: 'the bar is on screen');
    expect(headerRect(tester).top, closeTo(navRect(tester).bottom, 0.5), reason: 'the heading sits right under it');
    expect(headerOpacity(tester), 1);
    expect(gridRect(tester).top, closeTo(headerRect(tester).bottom, 0.5));
  }

  void expectFolded(WidgetTester tester) {
    expect(barHidden(tester), isTrue, reason: 'the bar has glided out of view');
    expect(headerOpacity(tester), 0, reason: 'the heading has faded out');
    expect(
      gridRect(tester).top,
      closeTo(_frame().top, 0.5),
      reason: 'folded, the grid starts where two whole rows fit with equal room above and below',
    );
  }

  testWidgets('opens at the top with the bar and the heading on screen and the ring on the first card', (tester) async {
    await pump(tester);
    await openCatalog(tester);

    expect(catalog.snapshot.groups, hasLength(_titles));
    expect(primary()?.debugLabel, cardLabel(0));
    expect(hostKey.currentState!.isNavFocused, isFalse);
    expectShown(tester);
  });

  testWidgets('DOWN past the first row folds the heading and the bar away, the ring stays on the card', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    final gridSize = gridRect(tester).size;

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(primary()?.debugLabel, cardLabel(6), reason: 'row 1, column 0');
    expect(hostKey.currentState!.isNavFocused, isFalse);
    expectFolded(tester);
    expect(gridRect(tester).size, gridSize, reason: 'the grid moves, it is not laid out at another size');
  });

  testWidgets('DOWN within the folded rows changes nothing, UP to the first row brings both back', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(primary()?.debugLabel, cardLabel(12));
    expectFolded(tester);

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(primary()?.debugLabel, cardLabel(6));
    expectFolded(tester);

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(primary()?.debugLabel, cardLabel(0));
    expectShown(tester);
  });

  testWidgets('UP from the first row puts the ring in a visible bar', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowUp);
    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(hostKey.currentState!.isNavFocused, isTrue);
    expect(primary(), hostKey.currentState!.navNodes.get(coordinator.active.focusKey));
    expectShown(tester);
  });

  testWidgets('the rail opens without moving the page, and UP out of it shows the bar before the ring lands', (
    tester,
  ) async {
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expectFolded(tester);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(primary()?.debugLabel, 'TvCatalogRailSources');
    expectFolded(tester);

    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(hostKey.currentState!.isNavFocused, isTrue);
    expect(primary(), hostKey.currentState!.navNodes.get(coordinator.active.focusKey));
    expectShown(tester);

    // DOWN goes back into the page, onto the card it was left on, and the
    // page folds away again because that card is past the first row.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(hostKey.currentState!.isNavFocused, isFalse);
    expect(barHidden(tester), isTrue);
  });

  testWidgets('glides: leaving takes longer than returning, and nothing jumps on the first frame', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    final restTop = gridRect(tester).top;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    final firstFrame = gridRect(tester).top;
    expect(firstFrame, lessThan(restTop), reason: 'it has started moving');
    expect(firstFrame, greaterThan(TvTopNavLayout.topInset), reason: 'but it did not jump there');
    await tester.pump(const Duration(milliseconds: 160));
    expect(barHidden(tester), isFalse, reason: 'still leaving at 176 ms of 260');
    await tester.pumpAndSettle();
    expectFolded(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 210));
    expectShown(tester);
  });

  testWidgets('a reversal halfway carries on from where it is, in the time the distance left needs', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    final restTop = gridRect(tester).top;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 60));
    final midway = gridRect(tester).top;
    expect(midway, lessThan(restTop));
    expect(midway, greaterThan(TvTopNavLayout.topInset));

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    expect(gridRect(tester).top, closeTo(midway, 1), reason: 'no jump back to either end');
    // About half the way is left, so about half of the 200 ms return.
    await tester.pump(const Duration(milliseconds: 140));
    expect(gridRect(tester).top, closeTo(restTop, 0.5));
    expect(headerOpacity(tester), 1);
    expect(navRect(tester).top, closeTo(0, 0.5), reason: 'the bar turned round with the page, not on its own clock');
    await tester.pumpAndSettle();
    expectShown(tester);
  });

  testWidgets('a grid that empties under a folded page brings the bar and the heading back', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(primary()?.debugLabel, 'TvCatalogRailSources');
    expectFolded(tester);

    // The ring stays in the rail, so nothing moves the focus into the bar:
    // only the page's own flag can bring it back.
    client.items.clear();
    await catalog.refresh();
    await tester.pumpAndSettle();

    expect(find.byType(TvCatalogCardGrid), findsNothing, reason: 'the empty state replaced the grid');
    expect(primary()?.debugLabel, 'TvCatalogRailSources');
    expect(hostKey.currentState!.isNavFocused, isFalse);
    expect(navRect(tester).top, 0, reason: 'nothing to be past, so the bar is back');
    expect(headerOpacity(tester), 1);
  });

  testWidgets('closing the route with the ring in the bar keeps the same bar, no remount', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(hostKey.currentState!.isNavFocused, isTrue);
    final navNode = hostKey.currentState!.navNodes.get(coordinator.active.focusKey);
    expect(navNode.hasPrimaryFocus, isTrue);
    final barElement = tester.element(find.byType(TvTopNavigation));
    final itemFinder = find.byWidgetPredicate((w) => w is Focus && identical(w.focusNode, navNode));
    final itemElement = tester.element(itemFinder);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();

    expect(coordinator.activeCanPop, isFalse, reason: 'the catalog route is gone, the bar is persistent again');
    expect(identical(tester.element(find.byType(TvTopNavigation)), barElement), isTrue);
    expect(
      identical(tester.element(itemFinder), itemElement),
      isTrue,
      reason: 'the Focus that held the ring is the same element, so its node was never detached',
    );
    await tester.pumpAndSettle();
    expect(navRect(tester).top, 0);
  });

  testWidgets('back from a detail opened on row 2 returns to a folded page, ring on the same card', (tester) async {
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(primary()?.debugLabel, cardLabel(12));
    expectFolded(tester);

    final detailStop = FocusNode(debugLabel: 'detail stop');
    addTearDown(detailStop.dispose);
    hostKey.currentState!.open(
      TvNestedRoute(
        id: 'detail',
        topNav: TvTopNavPresentation.collapsible,
        builder: (_) => Focus(
          focusNode: detailStop,
          child: const SizedBox.expand(child: Text('detail')),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(primary(), detailStop);
    expect(barHidden(tester), isTrue);

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    for (var frame = 0; frame < 20; frame++) {
      await tester.pump(const Duration(milliseconds: 16));
      expect(barHidden(tester), isTrue, reason: 'the bar never flashes in on the way back (frame $frame)');
    }
    await tester.pumpAndSettle();

    expect(primary()?.debugLabel, cardLabel(12));
    expectFolded(tester);
  });

  /// Sixty films, ten rows: enough for the grid to really scroll.
  Future<void> growCatalog() async {
    client.items
      ..clear()
      ..addAll([for (var i = 0; i < 60; i++) _movie(i)]);
    await catalog.refresh();
  }

  Rect cardRect(WidgetTester tester, int index) => logical(
    tester.getRect(find.byWidgetPredicate((w) => w is Focus && w.focusNode?.debugLabel == cardLabel(index)).first),
  );

  double scrollOffset(WidgetTester tester) => tester
      .state<ScrollableState>(
        find.descendant(of: find.byType(TvCatalogCardGrid), matching: find.byType(Scrollable)).first,
      )
      .position
      .pixels;

  /// Rows [top] and [top] + 1 stand whole on screen, poster to year, the top
  /// one on the same line every time, and the focused card, 6% scale-up
  /// included, keeps Apple's title-safe 60 of 1080 clear at both edges.
  void expectTwoWholeRows(WidgetTester tester, {required int top, required int focusedRow}) {
    final margin = _frame().margin;
    final upper = cardRect(tester, top * 6);
    final lower = cardRect(tester, (top + 1) * 6);
    final ring = upper.height * (FocusTheme.fullCardFocusScale - 1) / 2;
    expect(upper.top - ring, closeTo(margin, 0.5), reason: 'row $top is the top row, on the row line');
    expect(lower.bottom + ring, lessThanOrEqualTo(_view.height - margin + 0.5), reason: 'room under row ${top + 1}');
    final focused = cardRect(tester, focusedRow * 6);
    expect(focused.top - ring, greaterThanOrEqualTo(margin - 0.5));
    expect(focused.bottom + ring, lessThanOrEqualTo(_view.height - margin + 0.5));
  }

  Future<void> walkTwoRows(WidgetTester tester) async {
    for (var row = 1; row <= 6; row++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(primary()?.debugLabel, cardLabel(row * 6));
      expectTwoWholeRows(tester, top: row - 1, focusedRow: row);
      expectFolded(tester);
    }
    for (var row = 5; row >= 1; row--) {
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(primary()?.debugLabel, cardLabel(row * 6));
      expectTwoWholeRows(tester, top: row, focusedRow: row);
      expectFolded(tester);
    }
  }

  testWidgets('folded, DOWN and UP keep two whole rows on screen, a row at a time', (tester) async {
    await growCatalog();
    await pump(tester);
    await openCatalog(tester);
    expect(_frame().margin, closeTo(60, 0.1), reason: "Apple's title-safe 60 of 1080");
    await walkTwoRows(tester);
  });

  testWidgets('on the Apple TV canvas too, with room around the two rows', (tester) async {
    await growCatalog();
    await pump(tester, appleTv: true);
    await openCatalog(tester);
    expect(_view.height, closeTo(583.8, 0.1));
    expect(_frame().margin, closeTo(583.8 * 60 / 1080, 0.1), reason: "Apple's title-safe 60 of 1080");
    await walkTwoRows(tester);
  });

  testWidgets('the library-density setting narrows the cards, and two rows still fit', (tester) async {
    await growCatalog();
    await pump(tester, appleTv: true);
    await openCatalog(tester);
    final atDefault = cardRect(tester, 0).width;

    await SettingsService.instance.write(SettingsService.libraryDensity, LibraryDensity.min);
    coordinator.popNested();
    await tester.pumpAndSettle();
    await openCatalog(tester);
    final atCompact = cardRect(tester, 0).width;

    expect(atCompact, closeTo(atDefault * 0.8, 1), reason: 'density 1 takes a fifth off the two-row width');
    await walkTwoRows(tester);
  });

  testWidgets('a row change glides the content, it does not jump a row at once', (tester) async {
    await growCatalog();
    await pump(tester);
    await openCatalog(tester);
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(scrollOffset(tester), 0, reason: 'rows 0 and 1 both fit, nothing to scroll yet');
    final pitch = cardRect(tester, 6).top - cardRect(tester, 0).top;

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 16));
    await tester.pump(const Duration(milliseconds: 16));
    final early = scrollOffset(tester);
    expect(early, greaterThan(0), reason: 'it has started');
    // Traversal's own ensureVisible would have jumped to ~95% of a row.
    expect(early, lessThan(pitch * 0.8), reason: 'and is on its way, not already there');
    await tester.pumpAndSettle();
    expect(scrollOffset(tester), closeTo(pitch, 0.5), reason: 'it ends exactly one row further');
  });

  testWidgets('UP out of the rail into the bar brings the first row back whole under the heading', (tester) async {
    await growCatalog();
    await pump(tester);
    await openCatalog(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(scrollOffset(tester), greaterThan(0), reason: 'the grid really scrolled');
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(primary()?.debugLabel, 'TvCatalogRailSources');

    await press(tester, LogicalKeyboardKey.arrowUp);

    expect(hostKey.currentState!.isNavFocused, isTrue);
    expectShown(tester);
    expect(scrollOffset(tester), 0, reason: 'the page is back at its top together with the heading');
    final first = cardRect(tester, 0);
    expect(first.top, greaterThanOrEqualTo(headerRect(tester).bottom), reason: 'poster not under the heading');
    expect(first.bottom, lessThanOrEqualTo(_window.height), reason: 'title and year on screen');
  });

  testWidgets('UP onto the first row puts it whole under the returning heading', (tester) async {
    await growCatalog();
    await pump(tester);
    await openCatalog(tester);
    for (var i = 0; i < 4; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    for (var i = 0; i < 4; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
    }
    expect(primary()?.debugLabel, cardLabel(0));
    expectShown(tester);
    expect(scrollOffset(tester), 0);
    final first = cardRect(tester, 0);
    expect(first.top, greaterThanOrEqualTo(headerRect(tester).bottom));
    expect(first.bottom, lessThanOrEqualTo(_window.height));
  });

  testWidgets('reduce motion: both states are reached on the next frame', (tester) async {
    await pump(tester, reduceMotion: true);
    await openCatalog(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();
    await tester.pump();
    expectFolded(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump();
    expectShown(tester);
  });

  testWidgets('a persistent route keeps the bar and the heading where they were', (tester) async {
    await pump(tester);
    await openCatalog(tester, topNav: TvTopNavPresentation.persistent);
    final header = headerRect(tester);

    await press(tester, LogicalKeyboardKey.arrowDown);

    expect(primary()?.debugLabel, cardLabel(6));
    expect(navRect(tester).top, 0);
    expect(headerRect(tester), header);
  });
}
