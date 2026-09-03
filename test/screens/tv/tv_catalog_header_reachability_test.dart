/// CAT4: "Bron, filters en sortering mogelijk onbereikbaar"
/// (`docs/tvos-fysieke-correctieronde.md`).
///
/// ## Why the existing suites do not cover this
///
/// `tv_unified_catalog_focus_test.dart` proves the screen's own half of the
/// contract — grid ↔ header, and header asking the shell for the sidebar —
/// against a bare `MainScreenFocusScope` stand-in with no `SidebarFocusCoordinator`
/// behind it. `tv_destination_restoration_test.dart` drives the real
/// `TvRootShell` and a real catalog, but its `_ShellHost` test double calls
/// `focusActiveTabIfReady()` directly on every visit rather than going through
/// `SidebarFocusCoordinator.focusContent`'s `restorePreviousFocus` branch —
/// exactly the mechanism `MainScreen._focusContent` uses in production. No
/// suite in this repo mounts that mechanism against a screen with a header, a
/// gap `tv_content_focus_authority_test.dart` states explicitly ("The one
/// thing not mounted is `MainScreen` itself").
///
/// This file closes that gap: the harness below is `MainScreen`'s TV-only
/// focus wiring (`_focusSidebar`, `_focusContent`, `_focusTvNestedRoute`),
/// reproduced verbatim against a real `SidebarFocusCoordinator`, the real
/// `TvRootShell`, and the real `TvMoviesScreen`/`TvUnifiedCatalogScreen`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
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
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/navigation/sidebar_focus_coordinator.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/tv/tv_movies_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_unified_media_grid.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

/// One library that answers immediately, twelve items so the top row really
/// is a row (LEFT from column 0 must be reachable without scrolling first).
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

MediaItem _item(String id, {required String title}) =>
    MediaItem(id: id, backend: MediaBackend.plex, kind: MediaKind.movie, title: title, serverId: 'nas');

/// `MainScreen`'s TV-only focus wiring (hoofdstuk 7.1/7.4/7.6), reproduced
/// against the real [SidebarFocusCoordinator] and [TvContentFocusAuthority]
/// rather than a simplified stand-in — see the file doc for why that
/// distinction is the point of this file.
class _TvHarness extends StatefulWidget {
  const _TvHarness({super.key, required this.coordinator, required this.buildCatalog});

  final TvNavigationCoordinator coordinator;
  final Widget Function(GlobalKey screenKey) buildCatalog;

  @override
  State<_TvHarness> createState() => _TvHarnessState();
}

class _TvHarnessState extends State<_TvHarness> {
  final _focus = SidebarFocusCoordinator();
  final _tvContentFocus = TvContentFocusAuthority();
  final _tvNavNodes = FocusMemoryTracker(debugLabelPrefix: 'tvNav');

  TvNavigationCoordinator get _tvNav => widget.coordinator;

  @override
  void initState() {
    super.initState();
    _focus.addListener(_handleSidebarFocusChanged);
  }

  @override
  void dispose() {
    _focus.removeListener(_handleSidebarFocusChanged);
    _focus.dispose();
    _tvNavNodes.dispose();
    super.dispose();
  }

  void _handleSidebarFocusChanged() {
    if (mounted) setState(() {});
  }

  /// `MainScreen._openTvCompleteCatalog` + the `_focusContent` it calls
  /// implicitly through `_selectTvDestination`'s cold-open path: pushes the
  /// nested route and puts the remote on it, the way pressing "Alle films"
  /// on the landing does.
  void openCatalog(TvDestinationId destination) {
    final screenKey = GlobalKey(debugLabel: 'tvCatalog_${destination.name}');
    _tvNav.activate(destination);
    _tvNav.pushNested(
      destination,
      TvNestedRoute(
        id: 'tvCatalog_${destination.name}',
        screenKey: screenKey,
        builder: (_) => widget.buildCatalog(screenKey),
      ),
    );
    _focusContent(restorePreviousFocus: true);
  }

  /// `MainScreen._focusSidebar`, TV branch only.
  void _focusSidebar() {
    _tvContentFocus.cancel();
    _focus.focusSidebar(
      focusActiveItem: () {
        if (!mounted) return;
        final node = _tvNavNodes.get(_tvNav.focusedDestination.focusKey);
        if (node.canRequestFocus) node.requestFocus();
      },
    );
  }

  /// `MainScreen._focusContent`, TV branch only — the exact mechanism under
  /// test: `SidebarFocusCoordinator.focusContent`'s `restorePreviousFocus`
  /// skips `focusDefault` (and therefore `focusActiveTabIfReady`) whenever the
  /// content scope already remembers a focused descendant.
  void _focusContent({bool restorePreviousFocus = true}) {
    _tvContentFocus.arm(restorePreviousFocus ? TvContentFocusIntent.restore : TvContentFocusIntent.primary);
    _focus.focusContent(
      restorePreviousFocus: restorePreviousFocus,
      focusDefault: () {
        if (!mounted) return;
        if (_tvNav.activeCanPop) {
          _focusTvNestedRoute();
        }
      },
    );
  }

  /// `MainScreen._focusTvNestedRoute`, verbatim.
  void _focusTvNestedRoute() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _tvNav.activeNestedRoute?.surfaceKey.currentState?.focusEntry();
    });
  }

  @override
  Widget build(BuildContext context) => TvRootShell(
    coordinator: _tvNav,
    contentFocus: _tvContentFocus,
    navNodes: _tvNavNodes,
    navFocusScope: _focus.sidebarScope,
    contentFocusScope: _focus.contentScope,
    isNavFocused: _focus.isSidebarFocused,
    profile: null,
    onSelectDestination: (d) {},
    onFocusDestination: _tvNav.activate,
    onFocusContent: _focusContent,
    onFocusNav: _focusSidebar,
    onOpenProfiles: () {},
    onOverlaySheetOpenChanged: (_) {},
    onKeyEvent: (_) => KeyEventResult.ignored,
    selectLibrary: null,
    openSettings: null,
    dismissNestedRoute: ([result]) {},
    child: const SizedBox.shrink(),
  );
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

  String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await tester.pumpAndSettle();
  }

  Future<_TvHarnessState> pump(WidgetTester tester, TvNavigationCoordinator coordinator) async {
    tester.view.physicalSize = const Size(1280, 720);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final client = _FakeLibraryClient('nas', items: [for (var i = 0; i < 12; i++) _item('i$i', title: 'Film $i')]);
    final manager = MultiServerManager()..debugRegisterClientForTesting(client);
    final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
    final libraries = LibrariesProvider()
      ..debugSetLibraries([
        MediaLibrary(
          id: '1',
          backend: MediaBackend.plex,
          title: 'Films',
          kind: MediaKind.movie,
          serverId: 'nas',
          serverName: 'NAS',
        ),
      ]);
    final hidden = HiddenLibrariesProvider();
    final catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hidden);
    addTearDown(() {
      catalogs.dispose();
      hidden.dispose();
      libraries.dispose();
      multiServer.dispose();
    });

    final hostKey = GlobalKey<_TvHarnessState>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MultiProvider(
          providers: [
            ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            Provider<UnifiedCatalogs>.value(value: catalogs),
          ],
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: InputModeTracker(
                child: _TvHarness(
                  key: hostKey,
                  coordinator: coordinator,
                  buildCatalog: (screenKey) => TvMoviesScreen(catalogKey: screenKey),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return hostKey.currentState!;
  }

  testWidgets('DOWN out of the bar lands on the header the first time', (tester) async {
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    addTearDown(coordinator.dispose);

    final host = await pump(tester, coordinator);
    host.openCatalog(TvDestinationId.movies);
    await tester.pumpAndSettle();

    expect(find.byType(TvUnifiedMediaGrid), findsOneWidget, reason: 'sanity: the catalog must have loaded cards');
    expect(focusedLabel(), 'TvCatalogFiltersAction', reason: 'DOWN into a cold catalog should land on the header');
  });

  testWidgets('CAT4: after LEFT exits the grid straight to the bar, DOWN a second time still lands on the header', (
    tester,
  ) async {
    final coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
    addTearDown(coordinator.dispose);

    final host = await pump(tester, coordinator);
    host.openCatalog(TvDestinationId.movies);
    await tester.pumpAndSettle();
    expect(focusedLabel(), 'TvCatalogFiltersAction', reason: 'arrival lands on the header');

    // One DOWN into the grid: the first card, column 0.
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), startsWith('TvUnifiedCard('), reason: 'DOWN from the header enters the grid');

    // LEFT from column 0 exits straight to the bar (`onExitLeft`), the way a
    // viewer walking left off the edge of the first row does — it never
    // passes back through the header.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      'tvNav_${TvDestinationId.movies.name}',
      reason: 'LEFT off the first column hands focus to the bar item for the active destination',
    );

    // The remote is now standing in the bar on the same destination it just
    // left. Pressing DOWN here is `TvRootShell`'s own `onNavigateDown` wiring
    // — the same single press hoofdstuk 7.4 documents as "Down vanaf topnav
    // focust de eerste headeractie", and the same press the first assertion
    // in this file proved lands on the header from a cold catalog.
    await press(tester, LogicalKeyboardKey.arrowDown);

    // The contract `TvRootShell.onFocusContent` documents: "Each
    // destination therefore restores its own position in
    // `focusActiveTabIfReady` ... the catalog to the header action you last
    // used. The card itself is one step further down." A single DOWN out of
    // the bar must land here regardless of which control the viewer used to
    // leave the grid.
    expect(
      focusedLabel(),
      'TvCatalogFiltersAction',
      reason: 'CAT4: DOWN out of the bar must land on the header, never straight back on a grid card.',
    );
  });
}
