/// Mijn Pleya ▸ Bibliotheken on TV, as bronbeheer instead of a second
/// browsing screen (LIB7, DEC-092).
///
/// Two halves, the same split `tv_my_pleya_screen_test.dart` uses. Which
/// actions a library row offers is a pure function, tested as one. What the
/// screen actually shows is DEC-092's own negative control: no Aanbevolen or
/// Bladeren tab exists at all, and every catalogable library row can reach
/// "Openen in catalogus" — this was never true of the shared `LibrariesScreen`
/// this replaces on TV, which drew exactly those two tabs.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/unified_catalogs.dart';
import 'package:pleya/screens/tv/sections/tv_libraries_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/storage_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_panel_primitives.dart';
import 'package:pleya/widgets/tv/tv_cinema_libraries.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/prefs.dart';

MediaLibrary _lib(
  String id, {
  required ServerId serverId,
  String? serverName,
  MediaKind kind = MediaKind.movie,
  MediaBackend backend = MediaBackend.plex,
  String title = 'L',
}) => MediaLibrary(id: id, backend: backend, title: title, kind: kind, serverId: serverId, serverName: serverName);

void main() {
  // ---------------------------------------------------------------------------
  // Which actions a row offers (mockup 27 B)
  // ---------------------------------------------------------------------------

  group('tvLibraryActionsFor', () {
    test('missing server identity never grants maintenance even with an affirmative caller', () {
      const library = MediaLibrary(id: 'missing', backend: MediaBackend.plex, title: 'Missing', kind: MediaKind.movie);
      expect(tvLibraryActionsFor(library, canManage: true), [
        TvLibraryAction.openInCatalog,
        TvLibraryAction.toggleVisibility,
      ]);
    });

    test('a Plex movie library gets the full set, in mockup order', () {
      final actions = tvLibraryActionsFor(_lib('1', serverId: ServerId('s')), canManage: true);
      expect(actions, [
        TvLibraryAction.openInCatalog,
        TvLibraryAction.refreshMetadata,
        TvLibraryAction.scan,
        TvLibraryAction.toggleVisibility,
        TvLibraryAction.analyze,
        TvLibraryAction.emptyTrash,
      ]);
    });

    test('a Jellyfin show library skips the Plex-only admin actions', () {
      final actions = tvLibraryActionsFor(
        _lib('1', serverId: ServerId('s'), kind: MediaKind.show, backend: MediaBackend.jellyfin),
        canManage: true,
      );
      expect(actions, [
        TvLibraryAction.openInCatalog,
        TvLibraryAction.refreshMetadata,
        TvLibraryAction.toggleVisibility,
      ]);
    });

    test('a music library has no catalog to open', () {
      final actions = tvLibraryActionsFor(_lib('1', serverId: ServerId('s'), kind: MediaKind.artist), canManage: true);
      expect(actions, isNot(contains(TvLibraryAction.openInCatalog)));
    });

    test('without owner rights only the profile actions remain, on every backend', () {
      for (final backend in MediaBackend.values) {
        expect(tvLibraryActionsFor(_lib('1', serverId: ServerId('s'), backend: backend), canManage: false), [
          TvLibraryAction.openInCatalog,
          TvLibraryAction.toggleVisibility,
        ]);
      }
    });

    test('every library can still be shown or hidden, regardless of kind', () {
      for (final kind in MediaKind.values) {
        for (final canManage in [true, false]) {
          expect(
            tvLibraryActionsFor(
              _lib('1', serverId: ServerId('s'), kind: kind),
              canManage: canManage,
            ),
            contains(TvLibraryAction.toggleVisibility),
          );
        }
      }
    });
  });

  // ---------------------------------------------------------------------------
  // The screen itself
  // ---------------------------------------------------------------------------

  group('the bronbeheer screen', () {
    late LibrariesProvider libraries;
    late HiddenLibrariesProvider hidden;

    setUp(() {
      resetSharedPreferencesForTest();
    });

    tearDown(() {
      libraries.dispose();
      hidden.dispose();
    });

    Future<void> pump(
      WidgetTester tester,
      List<MediaLibrary> fixture, {
      Size size = const Size(1280, 720),
      MultiServerProvider? multiServer,
    }) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Everything storage-backed runs inside one real async zone, and the
      // singleton is resolved *before* anything else can race it.
      // `BaseSharedPreferencesService.initializeInstance` registers its
      // instance in `_instances` before awaiting `sharedCache()` — so two
      // first-time callers racing for the same singleton (here:
      // `HiddenLibrariesProvider`'s constructor kicking off its own
      // storage-backed init, concurrently with `updateLibraryOrder`'s own
      // `StorageService.getInstance()`) can have the second one see the
      // instance already registered and return it before its `_cache` is
      // actually assigned — a `LateInitializationError` on first synchronous
      // read. Resolving the singleton once, sequentially, first, closes that
      // window.
      await tester.runAsync(() async {
        await StorageService.getInstance();
        libraries = LibrariesProvider();
        hidden = HiddenLibrariesProvider();
        await libraries.updateLibraryOrder(fixture);
      });

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
              if (multiServer != null) ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: const InputModeTracker(child: Scaffold(body: TvLibrariesScreen())),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    TvLibrariesScreenState state(WidgetTester tester) =>
        tester.state<TvLibrariesScreenState>(find.byType(TvLibrariesScreen));

    Future<void> selectRow(WidgetTester tester, String libraryGlobalKey) async {
      state(tester).loadLibraryByKey(libraryGlobalKey);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    /// `TvPanelButton` is D-pad only — no `GestureDetector`, so `tester.tap`
    /// never reaches its `onPressed`. This is the same "find the node, focus
    /// it, press Select" shape as `tv_my_pleya_screen_test.dart`'s `press`
    /// helper, just reading the node off the button widget itself rather than
    /// off a `FocusMemoryTracker` key.
    Future<void> pressPanelButton(WidgetTester tester, String label) async {
      final button = tester.widget<TvPanelButton>(find.widgetWithText(TvPanelButton, label));
      button.focusNode!.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    final movie = _lib('m1', serverId: ServerId('srv'), serverName: 'Pleya', title: 'Films');
    final show = _lib('s1', serverId: ServerId('srv'), serverName: 'Pleya', kind: MediaKind.show, title: 'Series');
    final music = _lib('a1', serverId: ServerId('srv'), serverName: 'Pleya', kind: MediaKind.artist, title: 'Concert');

    testWidgets('draws no Aanbevolen or Bladeren tab — DEC-092 negative control', (tester) async {
      await pump(tester, [movie, show]);

      // The shared `LibrariesScreen` this replaces on TV always drew these two
      // tabs; this screen has no tab bar at all.
      expect(find.text(t.libraries.tabs.recommended), findsNothing);
      expect(find.text(t.libraries.tabs.browse), findsNothing);
      expect(find.text(t.libraries.tabs.collections), findsNothing);
      expect(find.text(t.libraries.tabs.playlists), findsNothing);
    });

    testWidgets('every row shows its title, grouped under its server', (tester) async {
      await pump(tester, [movie, show]);

      expect(find.text('Films'), findsNWidgets(2));
      expect(find.text('Series'), findsOneWidget);
      expect(find.text('PLEYA'), findsOneWidget);
    });

    testWidgets('a movie row opens the sheet with "Openen in Alle films"', (tester) async {
      await pump(tester, [movie, show]);

      await selectRow(tester, movie.globalKey);

      expect(find.text(t.libraries.openInAllMovies), findsOneWidget);
      expect(find.text(t.libraries.hideLibrary), findsOneWidget);
    });

    testWidgets('a show row opens the sheet with "Openen in Alle series"', (tester) async {
      await pump(tester, [movie, show]);

      await selectRow(tester, show.globalKey);

      expect(find.text(t.libraries.openInAllSeries), findsOneWidget);
    });

    MultiServerProvider authorityProvider({required bool canManage}) {
      final manager = _AuthorityManager()..canManage = canManage;
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(() {
        provider.dispose();
        manager.dispose();
      });
      return provider;
    }

    testWidgets('a non-owner sees no library maintenance in the sheet', (tester) async {
      await pump(tester, [movie, show], multiServer: authorityProvider(canManage: false));

      await selectRow(tester, movie.globalKey);

      expect(find.text(t.libraries.openInAllMovies), findsOneWidget);
      expect(find.text(t.libraries.hideLibrary), findsOneWidget);
      expect(find.text(t.libraries.refreshMetadata), findsNothing);
      expect(find.text(t.libraries.scanLibraryFiles), findsNothing);
      expect(find.text(t.libraries.analyze), findsNothing);
      expect(find.text(t.libraries.emptyTrash), findsNothing);
    });

    testWidgets('the owner sees library maintenance in the sheet', (tester) async {
      await pump(tester, [movie, show], multiServer: authorityProvider(canManage: true));

      await selectRow(tester, movie.globalKey);

      expect(find.text(t.libraries.refreshMetadata), findsOneWidget);
      expect(find.text(t.libraries.scanLibraryFiles), findsOneWidget);
    });

    testWidgets('a music row has no catalog action — nothing to browse it with', (tester) async {
      await pump(tester, [movie, music]);

      await selectRow(tester, music.globalKey);

      expect(find.text(t.libraries.openInAllMovies), findsNothing);
      expect(find.text(t.libraries.openInAllSeries), findsNothing);
      expect(find.text(t.libraries.hideLibrary), findsOneWidget);
    });

    testWidgets('Ordenen opens reorder mode, Klaar returns to the list', (tester) async {
      await pump(tester, [movie, show]);

      expect(find.text(t.libraries.reorder), findsOneWidget);
      await pressPanelButton(tester, t.libraries.reorder);

      expect(find.text(t.libraries.reorderIntro), findsOneWidget);
      expect(find.text(t.unifiedCatalog.homeRows.done), findsOneWidget);

      await pressPanelButton(tester, t.unifiedCatalog.homeRows.done);

      expect(find.text(t.libraries.reorderIntro), findsNothing);
      expect(find.text('Films'), findsNWidgets(2));
    });

    testWidgets('DOWN from Klaar reaches the first reorder row', (tester) async {
      await pump(tester, [movie, show]);

      await pressPanelButton(tester, t.libraries.reorder);
      final button = tester.widget<TvPanelButton>(find.widgetWithText(TvPanelButton, t.unifiedCatalog.homeRows.done));
      button.focusNode!.requestFocus();
      await tester.pump();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();

      expect(FocusManager.instance.primaryFocus?.debugLabel, movie.globalKey);
    });

    testWidgets('Cinema selection has a separate summary that follows focus without opening an action', (tester) async {
      await pump(tester, [movie, show]);
      state(tester).loadLibraryByKey(movie.globalKey);
      await tester.pumpAndSettle();
      expect(find.text('Films'), findsNWidgets(2));
      final filmRects = tester.getTopLeft(find.text('Films').first).dx;
      expect(tester.getTopLeft(find.text('Films').last).dx, greaterThan(filmRects + 200));
      state(tester).loadLibraryByKey(show.globalKey);
      await tester.pumpAndSettle();
      expect(find.text('Series'), findsNWidgets(2));
      expect(
        find.text(t.libraries.openInAllSeries),
        findsNothing,
        reason: 'focus only selects the summary; Select opens the existing sheet',
      );
    });

    testWidgets('empty list entry focuses the mounted refresh recovery action', (tester) async {
      await pump(tester, []);
      state(tester).focusActiveTabIfReady();
      await tester.pump();
      expect(find.widgetWithText(TvPanelButton, t.libraries.refreshAllLibraries), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvLibraries.refreshAll');
    });

    testWidgets('removing a picked library releases move mode instead of picking its replacement', (tester) async {
      await pump(tester, [movie, show, music]);
      await pressPanelButton(tester, t.libraries.reorder);
      await selectRow(tester, show.globalKey);
      expect(
        tester
            .widgetList<TvCinemaLibraryRow>(find.byType(TvCinemaLibraryRow))
            .where((row) => row.moving)
            .single
            .library
            .title,
        'Series',
      );
      libraries.debugSetLibraries([movie, music]);
      await tester.pumpAndSettle();
      expect(
        tester.widgetList<TvCinemaLibraryRow>(find.byType(TvCinemaLibraryRow)).where((row) => row.moving),
        isEmpty,
      );
    });

    testWidgets('external insertion preserves the picked identity rather than its old index', (tester) async {
      await pump(tester, [movie, show]);
      await pressPanelButton(tester, t.libraries.reorder);
      await selectRow(tester, show.globalKey);
      libraries.debugSetLibraries([music, movie, show]);
      await tester.pumpAndSettle();
      expect(
        tester
            .widgetList<TvCinemaLibraryRow>(find.byType(TvCinemaLibraryRow))
            .where((row) => row.moving)
            .single
            .library
            .title,
        'Series',
      );
    });

    testWidgets('same-name servers keep distinct contiguous order and cannot move across groups', (tester) async {
      final other = _lib('other', serverId: ServerId('other'), serverName: 'Pleya', title: 'Other');
      await pump(tester, [movie, other, show]);
      await pressPanelButton(tester, t.libraries.reorder);
      expect(
        tester.widgetList<TvCinemaLibraryRow>(find.byType(TvCinemaLibraryRow)).map((row) => row.library.globalKey),
        [movie.globalKey, show.globalKey, other.globalKey],
      );
      await selectRow(tester, show.globalKey);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(
        libraries.libraries.map((library) => library.globalKey),
        [movie.globalKey, other.globalKey, show.globalKey],
        reason: 'blocked move must not persist a cross-server order',
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(libraries.libraries.map((library) => library.globalKey), [
        show.globalKey,
        movie.globalKey,
        other.globalKey,
      ]);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(t.unifiedCatalog.homeRows.done), findsNothing);
      expect(
        libraries.libraries.first.globalKey,
        show.globalKey,
        reason: 'Back closes; existing immediate persistence is retained',
      );
    });

    testWidgets('maintenance authority is checked for the selected server only', (tester) async {
      final manager = _AuthorityManager()..managedServers = {'other'};
      final provider = MultiServerProvider(manager, DataAggregationService(manager));
      addTearDown(provider.dispose);
      await pump(tester, [movie, show], multiServer: provider);
      await selectRow(tester, movie.globalKey);
      expect(find.text(t.libraries.refreshMetadata), findsNothing);
      expect(find.text(t.libraries.scanLibraryFiles), findsNothing);
      expect(find.text(t.libraries.hideLibrary), findsOneWidget);
    });

    testWidgets('losing the last focused library recovers to mounted refresh', (tester) async {
      await pump(tester, [movie]);
      state(tester).loadLibraryByKey(movie.globalKey);
      await tester.pumpAndSettle();
      libraries.debugSetLibraries([]);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvLibraries.refreshAll');
      expect(find.byType(TvCinemaLibrarySummary), findsNothing);
    });

    testWidgets('dense libraries with long titles remain reachable and hidden summary follows profile state', (
      tester,
    ) async {
      final dense = [
        for (var i = 0; i < 9; i++)
          _lib(
            'dense$i',
            serverId: ServerId('server${i ~/ 3}'),
            serverName: 'Server ${i ~/ 3}',
            title: i == 8 ? 'Een bijzonder lange bibliotheektitel die ook volledig bedienbaar blijft' : 'Library $i',
          ),
      ];
      await pump(tester, dense);
      state(tester).focusActiveTabIfReady();
      await tester.pumpAndSettle();
      for (var i = 1; i < dense.length; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      expect(FocusManager.instance.primaryFocus?.debugLabel, dense.last.globalKey);
      final row = tester.widget<TvCinemaLibraryRow>(find.byKey(ValueKey(dense.last.globalKey)).last);
      expect(row.hidden, isFalse);
      await tester.runAsync(() => hidden.hideLibrary(dense.last.globalKey));
      await tester.pumpAndSettle();
      expect(tester.widget<TvCinemaLibrarySummary>(find.byType(TvCinemaLibrarySummary)).hidden, isTrue);
      expect(FocusManager.instance.primaryFocus?.debugLabel, dense.last.globalKey);
      await tester.runAsync(() => hidden.unhideLibrary(dense.last.globalKey));
      await tester.pumpAndSettle();
      expect(tester.widget<TvCinemaLibrarySummary>(find.byType(TvCinemaLibrarySummary)).hidden, isFalse);
      expect(tester.takeException(), isNull);
    });

    testWidgets('Menu on Klaar closes only reorder mode', (tester) async {
      await pump(tester, [movie, show]);
      await pressPanelButton(tester, t.libraries.reorder);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvLibraries.reorder');
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();
      expect(find.text(t.unifiedCatalog.homeRows.done), findsNothing);
      expect(find.widgetWithText(TvPanelButton, t.libraries.reorder), findsOneWidget);
      expect(find.byType(TvLibrariesScreen), findsOneWidget);
    });

    testWidgets('removing a deeply scrolled focused row restores a mounted first row', (tester) async {
      final many = [
        for (var i = 0; i < 40; i++)
          _lib('many$i', serverId: ServerId('srv'), serverName: 'Pleya', title: 'Deep library $i'),
      ];
      await pump(tester, many);
      await tester.scrollUntilVisible(find.text(many.last.title), 200, scrollable: find.byType(Scrollable).first);
      state(tester).loadLibraryByKey(many.last.globalKey);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, many.last.globalKey);
      libraries.debugSetLibraries(many.sublist(0, many.length - 1));
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, many.first.globalKey);
      expect(FocusManager.instance.primaryFocus?.context, isNotNull);
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      expect(FocusManager.instance.primaryFocus?.debugLabel, many[1].globalKey);
    });

    testWidgets('Apple TV Menu down and release both belong to the reorder dismissal', (tester) async {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
      await pump(tester, [movie, show]);
      await pressPanelButton(tester, t.libraries.reorder);
      expect(await tester.sendKeyDownEvent(LogicalKeyboardKey.escape), isTrue);
      await tester.pumpAndSettle();
      expect(find.text(t.unifiedCatalog.homeRows.done), findsNothing);
      expect(
        await tester.sendKeyUpEvent(LogicalKeyboardKey.escape),
        isTrue,
        reason: 'release cannot pop the surrounding native route',
      );
      await tester.pumpAndSettle();
      expect(find.byType(TvLibrariesScreen), findsOneWidget);
    });

    testWidgets('a single library offers no Ordenen — nothing to reorder', (tester) async {
      await pump(tester, [movie]);

      expect(find.text(t.libraries.reorder), findsNothing);
    });
  });

  // ---------------------------------------------------------------------------
  // SYS-1d: the catalog opener stays inside the TV shell
  // ---------------------------------------------------------------------------

  group('SYS-1d: opening the catalog from a library keeps the TV shell mounted', () {
    late LibrariesProvider libraries;
    late HiddenLibrariesProvider hidden;
    late TvNavigationCoordinator coordinator;
    late FocusMemoryTracker navNodes;
    late FocusScopeNode navScope;
    late FocusScopeNode contentScope;

    final movie = _lib('m1', serverId: ServerId('srv'), serverName: 'Pleya', title: 'Films');

    setUp(() {
      resetSharedPreferencesForTest();
      coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
      navNodes = FocusMemoryTracker(debugLabelPrefix: 'sys1dNav');
      navScope = FocusScopeNode(debugLabel: 'nav');
      contentScope = FocusScopeNode(debugLabel: 'content');
    });

    tearDown(() {
      libraries.dispose();
      hidden.dispose();
      coordinator.dispose();
      navNodes.dispose();
      navScope.dispose();
      contentScope.dispose();
    });

    // What `main_screen.dart`'s `_pushTvContentRoute` does once attached: open
    // the route inside the destination that is already active.
    Future<Object?> pushViaRegistry(TvNestedRoute route) {
      final destination = coordinator.active;
      return coordinator.pushNested(destination, route).result;
    }

    Future<void> pumpInShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await tester.runAsync(() async {
        await StorageService.getInstance();
        libraries = LibrariesProvider();
        hidden = HiddenLibrariesProvider();
        await libraries.updateLibraryOrder([movie]);
      });

      final manager = MultiServerManager();
      final multiServer = MultiServerProvider(manager, DataAggregationService(manager));
      final catalogs = UnifiedCatalogs(multiServer: multiServer, libraries: libraries, hiddenLibraries: hidden);
      addTearDown(catalogs.dispose);
      addTearDown(multiServer.dispose);

      tvContentRouteRegistry.attach(pushViaRegistry);
      addTearDown(() => tvContentRouteRegistry.detach(pushViaRegistry));

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<LibrariesProvider>.value(value: libraries),
              ChangeNotifierProvider<HiddenLibrariesProvider>.value(value: hidden),
              ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
              Provider<UnifiedCatalogs>.value(value: catalogs),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: InputModeTracker(
                child: TvRootShell(
                  coordinator: coordinator,
                  contentFocus: TvContentFocusAuthority(),
                  navNodes: navNodes,
                  navFocusScope: navScope,
                  contentFocusScope: contentScope,
                  isNavFocused: false,
                  profile: null,
                  onSelectDestination: (_) {},
                  onFocusDestination: coordinator.focusDestination,
                  onFocusContent: ({bool restorePreviousFocus = true}) {},
                  onFocusNav: () {},
                  onOpenProfiles: () {},
                  onOverlaySheetOpenChanged: (_) {},
                  onKeyEvent: (_) => KeyEventResult.ignored,
                  selectLibrary: null,
                  openSettings: null,
                  dismissNestedRoute: ([_]) {},
                  child: const TvLibrariesScreen(),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    /// `TvCatalogOptionRow` is `FocusableWrapper`-based, not a
    /// `GestureDetector` — same "find it, focus it, press Select" shape the
    /// rest of this file already uses for `TvPanelButton`.
    Future<void> activateByLabel(WidgetTester tester, String label) async {
      final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    testWidgets('opening the catalog from Libraries keeps the TV shell mounted', (tester) async {
      await pumpInShell(tester);

      tester.state<TvLibrariesScreenState>(find.byType(TvLibrariesScreen)).loadLibraryByKey(movie.globalKey);
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      await activateByLabel(tester, t.libraries.openInAllMovies);

      // Hoofdstuk 33's shared shell is binding on all eight references; a
      // kale Navigator.push draws a new route over TvRootShell entirely and
      // takes the bar with it, which is exactly SYS-1's symptom.
      expect(find.byType(TvTopNavigation), findsOneWidget);
    });
  });
}

class _AuthorityManager extends MultiServerManager {
  bool canManage = false;
  Set<String>? managedServers;

  @override
  bool canManageServerMetadata(ServerId serverId) => managedServers?.contains(serverId) ?? canManage;
}
