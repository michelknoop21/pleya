/// Mijn Pleya on TV (hoofdstuk 18, north star 08).
///
/// Two halves, because the screen has two kinds of claim to prove. Which tiles
/// exist is the hoofdstuk 18.2 function mapping, and that is a pure function —
/// tested as one, so a conditional tile can be checked without a server. What
/// the tiles then *do* is a focus and activation contract, and that is tested
/// against the production widget.
///
/// The load-bearing promise of the whole screen is that no tile is decorative:
/// every one of them opens something this app already ships (hoofdstuk 18.2),
/// so the section a tile reports is asserted rather than assumed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/providers/seerr_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:provider/provider.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/tv_my_pleya_conditions.dart';

void main() {
  // ---------------------------------------------------------------------------
  // Which tiles exist (hoofdstuk 18.2 and 18.3)
  // ---------------------------------------------------------------------------

  group('the function mapping', () {
    List<TvMyPleyaGroup> groups({
      bool hasWatchlist = true,
      bool hasSeerr = true,
      bool showDownloads = true,
      bool showActivity = true,
      int? watchlistCount,
      int? downloadCount,
    }) => buildTvMyPleyaGroups(
      hasWatchlist: hasWatchlist,
      hasSeerr: hasSeerr,
      showDownloads: showDownloads,
      showActivity: showActivity,
      watchlistCount: watchlistCount,
      downloadCount: downloadCount,
    );

    List<TvMyPleyaSection?> sectionsIn(List<TvMyPleyaGroup> gs) =>
        gs.expand((group) => group.tiles).map((tile) => tile.section).toList();

    test('the three groups appear in the hoofdstuk 18.1 order', () {
      expect(groups().map((group) => group.label).toList(), [
        t.tvMyPleya.groupContent,
        t.tvMyPleya.groupSources,
        t.tvMyPleya.groupPleya,
      ]);
    });

    test('every section reachable from the hub is one this app already ships', () {
      // The hub's whole promise: no tile without a real screen behind it.
      // `null` is sign out, which acts rather than navigates.
      expect(sectionsIn(groups()).whereType<TvMyPleyaSection>().toSet(), TvMyPleyaSection.values.toSet());
    });

    test('sign out is the one tile that acts instead of opening a section', () {
      final actions = groups().expand((group) => group.tiles).where((tile) => tile.section == null).toList();
      expect(actions, hasLength(1));
      expect(actions.single.title, t.common.logout);
    });

    test('Downloads is absent where the platform has no downloads', () {
      // Hoofdstuk 18.3: Downloads never appears on Apple TV.
      expect(sectionsIn(groups(showDownloads: false)), isNot(contains(TvMyPleyaSection.downloads)));
    });

    test('Requests is absent without Seerr, and Kijklijst without a watchlist', () {
      expect(sectionsIn(groups(hasSeerr: false)), isNot(contains(TvMyPleyaSection.requests)));
      expect(sectionsIn(groups(hasWatchlist: false)), isNot(contains(TvMyPleyaSection.watchlist)));
    });

    test('Activiteit is absent without a Plex source behind it', () {
      expect(sectionsIn(groups(showActivity: false)), isNot(contains(TvMyPleyaSection.activity)));
    });

    test('a group whose every tile is conditional disappears rather than leaving a heading over nothing', () {
      final bare = groups(hasWatchlist: false, hasSeerr: false, showDownloads: false);
      expect(bare.map((group) => group.label), isNot(contains(t.tvMyPleya.groupContent)));
      // Hoofdstuk 33.8: the conditional tiles "vallen weg zonder gat in de
      // groepsstructuur" — the groups that remain are still whole.
      expect(bare.every((group) => group.tiles.isNotEmpty), isTrue);
    });

    test('Mijn Pleya keeps its own two groups whatever is switched off', () {
      // Hoofdstuk 18.3: "Mijn Pleya zelf verdwijnt nooit". Settings, Servers and
      // sign out are only reachable here on TV, so a condition that could empty
      // this screen would be a condition that strands someone.
      final bare = groups(hasWatchlist: false, hasSeerr: false, showDownloads: false, showActivity: false);
      expect(sectionsIn(bare), containsAll(<TvMyPleyaSection>[TvMyPleyaSection.settings, TvMyPleyaSection.servers]));
    });

    test('a zero count is no count at all', () {
      // A tile reading "0" is a tile that should not carry a count.
      final tiles = groups(watchlistCount: 0, downloadCount: 4).expand((group) => group.tiles);
      expect(tiles.firstWhere((tile) => tile.section == TvMyPleyaSection.watchlist).count, isNull);
      expect(tiles.firstWhere((tile) => tile.section == TvMyPleyaSection.downloads).count, 4);
    });

    test('every tile carries a title and a subtitle, and a focus key of its own', () {
      final tiles = groups().expand((group) => group.tiles).toList();
      expect(tiles.every((tile) => tile.title.isNotEmpty && tile.subtitle.isNotEmpty), isTrue);
      expect(tiles.map((tile) => tile.focusKey).toSet(), hasLength(tiles.length));
    });
  });

  // ---------------------------------------------------------------------------
  // The screen itself
  // ---------------------------------------------------------------------------

  group('the hub', () {
    late MultiServerManager manager;
    late MultiServerProvider servers;
    late List<TvMyPleyaSection> opened;
    late int upCalls;
    late int switchProfileCalls;
    late int signOutCalls;

    setUp(() {
      TvDetectionService.debugSetAppleTVOverride(true);
      manager = MultiServerManager();
      servers = MultiServerProvider(manager, DataAggregationService(manager));
      opened = [];
      upCalls = 0;
      switchProfileCalls = 0;
      signOutCalls = 0;
    });

    tearDown(() {
      servers.dispose();
      TvDetectionService.debugSetAppleTVOverride(null);
    });

    Future<void> pump(WidgetTester tester, {bool full = false, Size size = const Size(1280, 720)}) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Hoofdstuk 18.3's conditional tiles, all switched on. Off by default so
      // every existing test in this group keeps the short hub it was written
      // against.
      WatchlistProvider? watchlist;
      SeerrProvider? seerr;
      if (full) {
        manager.debugRegisterClientForTesting(OnlinePlexClientDouble('nas', 'NAS'));
        watchlist = StockedWatchlistDouble();
        addTearDown(watchlist.dispose);
        seerr = ConfiguredSeerrDouble();
        addTearDown(seerr.dispose);
      }

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              if (watchlist != null) ChangeNotifierProvider<WatchlistProvider>.value(value: watchlist),
              if (seerr != null) ChangeNotifierProvider<SeerrProvider>.value(value: seerr),
            ],
            child: MaterialApp(
              debugShowCheckedModeBanner: false,
              theme: monoTheme(dark: true),
              home: InputModeTracker(
                child: Scaffold(
                  body: TvMyPleyaScreen(
                    onOpenSection: opened.add,
                    onSwitchProfile: () => switchProfileCalls++,
                    onSignOut: () => signOutCalls++,
                    onExitUp: () => upCalls++,
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    TvMyPleyaScreenState state(WidgetTester tester) => tester.state<TvMyPleyaScreenState>(find.byType(TvMyPleyaScreen));

    String? focusedLabel() => FocusManager.instance.primaryFocus?.debugLabel;

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
    }

    testWidgets('the page names itself and shows every group heading', (tester) async {
      await pump(tester);

      expect(find.text(t.navigation.myPleya), findsOneWidget);
      expect(find.text(t.tvMyPleya.groupSources), findsOneWidget);
      expect(find.text(t.tvMyPleya.groupPleya), findsOneWidget);
    });

    testWidgets('Downloads is not offered on an Apple TV', (tester) async {
      await pump(tester);

      // Hoofdstuk 18.3, and the same predicate `NavigationTab.getVisibleTabs`
      // uses — the tile and the tab cannot disagree about whether the feature
      // exists on this device.
      expect(find.text(t.navigation.downloads), findsNothing);
    });

    testWidgets('a tile opens its own section and nothing else', (tester) async {
      await pump(tester);

      state(tester).focusKey(TvMyPleyaSection.settings.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);

      expect(opened, [TvMyPleyaSection.settings]);
      expect(signOutCalls, 0);
    });

    testWidgets('sign out signs out instead of opening a section', (tester) async {
      await pump(tester);

      state(tester).focusKey('tvMyPleya_logout');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);

      expect(signOutCalls, 1);
      expect(opened, isEmpty);
    });

    testWidgets('the profile action switches profile', (tester) async {
      await pump(tester);

      state(tester).focusKey('tvMyPleya_switchProfile');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);

      expect(switchProfileCalls, 1);
    });

    testWidgets('Down from the top navigation lands on the profile action', (tester) async {
      await pump(tester);

      // Hoofdstuk 7.1: "Top navigation → page header → first content row".
      state(tester).focusActiveTabIfReady();
      await tester.pump();

      expect(focusedLabel(), 'tvMyPleya_switchProfile');
    });

    testWidgets('coming back to Mijn Pleya returns to where the remote was', (tester) async {
      await pump(tester);

      state(tester).focusKey(TvMyPleyaSection.servers.tileFocusKey);
      await tester.pump();

      // Leave, then come back the way the shell does.
      state(tester).focusActiveTabIfReady();
      await tester.pump();

      expect(focusedLabel(), TvMyPleyaSection.servers.tileFocusKey, reason: 'hoofdstuk 7.6 focus memory');
    });

    testWidgets('Up from the first row leaves for the top navigation', (tester) async {
      await pump(tester);

      state(tester).focusKey('tvMyPleya_switchProfile');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowUp);

      // Hoofdstuk 7.5 step 4: the top of the content hands the focus to the bar.
      expect(upCalls, 1);
    });

    testWidgets('Left and Right walk the page order across a group boundary', (tester) async {
      await pump(tester);

      // This harness has no watchlist, no Seerr, no downloads and no Plex
      // source, so the rendered hub is exactly Bibliotheken · Servers · Watch
      // Together, then the Pleya group — which makes Watch Together the last
      // tile before a group boundary (fase 8 added it, see
      // `TvMyPleyaSection.watchTogether`). The walk has to cross the boundary
      // rather than dead-end mid-page.
      state(tester).focusKey(TvMyPleyaSection.watchTogether.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);

      expect(focusedLabel(), TvMyPleyaSection.settings.tileFocusKey);

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), TvMyPleyaSection.watchTogether.tileFocusKey);
    });

    // Hoofdstuk 18.3 allows every conditional tile at once, and that page is
    // taller than the frame — `tv_shell_my_pleya_full.png` pictures it running
    // off the bottom. Every test above it runs the short hub, which fits, so
    // nothing until now walked a hub that scrolls.
    //
    // The risk that introduces is hoofdstuk 32's: a function that moved out of
    // the sidebar into Mijn Pleya has to stay reachable. A tile below the fold
    // that the remote cannot bring into view is exactly that function going
    // missing, and it would not show up in a picture of the first frame.
    testWidgets('on the full hub the last tile is still reachable, and scrolls into view', (tester) async {
      // The tvOS logical canvas (DEC-028), which is what an Apple TV actually
      // renders and what `tv_shell_my_pleya_full.png` is captured at. At this
      // group's default 1280x720 the full hub still fits, so the scenario only
      // exists at the real size.
      await pump(tester, full: true, size: kTvGoldenSurfaceSize);

      ScrollableState scroller() => tester.state<ScrollableState>(find.byType(Scrollable).first);

      // The page really does overflow — otherwise this test proves nothing.
      expect(
        scroller().position.maxScrollExtent,
        greaterThan(0.0),
        reason: 'the full hub must not fit the frame, or this is not the scenario it claims to be',
      );

      final before = scroller().position.pixels;
      state(tester).focusKey('tvMyPleya_logout');
      await tester.pumpAndSettle();

      expect(focusedLabel(), 'tvMyPleya_logout');
      expect(
        scroller().position.pixels,
        greaterThan(before),
        reason: 'focusing a tile below the fold has to bring it into view',
      );
      // And it is genuinely on screen, not merely focused off-screen.
      expect(tester.getRect(find.text(t.common.logout)).bottom, lessThanOrEqualTo(kTvGoldenSurfaceSize.height));
    });

    testWidgets('a menu tile announces its title and what it is for', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel(
          t.tvMyPleya.semantics.tile(title: t.tvMyPleya.servers, subtitle: t.tvMyPleya.serversSubtitle),
        ),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the server readout is a status line, not a row of focus stops', (tester) async {
      await pump(tester);

      // A remote that has to walk past three servers to reach the first tile is
      // a remote fighting the page.
      expect(find.text(t.tvMyPleya.noServers), findsOneWidget);
    });
  });
}
