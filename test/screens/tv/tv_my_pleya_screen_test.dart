/// Mijn Pleya on TV (A-24c, northstar `02-Mijn-Pleya-v4`, `pariteit-v4.csv`).
///
/// Three parts. The groups the iPhone page still reads ([buildTvMyPleyaGroups])
/// and the TV dock ([buildTvMyPleyaDock]) are pure functions, tested as such,
/// so a conditional tile can be checked without a server. What the page then
/// *does* is a focus, activation and canvas contract, tested against the
/// production page under the production shell at 1038 x 584
/// (`tv_my_pleya_page.dart`).
///
/// The load-bearing promise of the whole screen is that no tile is decorative:
/// every one of them opens something this app already ships, so the section a
/// tile reports is asserted rather than assumed.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_my_pleya_screen.dart';
import 'package:pleya/screens/tv/tv_my_pleya_sections.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';
import '../../test_helpers/tv_my_pleya_page.dart';

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
  // The TV dock (A-24c, `Snel naar`)
  // ---------------------------------------------------------------------------

  group('the Snel naar dock', () {
    List<TvMyPleyaSection?> dock({
      bool hasSeerr = true,
      bool showDownloads = false,
      bool showActivity = true,
      bool showCollections = true,
      bool showPlaylists = true,
    }) => buildTvMyPleyaDock(
      hasSeerr: hasSeerr,
      showDownloads: showDownloads,
      showActivity: showActivity,
      showCollections: showCollections,
      showPlaylists: showPlaylists,
    ).map((tile) => tile.section).toList();

    test('A10: the six tiles in the northstar order', () {
      expect(dock(), [
        TvMyPleyaSection.watchTogether,
        TvMyPleyaSection.collections,
        TvMyPleyaSection.playlists,
        TvMyPleyaSection.requests,
        TvMyPleyaSection.libraries,
        TvMyPleyaSection.activity,
      ]);
    });

    test('A15: without Seerr and Tautulli the row closes up, no empty places', () {
      expect(dock(hasSeerr: false, showActivity: false), [
        TvMyPleyaSection.watchTogether,
        TvMyPleyaSection.collections,
        TvMyPleyaSection.playlists,
        TvMyPleyaSection.libraries,
      ]);
    });

    test('every tile follows its own capability from pariteit-v4.csv', () {
      expect(dock(showCollections: false), isNot(contains(TvMyPleyaSection.collections)));
      expect(dock(showPlaylists: false), isNot(contains(TvMyPleyaSection.playlists)));
      expect(dock(hasSeerr: false), isNot(contains(TvMyPleyaSection.requests)));
      expect(dock(showActivity: false), isNot(contains(TvMyPleyaSection.activity)));
      // Samen kijken and Bibliotheken are unconditional.
      final bare = dock(hasSeerr: false, showActivity: false, showCollections: false, showPlaylists: false);
      expect(bare, [TvMyPleyaSection.watchTogether, TvMyPleyaSection.libraries]);
    });

    test('Downloads only where the platform has downloads, never on Apple TV', () {
      expect(dock(), isNot(contains(TvMyPleyaSection.downloads)));
      expect(dock(showDownloads: true), contains(TvMyPleyaSection.downloads));
    });

    test('Instellingen, Servers, Logboeken, Over and Uitloggen moved out of the page', () {
      // Settings is a bar destination, servers/logs/about live under it, and
      // sign-out is in the account menu (LEESMIJ-v4).
      final all = dock(showDownloads: true);
      for (final moved in [
        TvMyPleyaSection.settings,
        TvMyPleyaSection.servers,
        TvMyPleyaSection.logs,
        TvMyPleyaSection.about,
      ]) {
        expect(all, isNot(contains(moved)));
      }
      expect(all, everyElement(isNotNull), reason: 'no tile that acts instead of opening a section');
    });
  });

  // ---------------------------------------------------------------------------
  // The page under the shell (A10-A15)
  // ---------------------------------------------------------------------------

  group('the page', () {
    setUp(() async {
      resetSharedPreferencesForTest();
      SettingsService.resetForTesting();
      await SettingsService.getInstance();
    });

    Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    String poster(int i) => 'tvMyPleya_poster_w$i';
    final bigP = TvMyPleyaSection.assistant.tileFocusKey;
    final seeAll = TvMyPleyaSection.watchlist.tileFocusKey;
    String tileKey(TvMyPleyaSection s) => s.tileFocusKey;

    testWidgets('the heading greets the profile, and no profile block, Beheer or sign-out is left', (tester) async {
      await pumpTvMyPleyaPage(tester);

      expect(find.text(t.tvMyPleya.heading(name: 'Michel')), findsOneWidget);
      expect(find.text(t.tvMyPleya.subline), findsOneWidget);
      expect(find.text(t.tvMyPleya.quickLinks.toUpperCase()), findsOneWidget);
      // The old A-24b page drew these; v4 has none of them: no profile action,
      // no Beheer column and no sign-out tile.
      final oldTiles = find.byWidgetPredicate(
        (w) =>
            w is FocusableWrapper &&
            const {'settings', 'servers', 'logs', 'about', 'logout'}.contains(w.automationInstance),
      );
      expect(oldTiles, findsNothing);
      expect(find.text(t.common.logout), findsNothing);
      expect(find.text(t.tvMyPleya.logs), findsNothing);
      expect(find.text(t.tvMyPleya.servers), findsNothing);
    });

    testWidgets('first entry lands on Big P, one focus object', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);

      page.state.focusActiveTabIfReady();
      await tester.pumpAndSettle();

      expect(page.focused, bigP);
      // `Vraag Big P` is the visible action inside the card, not a second stop:
      // the card is the only focus stop around it.
      expect(
        find.ancestor(of: find.text(t.tvMyPleya.bigPAction), matching: find.byType(FocusableWrapper)),
        findsOneWidget,
      );

      await press(tester, LogicalKeyboardKey.select);
      expect(page.opened, [TvMyPleyaSection.assistant]);
    });

    testWidgets('Right from Big P reaches the first poster, Left from it returns to Big P', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);
      page.state.focusKey(bigP);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(page.focused, poster(0));
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(page.focused, bigP);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(page.focused, bigP, reason: 'no wrap at the left edge');
    });

    testWidgets('Up from the top row hands the remote to the top navigation', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);
      page.state.focusKey(bigP);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(page.upCalls, hasLength(1));

      // From a poster, Up reaches Bekijk alles first, then the bar.
      page.state.focusKey(poster(2));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(page.focused, seeAll);
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(page.upCalls, hasLength(2));
      // And Down from Bekijk alles goes back to the poster it came from.
      page.state.focusKey(poster(2));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(page.focused, poster(2));
    });

    testWidgets('Bekijk alles follows the last poster and opens the kijklijst', (tester) async {
      final page = await pumpTvMyPleyaPage(tester, conditions: const TvMyPleyaPageConditions(watchlistCount: 3));
      page.state.focusKey(poster(2));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowRight);
      expect(page.focused, seeAll);
      await press(tester, LogicalKeyboardKey.select);
      expect(page.opened, [TvMyPleyaSection.watchlist]);
    });

    testWidgets('a poster with nothing to play opens the full kijklijst', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);
      page.state.focusKey(poster(0));
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.select);
      expect(page.opened, [TvMyPleyaSection.watchlist]);
    });

    testWidgets('twelve posters stay reachable inside the panel', (tester) async {
      final page = await pumpTvMyPleyaPage(tester, conditions: const TvMyPleyaPageConditions(watchlistCount: 12));
      final panel = tester.getRect(find.byType(ListView).first);
      page.state.focusKey(poster(0));
      await tester.pumpAndSettle();

      for (var i = 1; i < 12; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
        expect(page.focused, poster(i));
        final rect = FocusManager.instance.primaryFocus!.rect;
        expect(rect.left, greaterThanOrEqualTo(panel.left - 0.5), reason: 'poster $i inside the panel');
        expect(rect.right, lessThanOrEqualTo(panel.right + 0.5), reason: 'poster $i inside the panel');
      }
    });

    testWidgets('Down into the dock and Up back to where the remote came from', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);
      page.state.focusKey(bigP);
      await tester.pumpAndSettle();

      await press(tester, LogicalKeyboardKey.arrowDown);
      final landed = page.focused!;
      expect(
        buildTvMyPleyaDock(
          hasSeerr: true,
          showDownloads: false,
          showActivity: true,
          showCollections: true,
          showPlaylists: true,
        ).map((tile) => tile.focusKey),
        contains(landed),
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(page.focused, bigP);

      // From the last tile Up goes to the nearest content action, a poster.
      page.state.focusKey(tileKey(TvMyPleyaSection.activity));
      await tester.pumpAndSettle();
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(page.focused, startsWith('tvMyPleya_poster_'));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(page.focused, tileKey(TvMyPleyaSection.activity));
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(page.focused, tileKey(TvMyPleyaSection.activity), reason: 'the dock is the last row');
    });

    testWidgets('A15: Left and Right walk only the tiles that exist, without wrapping', (tester) async {
      final page = await pumpTvMyPleyaPage(tester, conditions: const TvMyPleyaPageConditions.withoutSeerrAndActivity());
      page.state.focusKey(tileKey(TvMyPleyaSection.watchTogether));
      await tester.pumpAndSettle();

      final walked = <String?>[page.focused];
      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowRight);
        walked.add(page.focused);
      }
      expect(walked, [
        tileKey(TvMyPleyaSection.watchTogether),
        tileKey(TvMyPleyaSection.collections),
        tileKey(TvMyPleyaSection.playlists),
        tileKey(TvMyPleyaSection.libraries),
        tileKey(TvMyPleyaSection.libraries),
      ]);
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(page.focused, tileKey(TvMyPleyaSection.playlists));

      expect(find.text(t.seerr.title), findsNothing);
      expect(find.text(t.tvMyPleya.activity), findsNothing);
      // The four tiles share the whole row: the last one ends on the page's
      // right inset, so there is no empty place at the row's end.
      final last = tester.getRect(
        find.ancestor(of: find.text(t.libraries.title), matching: find.byType(AnimatedContainer)).first,
      );
      final pageRight = kTvGoldenSurfaceSize.width - TvTopNavLayout.pageInset * 0.85;
      expect(last.right, closeTo(pageRight, 4));
    });

    testWidgets('every dock tile opens its own section', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);
      final sections = [
        TvMyPleyaSection.watchTogether,
        TvMyPleyaSection.collections,
        TvMyPleyaSection.playlists,
        TvMyPleyaSection.requests,
        TvMyPleyaSection.libraries,
        TvMyPleyaSection.activity,
      ];
      for (final section in sections) {
        page.state.focusKey(tileKey(section));
        await tester.pumpAndSettle();
        await press(tester, LogicalKeyboardKey.select);
      }
      expect(page.opened, sections);
    });

    testWidgets('without Big P the first content action takes the first focus', (tester) async {
      final page = await pumpTvMyPleyaPage(tester, conditions: const TvMyPleyaPageConditions(bigP: false));
      expect(find.text(t.tvMyPleya.bigPTitle), findsNothing);
      expect(page.state.availableSections, isNot(contains(TvMyPleyaSection.assistant)));

      page.state.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      expect(page.focused, poster(0));
      await press(tester, LogicalKeyboardKey.arrowLeft);
      expect(page.focused, poster(0), reason: 'no Big P to return to');
    });

    testWidgets('without Big P and without a kijklijst the dock takes the first focus', (tester) async {
      final page = await pumpTvMyPleyaPage(
        tester,
        conditions: const TvMyPleyaPageConditions(bigP: false, watchlist: false),
      );
      page.state.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      expect(page.focused, tileKey(TvMyPleyaSection.watchTogether));
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(page.upCalls, hasLength(1));
    });

    testWidgets('coming back to Mijn Pleya returns to where the remote was', (tester) async {
      final page = await pumpTvMyPleyaPage(tester);
      page.state.focusKey(tileKey(TvMyPleyaSection.playlists));
      await tester.pumpAndSettle();
      FocusManager.instance.primaryFocus?.unfocus();
      await tester.pumpAndSettle();

      page.state.focusActiveTabIfReady();
      await tester.pumpAndSettle();
      expect(page.focused, tileKey(TvMyPleyaSection.playlists));
    });

    // ------------------------------------------------------------------------
    // The canvas and the type (Michel, 26 October 2026)
    // ------------------------------------------------------------------------

    for (final (name, conditions) in [
      ('A10, everything', const TvMyPleyaPageConditions(watchlistCount: 12)),
      ('A15, no Seerr or Activiteit', const TvMyPleyaPageConditions.withoutSeerrAndActivity()),
      ('Android TV with Downloads', const TvMyPleyaPageConditions(appleTv: false)),
      ('without Big P', const TvMyPleyaPageConditions(bigP: false)),
    ]) {
      for (final locale in [AppLocale.nl, AppLocale.en]) {
        testWidgets('$name (${locale.languageCode}): everything inside 1038 x 584, no text under 23 pt', (
          tester,
        ) async {
          await tester.runAsync(() => LocaleSettings.setLocale(locale));
          addTearDown(() => LocaleSettings.setLocaleSync(AppLocale.en));
          await tester.runAsync(loadAppFontsForGoldens);
          final page = await pumpTvMyPleyaPage(tester, conditions: conditions);
          final canvas = Offset.zero & kTvGoldenSurfaceSize;

          // No scrolling needed: the page fits, the dock included.
          final scroller = tester.state<ScrollableState>(
            find.descendant(of: find.byType(TvMyPleyaScreen), matching: find.byType(Scrollable)).first,
          );
          expect(scroller.position.maxScrollExtent, 0.0);

          // Every focus stop, ring room included, is on the canvas. Posters
          // past the panel's edge are clipped and scroll in on focus, so the
          // check is for those in the panel.
          final panel = find.byType(ListView).evaluate().isEmpty ? null : tester.getRect(find.byType(ListView).first);
          for (final wrapper in tester.widgetList<FocusableWrapper>(
            find.descendant(of: find.byType(TvMyPleyaScreen), matching: find.byType(FocusableWrapper)),
          )) {
            final node = wrapper.focusNode!;
            final rect = node.rect;
            if (panel != null && node.debugLabel!.startsWith('tvMyPleya_poster_') && rect.left > panel.right) continue;
            final ring = rect.inflate(4);
            expect(
              canvas.contains(ring.topLeft) && canvas.contains(ring.bottomRight),
              isTrue,
              reason: '${node.debugLabel} at $ring is off the canvas',
            );
          }

          // The dock is reachable and whole: walk to it with the remote.
          page.state.focusActiveTabIfReady();
          await tester.pumpAndSettle();
          await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
          await tester.pumpAndSettle();
          final dockRect = FocusManager.instance.primaryFocus!.rect;
          expect(dockRect.bottom, lessThanOrEqualTo(kTvGoldenSurfaceSize.height));

          // HIG: 23 pt on the 1080 canvas is 23 x 584 / 1080 logical here.
          final minimum = 23 * kTvGoldenSurfaceSize.height / 1080 - 0.01;
          final paragraphs = tester.renderObjectList<RenderParagraph>(
            find.descendant(of: find.byType(TvMyPleyaScreen), matching: find.byType(RichText)),
          );
          final small = <String>[];
          final cut = <String>[];
          for (final p in paragraphs) {
            if (p.text.toPlainText().trim().isEmpty) continue;
            // Icons are glyphs, not text.
            if (p.text.style?.fontFamily?.contains('MaterialSymbols') ?? false) continue;
            void visit(InlineSpan span, double? inherited) {
              final size = span.style?.fontSize ?? inherited;
              if (span is TextSpan && (span.text?.trim().isNotEmpty ?? false) && size != null && size < minimum) {
                small.add('${span.text} (${(size * 1080 / kTvGoldenSurfaceSize.height).toStringAsFixed(1)} pt)');
              }
              if (span is TextSpan) {
                for (final child in span.children ?? const <InlineSpan>[]) {
                  visit(child, size);
                }
              }
            }

            visit(p.text, null);
            if (p.didExceedMaxLines) cut.add(p.text.toPlainText());
          }
          expect(small, isEmpty, reason: 'text under the tvOS minimum');
          expect(cut, isEmpty, reason: 'text cut off');
        });
      }
    }
  });
}
