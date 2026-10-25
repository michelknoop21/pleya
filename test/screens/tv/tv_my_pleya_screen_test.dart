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
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/libraries_provider.dart';
import 'package:pleya/providers/personal_media_provider.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/providers/now_watching_provider.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
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
      bool showCollections = true,
      bool showPlaylists = true,
      bool showAssistant = true,
      int? watchlistCount,
      int? downloadCount,
    }) => buildTvMyPleyaGroups(
      hasWatchlist: hasWatchlist,
      showAssistant: showAssistant,
      hasSeerr: hasSeerr,
      showDownloads: showDownloads,
      showActivity: showActivity,
      showCollections: showCollections,
      showPlaylists: showPlaylists,
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

    test('Collecties and Afspeellijsten are independent capability-gated entries', () {
      expect(
        sectionsIn(groups()),
        containsAll(<TvMyPleyaSection>[TvMyPleyaSection.collections, TvMyPleyaSection.playlists]),
      );
      expect(sectionsIn(groups(showCollections: false)), isNot(contains(TvMyPleyaSection.collections)));
      expect(sectionsIn(groups(showPlaylists: false)), isNot(contains(TvMyPleyaSection.playlists)));
    });

    test('personal media belongs with the collection, not server management', () {
      final grouped = groups();
      expect(
        grouped.first.tiles.map((tile) => tile.section),
        containsAll(<TvMyPleyaSection>[TvMyPleyaSection.collections, TvMyPleyaSection.playlists]),
      );
      expect(grouped[1].tiles.map((tile) => tile.section), isNot(contains(TvMyPleyaSection.collections)));
    });

    test('a group whose every tile is conditional disappears rather than leaving a heading over nothing', () {
      final bare = groups(
        hasWatchlist: false,
        hasSeerr: false,
        showDownloads: false,
        showCollections: false,
        showPlaylists: false,
      );
      expect(bare.map((group) => group.label), isNot(contains(t.tvMyPleya.groupContent)));
      // Hoofdstuk 33.8: the conditional tiles "vallen weg zonder gat in de
      // groepsstructuur" — the groups that remain are still whole.
      expect(bare.every((group) => group.tiles.isNotEmpty), isTrue);
    });

    test('Mijn Pleya keeps its own two groups whatever is switched off', () {
      // Hoofdstuk 18.3: "Mijn Pleya zelf verdwijnt nooit". Settings, Servers and
      // sign out are only reachable here on TV, so a condition that could empty
      // this screen would be a condition that strands someone.
      final bare = groups(
        hasWatchlist: false,
        hasSeerr: false,
        showDownloads: false,
        showActivity: false,
        showCollections: false,
        showPlaylists: false,
      );
      expect(sectionsIn(bare), containsAll(<TvMyPleyaSection>[TvMyPleyaSection.settings, TvMyPleyaSection.servers]));
    });

    test('a zero count is no count at all', () {
      // A tile reading "0" is a tile that should not carry a count.
      final tiles = groups(watchlistCount: 0, downloadCount: 4).expand((group) => group.tiles);
      expect(tiles.firstWhere((tile) => tile.section == TvMyPleyaSection.watchlist).count, isNull);
      expect(tiles.firstWhere((tile) => tile.section == TvMyPleyaSection.downloads).count, 4);
    });

    test('counts read as subtitles, the way northstar 01 writes them', () {
      List<TvMyPleyaTile> tiles({int? libraries, int? online, int? total}) => buildTvMyPleyaGroups(
        hasWatchlist: false,
        hasSeerr: false,
        showDownloads: false,
        showActivity: false,
        showCollections: true,
        showPlaylists: true,
        collectionCount: 24,
        playlistCount: 1,
        libraryCount: libraries,
        onlineServerCount: online,
        totalServerCount: total,
      ).expand((group) => group.tiles).toList();
      String subtitleOf(List<TvMyPleyaTile> ts, TvMyPleyaSection s) => ts.firstWhere((t) => t.section == s).subtitle;

      final counted = tiles(libraries: 1, online: 2, total: 2);
      expect(subtitleOf(counted, TvMyPleyaSection.libraries), t.myPleya.librariesCount(n: 1));
      expect(subtitleOf(counted, TvMyPleyaSection.servers), t.myPleya.serversOnline(count: '2'));
      expect(subtitleOf(counted, TvMyPleyaSection.collections), t.myPleya.collectionsCount(n: 24));
      expect(subtitleOf(counted, TvMyPleyaSection.playlists), t.myPleya.playlistsCount(n: 1));

      final unknown = tiles(total: 0);
      expect(subtitleOf(unknown, TvMyPleyaSection.libraries), t.myPleya.librariesSubtitle);
      expect(subtitleOf(unknown, TvMyPleyaSection.servers), t.tvMyPleya.noServers);
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

    Future<void> pump(
      WidgetTester tester, {
      bool full = false,
      bool nowWatchingAvailable = false,
      bool personalMediaAvailable = false,
      bool appleTv = true,
      Size size = const Size(1280, 720),
      List<WatchlistEntry>? watchlistEntries,
    }) async {
      TvDetectionService.debugSetAppleTVOverride(appleTv);
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // Hoofdstuk 18.3's conditional tiles, all switched on. Off by default so
      // every existing test in this group keeps the short hub it was written
      // against. `nowWatchingAvailable` is the one PB-7 needs on its own,
      // independent of watchlist/Seerr/Plex, to test the Activiteit tile's
      // predicate in isolation.
      WatchlistProvider? watchlist;
      SeerrProvider? seerr;
      NowWatchingProvider? nowWatching;
      if (full) {
        manager.debugRegisterClientForTesting(OnlinePlexClientDouble('nas', 'NAS'));
        watchlist = StockedWatchlistDouble(railEntries: watchlistEntries ?? const []);
        addTearDown(watchlist.dispose);
        seerr = ConfiguredSeerrDouble();
        addTearDown(seerr.dispose);
      } else if (watchlistEntries != null) {
        watchlist = StockedWatchlistDouble(railEntries: watchlistEntries);
        addTearDown(watchlist.dispose);
      }
      if (full || nowWatchingAvailable) {
        nowWatching = AvailableNowWatchingDouble();
        addTearDown(nowWatching.dispose);
      }
      LibrariesProvider? libraries;
      PersonalMediaProvider? personalMedia;
      if (personalMediaAvailable) {
        manager.debugRegisterClientForTesting(OnlinePlexClientDouble('personal', 'Personal'));
        libraries = LibrariesProvider()
          ..debugSetLibraries(const [
            MediaLibrary(
              id: 'movies',
              backend: MediaBackend.plex,
              title: 'Movies',
              kind: MediaKind.movie,
              serverId: 'personal',
            ),
          ]);
        personalMedia = PersonalMediaProvider(multiServer: servers, libraries: libraries);
        addTearDown(personalMedia.dispose);
        addTearDown(libraries.dispose);
      }

      await tester.pumpWidget(
        TranslationProvider(
          child: MultiProvider(
            providers: [
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              if (personalMedia != null) ChangeNotifierProvider<PersonalMediaProvider>.value(value: personalMedia),
              if (watchlist != null) ChangeNotifierProvider<WatchlistProvider>.value(value: watchlist),
              if (seerr != null) ChangeNotifierProvider<SeerrProvider>.value(value: seerr),
              if (nowWatching != null) ChangeNotifierProvider<NowWatchingProvider>.value(value: nowWatching),
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
      expect(find.text(t.tvMyPleya.groupSources.toUpperCase()), findsOneWidget);
      expect(find.text(t.tvMyPleya.groupPleya.toUpperCase()), findsOneWidget);
    });

    testWidgets('Downloads is not offered on an Apple TV', (tester) async {
      await pump(tester);

      // Hoofdstuk 18.3, and the same predicate `NavigationTab.getVisibleTabs`
      // uses — the tile and the tab cannot disagree about whether the feature
      // exists on this device.
      expect(find.text(t.navigation.downloads), findsNothing);
    });

    // PB-7: an online Plex server is no longer sufficient on its own. Negative
    // control for the predicate this workitem replaces — before this change
    // `OnlinePlexClientDouble` alone was enough to show the tile, and this
    // must be red on the pre-fix code or it proves nothing.
    testWidgets('Activiteit stays hidden with an online Plex server but no Tautulli source', (tester) async {
      manager.debugRegisterClientForTesting(OnlinePlexClientDouble('nas', 'NAS'));
      await pump(tester);

      expect(find.text(t.tvMyPleya.activity), findsNothing);
    });

    // PB-7's other half: capability and data availability decide this, not the
    // presence of a concrete `PlexClient`. Tautulli Now Watching is a valid
    // source on its own.
    testWidgets('Activiteit appears once a Tautulli source is available', (tester) async {
      await pump(tester, nowWatchingAvailable: true);

      expect(find.text(t.tvMyPleya.activity), findsOneWidget);
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

    testWidgets('TOK2: the server dot uses the shared status colour', (tester) async {
      // A dot that is almost kSuccess but not quite is the failure mode TOK-1
      // already had: two greens that look the same until one theme moves.
      await pump(tester, full: true);

      final dot = tester.widget<Container>(find.byKey(const ValueKey('tv.my-pleya.server-dot.nas.online')));
      final decoration = dot.decoration! as BoxDecoration;
      expect(decoration.color, kSuccess);
    });

    testWidgets('TOK2: two online servers each keep their own dot key', (tester) async {
      // The bug this reopened: the key carried only online/offline, so a
      // second online server collided with the first one's dot instead of
      // getting a widget of its own. Two different ids, same display name on
      // purpose, to prove the id is what makes the key unique, not the name.
      manager.debugRegisterClientForTesting(OnlinePlexClientDouble('nas1', 'Server'));
      manager.debugRegisterClientForTesting(OnlinePlexClientDouble('nas2', 'Server'));
      await pump(tester);

      expect(find.byKey(const ValueKey('tv.my-pleya.server-dot.nas1.online')), findsOneWidget);
      expect(find.byKey(const ValueKey('tv.my-pleya.server-dot.nas2.online')), findsOneWidget);
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

    // A-24b, northstar 01: two columns. This harness has no watchlist, no
    // Seerr and no Big P, so the left column is Bibliotheken · Servers · Samen
    // kijken and the right column is Beheer.
    testWidgets('Right from the end of a row crosses to the right column, Left comes back', (tester) async {
      await pump(tester);

      state(tester).focusKey(TvMyPleyaSection.watchTogether.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), TvMyPleyaSection.settings.tileFocusKey, reason: 'the right-column row nearest in height');

      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), TvMyPleyaSection.watchTogether.tileFocusKey, reason: 'the nearest element of the row');
    });

    testWidgets('Left and Right walk a row without wrapping into the next one', (tester) async {
      await pump(tester);

      state(tester).focusKey(TvMyPleyaSection.libraries.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(focusedLabel(), TvMyPleyaSection.libraries.tileFocusKey, reason: 'the first tile is the left edge');

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), TvMyPleyaSection.servers.tileFocusKey);
    });

    testWidgets('Up and Down walk the Beheer column, and Up from its top reaches the profile', (tester) async {
      await pump(tester);

      state(tester).focusKey(TvMyPleyaSection.settings.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), TvMyPleyaSection.logs.tileFocusKey);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), TvMyPleyaSection.about.tileFocusKey);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'tvMyPleya_logout');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), 'tvMyPleya_logout', reason: 'the bottom stays put');

      state(tester).focusKey(TvMyPleyaSection.settings.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'tvMyPleya_switchProfile');
    });

    testWidgets('Down from the bottom row stays put instead of snapping to the last tile', (tester) async {
      await pump(tester);

      state(tester).focusKey(TvMyPleyaSection.servers.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);

      expect(focusedLabel(), TvMyPleyaSection.servers.tileFocusKey);
    });

    // Up/down between rows of different length keep the column by geometry.
    // The full harness: an empty kijklijst (heading and Bekijk alles), Mijn
    // content with Aanvragen alone, then four Bronnen tiles.
    testWidgets('Up and Down between rows of different length keep the nearest column', (tester) async {
      await pump(tester, full: true);

      state(tester).focusKey(TvMyPleyaSection.requests.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), TvMyPleyaSection.libraries.tileFocusKey, reason: 'Aanvragen sits over Bibliotheken');

      state(tester).focusKey(TvMyPleyaSection.activity.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), TvMyPleyaSection.requests.tileFocusKey, reason: 'the only tile of the row above');

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), TvMyPleyaSection.watchlist.tileFocusKey, reason: 'an empty kijklijst keeps Bekijk alles');
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'tvMyPleya_switchProfile');
    });

    testWidgets('four content tiles share one row and the remote keeps their columns', (tester) async {
      await pump(tester, full: true, personalMediaAvailable: true, appleTv: false);

      expect(tester.takeException(), isNull);
      expect(find.text(t.collections.title), findsOneWidget);
      expect(find.text(t.playlists.title), findsOneWidget);

      state(tester).focusKey(TvMyPleyaSection.collections.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), TvMyPleyaSection.playlists.tileFocusKey);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(focusedLabel(), TvMyPleyaSection.servers.tileFocusKey, reason: 'second column over second column');
      expect(tester.takeException(), isNull);
    });

    testWidgets('both personal media tiles activate their own section', (tester) async {
      await pump(tester, personalMediaAvailable: true);

      state(tester).focusKey(TvMyPleyaSection.collections.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);
      expect(opened, [TvMyPleyaSection.collections]);

      state(tester).focusKey(TvMyPleyaSection.playlists.tileFocusKey);
      await tester.pump();
      await press(tester, LogicalKeyboardKey.select);
      expect(opened, [TvMyPleyaSection.collections, TvMyPleyaSection.playlists]);
    });

    // A-24b, northstars 01 and 02: the kijklijst is a poster rail under
    // `Je kijklijst` with `Bekijk alles`, not a tile.
    group('the kijklijst rail', () {
      final entries = [for (var i = 0; i < 8; i++) watchlistEntryDouble('w$i', year: 2020 + i)];

      testWidgets('shows posters with title and year, and no Kijklijst tile', (tester) async {
        await pump(tester, watchlistEntries: entries);

        expect(find.text(t.settingsStudio.yourWatchlist.toUpperCase()), findsOneWidget);
        expect(find.byType(TvCatalogCard), findsWidgets);
        expect(find.text('2020'), findsOneWidget);
        expect(find.text('Title w0'), findsOneWidget);
        expect(find.text(t.watchlist.title), findsNothing, reason: 'the tile became the rail');
        expect(state(tester).availableSections, contains(TvMyPleyaSection.watchlist));
      });

      testWidgets('Down from the profile lands on the first poster, Up goes back', (tester) async {
        await pump(tester, watchlistEntries: entries);

        state(tester).focusKey('tvMyPleya_switchProfile');
        await tester.pump();
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedLabel(), 'tvMyPleya_poster_w0');

        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedLabel(), 'tvMyPleya_poster_w1');
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), 'tvMyPleya_switchProfile');
      });

      testWidgets('Bekijk alles follows the last poster and opens the kijklijst', (tester) async {
        await pump(tester, watchlistEntries: entries.take(3).toList());

        state(tester).focusKey('tvMyPleya_poster_w2');
        await tester.pump();
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(focusedLabel(), TvMyPleyaSection.watchlist.tileFocusKey);

        await press(tester, LogicalKeyboardKey.select);
        expect(opened, [TvMyPleyaSection.watchlist]);
      });

      testWidgets('a title with nothing to play opens the full kijklijst', (tester) async {
        await pump(tester, watchlistEntries: entries);

        state(tester).focusKey('tvMyPleya_poster_w0');
        await tester.pump();
        await press(tester, LogicalKeyboardKey.select);
        expect(opened, [TvMyPleyaSection.watchlist]);
      });

      testWidgets('Down from a poster keeps the column into the tiles below', (tester) async {
        await pump(tester, watchlistEntries: entries);

        state(tester).focusKey('tvMyPleya_poster_w0');
        await tester.pump();
        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedLabel(), TvMyPleyaSection.libraries.tileFocusKey);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), 'tvMyPleya_poster_w0');
      });
    });

    testWidgets('without Big P, Beheer sits directly under Pleya (northstar 04)', (tester) async {
      await pump(tester);

      expect(find.text(t.tvMyPleya.groupPleya.toUpperCase()), findsOneWidget);
      expect(find.text(t.settingsStudio.manage.toUpperCase()), findsNothing);
      expect(find.text(t.tvMyPleya.groupContent.toUpperCase()), findsNothing, reason: 'an empty group disappears');
      final pleya = tester.getRect(find.text(t.tvMyPleya.groupPleya.toUpperCase()));
      final settings = tester.getRect(find.text(t.settings.title));
      expect(settings.top, greaterThan(pleya.bottom));
      expect(settings.left, greaterThan(tester.getRect(find.text(t.myPleya.watchTogether)).right));
    });

    testWidgets('Uitloggen reads in the accent red', (tester) async {
      await pump(tester);

      final logout = tester.widget<Text>(find.text(t.common.logout));
      expect(logout.style?.color, monoTheme(dark: true).extension<MonoTokens>()!.accent);
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
    // VIS-0925-G (DEC-139): at the tvOS logical canvas the full hub now fits.
    // The tiles are about 100 pt instead of 151, which is the point of the
    // targeted densification.
    testWidgets('on the canonical canvas the full hub fits, last tile included', (tester) async {
      await pump(tester, full: true, size: kTvGoldenSurfaceSize);
      final scroller = tester.state<ScrollableState>(find.byType(Scrollable).first);
      expect(scroller.position.maxScrollExtent, 0.0);
      expect(tester.getRect(find.text(t.common.logout)).bottom, lessThanOrEqualTo(kTvGoldenSurfaceSize.height));
    });

    // VIS-0925 review FIX 1: no tile title or subtitle is cut off on the
    // canonical canvas.
    for (final locale in [AppLocale.en, AppLocale.nl]) {
      testWidgets('on the canonical canvas no tile text is ellipsized (${locale.languageCode})', (tester) async {
        await tester.runAsync(() => LocaleSettings.setLocale(locale));
        addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
        // Real Inter metrics: the test font draws every glyph a full em wide.
        await tester.runAsync(loadAppFontsForGoldens);
        await pump(tester, full: true, size: kTvGoldenSurfaceSize);
        final paragraphs = tester.renderObjectList<RenderParagraph>(
          find.descendant(of: find.byType(TvMyPleyaScreen), matching: find.byType(RichText)),
        );
        final cut = [
          for (final p in paragraphs)
            if (p.didExceedMaxLines) p.text.toPlainText(),
        ];
        expect(cut, isEmpty);
      });
    }

    testWidgets('on the full hub the last tile is still reachable, and scrolls into view', (tester) async {
      // A-24b: the Editorial hub fits the tvOS canvas the way northstar 01
      // does, so the overflow comes from larger text (an accessibility text
      // size), and the scroll path it proves has to keep working for it.
      // Real Inter metrics: the test font draws every glyph a full em wide.
      await tester.runAsync(loadAppFontsForGoldens);
      tester.platformDispatcher.textScaleFactorTestValue = 2;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
      const size = Size(1038, 584);
      // An empty kijklijst: the poster rail is the catalogue card's, whose
      // fixed footer is the catalogue's own contract and not this test's.
      await pump(tester, full: true, size: size);

      // The page's own scroller: the first Scrollable in tree order, above
      // the rail's horizontal one.
      ScrollableState scroller() => tester.state<ScrollableState>(find.byType(Scrollable).first);

      // The page really does overflow — otherwise this test proves nothing.
      expect(
        scroller().position.maxScrollExtent,
        greaterThan(0.0),
        reason: 'the full hub must not fit the frame, or this is not the scenario it claims to be',
      );

      // The lowest tile on the page, whichever column it is in.
      final candidates = {
        TvMyPleyaSection.libraries.tileFocusKey: find.text(t.libraries.title),
        'tvMyPleya_logout': find.text(t.common.logout),
      };
      final lowest = candidates.entries.reduce(
        (a, b) => tester.getRect(a.value).bottom >= tester.getRect(b.value).bottom ? a : b,
      );
      expect(tester.getRect(lowest.value).bottom, greaterThan(size.height), reason: 'it starts below the fold');

      final before = scroller().position.pixels;
      state(tester).focusKey(lowest.key);
      await tester.pumpAndSettle();

      expect(focusedLabel(), lowest.key);
      expect(
        scroller().position.pixels,
        greaterThan(before),
        reason: 'focusing a tile below the fold has to bring it into view',
      );
      // And it is genuinely on screen, not merely focused off-screen.
      expect(tester.getRect(lowest.value).bottom, lessThanOrEqualTo(size.height));
    });

    testWidgets('a menu tile announces its title and what it is for', (tester) async {
      final handle = tester.ensureSemantics();
      await pump(tester);

      expect(
        find.bySemanticsLabel(t.tvMyPleya.semantics.tile(title: t.tvMyPleya.servers, subtitle: t.tvMyPleya.noServers)),
        findsOneWidget,
      );
      handle.dispose();
    });

    testWidgets('the server readout is a status line, not a row of focus stops', (tester) async {
      await pump(tester);

      // A remote that has to walk past three servers to reach the first tile is
      // a remote fighting the page. The line reads under the name and again as
      // the Servers tile's subtitle; neither is a focus stop of its own.
      expect(find.text(t.tvMyPleya.noServers), findsNWidgets(2));
      state(tester).focusKey('tvMyPleya_switchProfile');
      await tester.pump();
      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(focusedLabel(), 'tvMyPleya_switchProfile');
    });
  });
}
