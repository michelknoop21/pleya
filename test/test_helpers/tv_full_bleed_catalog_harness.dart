/// The production [TvRootShell], [TvTopNavigation] and
/// [TvUnifiedCatalogScreen] with `fullBleed` on, opened under the collapsible
/// bar the way `_openTvCompleteCatalog` opens them, on the Apple TV canvas or a
/// plain 1038 by 584 window. `MainScreen`'s wiring is reduced to the parts the
/// shell talks to, the same reduction `tv_catalog_scroll_away_test.dart` uses.
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
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:provider/provider.dart';

import 'prefs.dart';

/// `_AppleTvScale` in `main.dart`: 3840 x 2160 at a device pixel ratio of 2,
/// laid out at 1/1.85 of the 1920 x 1080 surface.
const Size appleTvPanel = Size(3840, 2160);
const double appleTvRootScale = 1.85;

class FakeLibraryClient implements MediaServerClient {
  FakeLibraryClient(this.items, {this.pageGate});

  List<MediaItem> items;

  /// Awaited before a page is answered, for a test that holds a load open.
  Future<void> Function(LibraryQuery query)? pageGate;

  final List<LibraryQuery> queries = [];

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
  }) async {
    queries.add(query);
    await pageGate?.call(query);
    return LibraryPage<MediaItem>(
      items: items.skip(query.offset).take(query.limit).toList(),
      totalCount: items.length,
      offset: query.offset,
    );
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

MediaItem fakeMovie(int i, {String? title, int? year, int? addedAt, int? lastViewedAt, int? viewCount}) => MediaItem(
  id: 'm$i',
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title ?? 'T${i.toString().padLeft(3, '0')}',
  serverId: 'nas',
  serverName: 'nas',
  year: year,
  addedAt: addedAt,
  lastViewedAt: lastViewedAt,
  viewCount: viewCount,
);

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
    onFocusDestination: _nav.focusDestination,
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

class FullBleedHarness {
  FullBleedHarness._(this.coordinator, this.multiServer, this.catalog, this.client);

  final TvNavigationCoordinator coordinator;
  final MultiServerProvider multiServer;
  final UnifiedCatalogProvider catalog;
  final FakeLibraryClient client;
  final _hostKey = GlobalKey<_HostState>();
  double _rootScale = 1;

  static void setUpAllTv() {
    setUpAll(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));
  }

  static Future<FullBleedHarness> create(List<MediaItem> items, {MediaKind kind = MediaKind.movie}) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();
    LocaleSettings.setLocaleSync(AppLocale.en);
    SelectKeyUpSuppressor.clearSuppression();

    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    final client = FakeLibraryClient(items);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: kind,
          serverId: 'nas',
          serverName: 'nas',
        ),
      ]);
    final hidden = HiddenLibrariesProvider();
    final catalog = UnifiedCatalogProvider(
      multiServer: multiServer,
      libraries: libraries,
      hiddenLibraries: hidden,
      kind: kind,
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
    return FullBleedHarness._(coordinator, multiServer, catalog, client);
  }

  /// Mounts the shell. [canvas] is a plain window at scale 1; null is the
  /// Apple TV canvas with its root scale.
  Future<void> pump(WidgetTester tester, {Size? canvas, bool reduceMotion = false}) async {
    tester.view.physicalSize = canvas ?? appleTvPanel;
    tester.view.devicePixelRatio = canvas == null ? 2 : 1;
    addTearDown(tester.view.reset);
    _rootScale = canvas == null ? appleTvRootScale : 1;
    final view = canvas ?? appleTvPanel / 2 / appleTvRootScale;
    final rootScale = _rootScale;
    await tester.pumpWidget(
      ChangeNotifierProvider<MultiServerProvider>.value(
        value: multiServer,
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            builder: (context, child) {
              final media = MediaQuery.of(context).copyWith(disableAnimations: reduceMotion);
              if (rootScale == 1) return MediaQuery(data: media, child: child!);
              return Transform.scale(
                scale: rootScale,
                alignment: Alignment.topLeft,
                child: OverflowBox(
                  alignment: Alignment.topLeft,
                  minWidth: view.width,
                  maxWidth: view.width,
                  minHeight: view.height,
                  maxHeight: view.height,
                  child: MediaQuery(
                    data: media.copyWith(size: view, devicePixelRatio: media.devicePixelRatio * rootScale),
                    child: child!,
                  ),
                ),
              );
            },
            home: InputModeTracker(
              child: _Host(key: _hostKey, coordinator: coordinator),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// Opens the route as `_openTvCompleteCatalog` does.
  Future<void> open(WidgetTester tester, {bool fullBleed = true}) async {
    final screenKey = GlobalKey(debugLabel: 'tvCatalog_movies');
    _hostKey.currentState!.open(
      TvNestedRoute(
        id: 'tvCatalog_movies',
        screenKey: screenKey,
        topNav: TvTopNavPresentation.collapsible,
        builder: (_) =>
            TvUnifiedCatalogScreen(key: screenKey, catalog: catalog, title: 'All movies', fullBleed: fullBleed),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  bool get isNavFocused => _hostKey.currentState!.isNavFocused;

  /// A rect in the app's own logical pixels, under any root scale.
  Rect logical(Rect r) => _rootScale == 1
      ? r
      : Rect.fromLTRB(r.left / _rootScale, r.top / _rootScale, r.right / _rootScale, r.bottom / _rootScale);

  Rect posterRect(WidgetTester tester, int index) => logical(tester.getRect(find.byKey(tvCatalogPosterKey).at(index)));

  String cardLabel(int index) => 'TvUnifiedCard(${catalog.snapshot.groups[index].groupId})';

  String? get focused => FocusManager.instance.primaryFocus?.debugLabel;

  double get windowHeight => (appleTvPanel.height / 2) / appleTvRootScale;
}
