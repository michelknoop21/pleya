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
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

const _window = Size(1920, 1080);

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
    final manager = MultiServerManager()
      ..debugRegisterClientForTesting(_FakeLibraryClient([for (var i = 0; i < _titles; i++) _movie(i)]));
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

  Future<void> pump(WidgetTester tester, {bool reduceMotion = false}) async {
    tester.view.physicalSize = _window;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(context).copyWith(disableAnimations: reduceMotion),
              child: child!,
            ),
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

  Rect navRect(WidgetTester tester) => tester.getRect(find.byType(TvTopNavigation));
  Rect headerRect(WidgetTester tester) => tester.getRect(find.byType(TvCatalogHeaderBar));
  Rect gridRect(WidgetTester tester) => tester.getRect(find.byType(TvCatalogCardGrid));
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
      closeTo(TvTopNavLayout.topInset, 0.5),
      reason: 'the grid moved up to the overscan line, scale 1.0 at 1080',
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
    await tester.pump(const Duration(milliseconds: 240));
    expect(barHidden(tester), isFalse, reason: 'still leaving at 256 ms of 320');
    await tester.pumpAndSettle();
    expectFolded(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 230));
    expectShown(tester);
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
