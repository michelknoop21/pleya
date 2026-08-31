/// Fase 6 (hoofdstuk 10.2a of docs/tvos-unified-experience.md, hoofdstuk 13
/// "restoration", [DEC-064]): a landing pushed on top of and popped back to
/// must return the viewer to the same tile and the same scroll position.
///
/// This exercises the View All push+pop specifically — a plain
/// `Navigator.push`/`pop` of a screen built by `buildAllScreen` — because that
/// is exactly the mechanism the fase-4 activation path
/// (`tv_discovery_activation_mixin.dart`) also uses to reach a detail screen:
/// both push one route onto this landing's own (nested) `Navigator` and pop
/// it, so proving Flutter's ordinary focus-scope restoration holds for one
/// proves it for the other. Faking the full activation coordinator chain
/// (source resolution, a real detail screen) to test the second path directly
/// would exercise fase-4 code this fase does not own, for no additional
/// coverage of what fase 6 actually changed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/providers/discover_provider.dart';
import 'package:pleya/providers/hidden_libraries_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/tv_discovery_landing_provider.dart';
import 'package:pleya/screens/tv/tv_discovery_landing_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_discovery_rail.dart';
import 'package:pleya/widgets/tv/tv_view_all_action.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

MediaItem _movie(String id, String title) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: 2024,
  serverId: 'server_1',
  serverName: 'Server',
);

class _FakeAggregationService extends DataAggregationService {
  _FakeAggregationService(super.serverManager);

  List<MediaHub> Function() hubsResult = () => const [];

  @override
  Future<OnDeckAggregationResult> getOnDeckFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    Set<String>? serverIds,
  }) async => (items: const <MediaItem>[], succeededServerIds: serverIds ?? const {'server_1'});

  @override
  Future<HubAggregationResult> getHubsFromAllServers({
    int? limit,
    Set<String>? hiddenLibraryKeys,
    bool useGlobalHubs = true,
    bool includePlaybackHubs = true,
    Set<String>? serverIds,
  }) async => (hubs: hubsResult(), succeededServerIds: serverIds ?? const {'server_1'});
}

class _FakeClient implements MediaServerClient {
  @override
  ServerId get serverId => ServerId('server_1');

  @override
  String? get serverName => 'Server';

  @override
  MediaBackend get backend => MediaBackend.plex;

  @override
  ServerCapabilities get capabilities => ServerCapabilities.plex;

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDownAll(() => TvDetectionService.debugSetAppleTVOverride(null));

  testWidgets('a catalog push+pop restores the action focus and the rail\'s remembered tile', (tester) async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    await SettingsService.getInstance();

    final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
    final aggregation = _FakeAggregationService(manager);
    final multiServer = MultiServerProvider(manager, aggregation);
    final hiddenLibraries = HiddenLibrariesProvider();
    final libraries = LibrariesProvider();
    final discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
    addTearDown(discover.dispose);
    addTearDown(libraries.dispose);
    addTearDown(hiddenLibraries.dispose);
    addTearDown(multiServer.dispose);

    aggregation.hubsResult = () => [
      MediaHub(
        id: 'recently-added-movies',
        identifier: 'recently-added-movies',
        title: 'Recently Added',
        type: 'movie',
        items: [_movie('m1', 'Harbourlight'), _movie('m2', 'Quarry Road'), _movie('m3', 'Blue Signal')],
        size: 3,
        serverId: 'server_1',
        serverName: 'Server',
      ),
      // A second rail so the landing's content overflows the viewport —
      // without it there is nothing to scroll and the offset assertion below
      // would pass vacuously at 0 either way.
      MediaHub(
        id: 'top-picks-movies',
        identifier: 'top-picks-movies',
        title: 'Top Picks',
        type: 'movie',
        items: [_movie('m4', 'Arcade Midnight')],
        size: 1,
        serverId: 'server_1',
        serverName: 'Server',
      ),
    ];
    await discover.load();

    final landing = TvDiscoveryLandingProvider(
      discover: discover,
      multiServer: multiServer,
      continueWatchingTitle: 'Continue Watching',
    );
    addTearDown(landing.dispose);
    // A microtask-only yield, not `Future.delayed` — under `testWidgets`'s
    // automated binding a real `Timer` never fires without an explicit
    // `tester.pump()`, so `Future.delayed` here would hang forever rather
    // than let the projection's own (Timer-free) async chain resolve.
    for (var i = 0; i < 50 && landing.isProjecting; i++) {
      await Future<void>.value();
    }
    expect(landing.movieRails, hasLength(2), reason: 'sanity: both movie hubs must have projected');
    // The projection assigns its own `groupId` (hoofdstuk 4.7) — not the raw
    // `MediaItem.id` this fixture used ('m2') — so the middle tile's id has
    // to be read back off the projected row. Found by content rather than
    // position: `DiscoverProvider` reorders hubs (library order, priority)
    // before this provider ever sees them, so which of the two rails ends up
    // first is not this test's contract to pin down.
    final threeItemRail = landing.movieRails.firstWhere((hub) => hub.groups.length == 3);
    final middleGroupId = threeItemRail.groups[1].groupId;

    setGoldenSurfaceSize(tester);
    final theme = monoTheme(dark: true);
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
          ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
          ChangeNotifierProvider<TvDiscoveryLandingProvider>.value(value: landing),
        ],
        child: TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: theme,
            home: InputModeTracker(
              child: Scaffold(
                body: TvDiscoveryLandingScreen(
                  title: t.unifiedCatalog.moviesTitle,
                  allTitle: t.unifiedCatalog.discovery.allMovies,
                  viewAllSemanticLabel: t.unifiedCatalog.discovery.semantics.viewAllMovies,
                  railsOf: (landing) => landing.movieRails,
                  buildAllScreen: () => const Scaffold(body: Center(child: Text('All Movies'))),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    // Focus the middle tile — not the one the rail autofocuses to, so the
    // test cannot pass by accident on a fresh, unfocused rebuild.
    // Found across the mounted rails rather than by key: since DEC-068 the
    // landing keys each rail with a `GlobalKey<TvDiscoveryRailState>` (so DOWN
    // out of the header action can reach the first rail's state), not the
    // `ValueKey(hubId)` this lookup used to match on.
    final railStates = tester.stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail));
    expect(railStates.any((rail) => rail.focusGroup(middleGroupId)), isTrue);
    await tester.pumpAndSettle();
    // `TvDiscoveryRailState._nodeFor` names each tile's `FocusNode`
    // `tvDiscoveryTile_<groupId>` — the primary-focus check goes through
    // `FocusManager` rather than `Focus.of(elementForTheTile)`, since that
    // element is the tile itself and its own `Focus` is a descendant, not an
    // ancestor, of that context.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvDiscoveryTile_$middleGroupId');

    // Back to the top so the page header is mounted again: focusing a tile
    // scrolled the landing down to that rail, and since DEC-068 the catalog
    // action lives in the header, which is content and scrolls with it.
    final scrollable = tester.widget<Scrollable>(find.byType(Scrollable).first);
    final controller = scrollable.controller!;
    controller.jumpTo(0);
    await tester.pumpAndSettle();

    // Focus the catalog action, *then* scroll. Focusing it scrolls the page to
    // reveal it (`FocusableWrapper`'s own ensure-visible), so doing it the
    // other way round would reset the offset and leave the assertion below
    // proving nothing.
    //
    // `TvViewAllAction` is remote-first (DEC-064 punt 3): it runs on a
    // `FocusableWrapper` Select key, not a `GestureDetector`, so it is driven
    // the same way here rather than with `tester.tap`.
    final viewAllAction = tester.widget<TvViewAllAction>(find.byType(TvViewAllAction));
    viewAllAction.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    // Push the catalog, then pop it — the exact push/pop the fase-4 activation
    // path also runs to reach a detail screen.
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('All Movies'), findsOneWidget, reason: 'the action must have pushed the fase-5 catalog screen');

    Navigator.of(tester.element(find.text('All Movies'))).pop();
    await tester.pumpAndSettle();

    // The landing comes back at the top, with the header action in view.
    //
    // Before DEC-068 this test also asserted a non-zero scroll offset survived
    // the round trip. That property is genuinely gone, and not by accident:
    // the launcher now lives in the page header, so restoring focus to it
    // necessarily scrolls the header back into view. Asserting a preserved
    // offset here would mean asserting the restored control stays off-screen.
    final scrollableAfterPop = tester.widget<Scrollable>(find.byType(Scrollable).first);
    expect(scrollableAfterPop.controller!.offset, 0);
    expect(find.byType(TvViewAllAction), findsOneWidget);

    // Flutter's own focus-scope stack put the primary focus back on
    // exactly the control this screen was left from, with no bespoke
    // restoration code involved.
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvDiscoveryViewAll');

    // The rail still remembers the tile the viewer was on before all of that:
    // asking it to restore its own focus lands on the middle tile, not on the
    // first one a fresh rail would autofocus.
    // The rail that holds that tile, not merely the first rail that will
    // restore something — every rail remembers its own tile, so `any` would
    // pass on whichever one happens to come first.
    final railAfterPop = tester
        .stateList<TvDiscoveryRailState>(find.byType(TvDiscoveryRail))
        .firstWhere((rail) => rail.widget.groups.any((g) => g.groupId == middleGroupId));
    expect(railAfterPop.focusCurrent(), isTrue);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'tvDiscoveryTile_$middleGroupId');
  });

  // DEC-068: the complete-catalog action moved from a row at the foot of the
  // page to a compact action beside the page title, and is now the landing's
  // only route into the catalog.
  testWidgets('the catalog action sits beside the page title and is the only one on the page', (tester) async {
    await pumpLanding(tester);

    expect(find.byType(TvViewAllAction), findsOneWidget, reason: 'one launcher, not two');
    expect(find.text('All movies'), findsOneWidget);

    // Beside the title, not at the page edge: the action's left edge is past
    // the title's right edge, and it stops well short of the right margin —
    // the right-aligned variant DEC-068 rejected would sit against it.
    final title = tester.getRect(find.text('Movies'));
    final action = tester.getRect(find.byType(TvViewAllAction));
    final page = tester.getRect(find.byType(TvDiscoveryLandingScreen));
    expect(action.left, greaterThan(title.right), reason: 'the two are separate semantics, not one run of text');
    expect(
      action.left - title.right,
      lessThan(page.width / 3),
      reason: 'a sibling of the title, not a far-right control',
    );
    expect(page.right - action.right, greaterThan(0));

    // And it is above the rails, not below them.
    final rail = tester.getRect(find.byType(TvDiscoveryRail).first);
    expect(action.bottom, lessThanOrEqualTo(rail.top));
  });

  testWidgets('the catalog action is focusable and opens the existing fase-5 catalog', (tester) async {
    await pumpLanding(tester);

    final action = tester.widget<TvViewAllAction>(find.byType(TvViewAllAction));
    action.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvDiscoveryViewAll');

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pumpAndSettle();
    expect(find.text('All Movies'), findsOneWidget, reason: 'the existing complete catalog, not a second screen');
  });

  testWidgets('DOWN from the catalog action reaches the first rail, and UP comes back', (tester) async {
    // The whole point of DEC-068: a short remote path between the header and
    // the content, with no walk through the rails to reach the catalog.
    await pumpLanding(tester);

    final action = tester.widget<TvViewAllAction>(find.byType(TvViewAllAction));
    action.focusNode!.requestFocus();
    await tester.pumpAndSettle();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(
      FocusManager.instance.primaryFocus?.debugLabel,
      startsWith('tvDiscoveryTile_'),
      reason: 'one DOWN lands in the first discovery rail',
    );

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvDiscoveryViewAll', reason: 'and UP comes straight back');
  });

  testWidgets('the landing carries no filter or sort chrome', (tester) async {
    await pumpLanding(tester);

    expect(find.byType(TvCatalogHeaderBar), findsNothing);
  });

  testWidgets('a long locale moves the action out without overlapping or overflowing', (tester) async {
    await pumpLanding(tester, title: 'Films en series die je nog niet gezien hebt', allTitle: 'Alle films bekijken');

    final title = tester.getRect(find.text('Films en series die je nog niet gezien hebt'));
    final action = tester.getRect(find.byType(TvViewAllAction));
    expect(action.left, greaterThanOrEqualTo(title.right), reason: 'no overlap');
    expect(tester.takeException(), isNull, reason: 'and no overflow');
  });
}

/// Mounts the landing with two movie rails, settled — the shape the DEC-068
/// header tests need and the existing restoration test builds inline.
Future<void> pumpLanding(WidgetTester tester, {String? title, String? allTitle}) async {
  resetSharedPreferencesForTest();
  SettingsService.resetForTesting();
  await SettingsService.getInstance();

  final manager = MultiServerManager()..debugRegisterClientForTesting(_FakeClient());
  final aggregation = _FakeAggregationService(manager);
  final multiServer = MultiServerProvider(manager, aggregation);
  final hiddenLibraries = HiddenLibrariesProvider();
  final libraries = LibrariesProvider();
  final discover = DiscoverProvider(multiServer, hiddenLibraries, libraries, isProfileBinding: () => false);
  addTearDown(discover.dispose);
  addTearDown(libraries.dispose);
  addTearDown(hiddenLibraries.dispose);
  addTearDown(multiServer.dispose);

  aggregation.hubsResult = () => [
    MediaHub(
      id: 'recently-added-movies',
      identifier: 'recently-added-movies',
      title: 'Recently Added',
      type: 'movie',
      items: [_movie('m1', 'Harbourlight'), _movie('m2', 'Quarry Road'), _movie('m3', 'Blue Signal')],
      size: 3,
      serverId: 'server_1',
      serverName: 'Server',
    ),
    MediaHub(
      id: 'top-picks-movies',
      identifier: 'top-picks-movies',
      title: 'Top Picks',
      type: 'movie',
      items: [_movie('m4', 'Arcade Midnight')],
      size: 1,
      serverId: 'server_1',
      serverName: 'Server',
    ),
  ];
  await discover.load();

  final landing = TvDiscoveryLandingProvider(
    discover: discover,
    multiServer: multiServer,
    continueWatchingTitle: 'Continue Watching',
  );
  addTearDown(landing.dispose);
  for (var i = 0; i < 50 && landing.isProjecting; i++) {
    await Future<void>.value();
  }

  setGoldenSurfaceSize(tester);
  await tester.pumpWidget(
    MultiProvider(
      providers: [
        ChangeNotifierProvider<MultiServerProvider>.value(value: multiServer),
        ChangeNotifierProvider<DiscoverProvider>.value(value: discover),
        ChangeNotifierProvider<TvDiscoveryLandingProvider>.value(value: landing),
      ],
      child: TranslationProvider(
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: monoTheme(dark: true),
          home: InputModeTracker(
            child: Scaffold(
              body: TvDiscoveryLandingScreen(
                title: title ?? t.unifiedCatalog.moviesTitle,
                allTitle: allTitle ?? t.unifiedCatalog.discovery.allMovies,
                viewAllSemanticLabel: t.unifiedCatalog.discovery.semantics.viewAllMovies,
                railsOf: (landing) => landing.movieRails,
                buildAllScreen: () => const Scaffold(body: Center(child: Text('All Movies'))),
              ),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}
