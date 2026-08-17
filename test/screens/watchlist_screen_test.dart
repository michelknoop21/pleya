import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/providers/multi_server_provider.dart';
import 'package:pleya/providers/offline_mode_provider.dart';
import 'package:pleya/providers/watchlist_provider.dart';
import 'package:pleya/screens/watchlist_screen.dart';
import 'package:pleya/services/data_aggregation_service.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_snapshot_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/focus/card_focus_scope.dart';
import 'package:pleya/widgets/media_card_grid_layout.dart';
import 'package:pleya/widgets/watchlist_card.dart';

import '../test_helpers/prefs.dart';

final scope = WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

WatchlistEntry entry({
  required String key,
  String title = 'Sintel',
  MediaKind kind = MediaKind.movie,
  int? year = 2010,
  int position = 0,
  WatchlistAvailability availability = WatchlistAvailability.unknown,
  MediaItem? match,
}) {
  return WatchlistEntry(
    key: key,
    kind: kind,
    item: MediaItem(id: key, backend: MediaBackend.plex, kind: kind, title: title, year: year),
    guid: 'plex://movie/$key',
    posterRef: 'https://metadata-static.plex.tv/$key.jpg',
    memberships: [WatchlistMembership(scope: scope, remoteKey: key, sourcePosition: position)],
    availability: availability,
    lastKnownMatch: match,
  );
}

/// A match on a registered server, which is what turns an entry into the
/// playable branch of [WatchlistCard] (see `WatchlistProvider.isPlayable`).
/// No poster path, so nothing reaches for the network.
MediaItem playableMatch(String key, {String title = 'Sintel', int? year = 2010}) => MediaItem(
  id: key,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: year,
  serverId: 'machine-1',
);

class _StubSource implements WatchlistSource {
  _StubSource(this.entries);

  final List<WatchlistEntry> entries;
  final removed = <WatchlistMembership>[];

  /// Counts every trip to the source, so a test can prove that a screen action
  /// did not go out over the wire.
  int fetchCount = 0;

  @override
  WatchlistScopeId get scope =>
      WatchlistScopeId(profileId: 'p1', backend: MediaBackend.plex, accountId: 'a', userId: 'u');

  @override
  bool accepts(MediaItem item) => true;

  @override
  Future<List<WatchlistEntry>> fetch() async {
    fetchCount++;
    return entries;
  }

  @override
  Future<WatchlistMembership> add(MediaItem item) async => WatchlistMembership(scope: scope, remoteKey: item.id);

  @override
  Future<void> remove(WatchlistMembership membership) async => removed.add(membership);

  @override
  Future<bool?> contains(MediaItem item) async => null;
}

/// Reports offline without dragging a MultiServerManager into a widget test.
/// The screen only ever reads [isOffline] off this provider.
class _OfflineProvider extends ChangeNotifier implements OfflineModeProvider {
  @override
  bool get isOffline => true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AppDatabase db;
  late WatchlistProvider provider;
  late _StubSource source;

  setUp(() async {
    resetSharedPreferencesForTest();
    await SettingsService.getInstance();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async => db.close());

  Future<void> pumpScreen(
    WidgetTester tester,
    List<WatchlistEntry> entries, {
    bool seerrConfigured = false,
    bool offline = false,
    bool serversOnline = false,
    TextScaler? textScaler,
  }) async {
    source = _StubSource(entries);
    provider = WatchlistProvider(
      snapshots: WatchlistSnapshotStore(cache: PlexApiCache.instance),
      repository: WatchlistRepository(sources: [source]),
      seerrConfigured: seerrConfigured,
      isServerOnline: (_) => serversOnline,
    );
    // An empty manager: no clients registered, so MediaCard's poster resolves
    // to its fallback icon and no image request goes out. Registered because
    // the real card asks for one during build and would throw without it.
    final manager = MultiServerManager();
    final servers = MultiServerProvider(manager, DataAggregationService(manager));
    addTearDown(servers.dispose);
    // Load before pumping, and through runAsync: the snapshot store talks to a
    // real sqlite file, which the test binding's fake async never advances. The
    // screen kicks off its own load too, but by then this one has settled and
    // the spinner is gone, so the frame count stays predictable.
    await tester.runAsync(() => provider.load());
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          builder: textScaler == null
              ? null
              : (context, child) => MediaQuery(
                  data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                  child: child!,
                ),
          // Without an OfflineModeProvider the screen reads absent as online,
          // which is the state most of these tests are about.
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<WatchlistProvider>.value(value: provider),
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              if (offline) ChangeNotifierProvider<OfflineModeProvider>(create: (_) => _OfflineProvider()),
            ],
            child: const WatchlistScreen(),
          ),
        ),
      ),
    );
    // Not pumpAndSettle: the loading spinner animates forever, so settling is
    // impossible until the load lands. Three pumps cover schedule, resolve and
    // rebuild.
    await tester.pump();
    await tester.pump();
    await tester.pump();
  }

  testWidgets('renders one card per title', (tester) async {
    await pumpScreen(tester, [entry(key: 'a', title: 'Sintel'), entry(key: 'b', title: 'Big Buck Bunny')]);

    expect(find.byType(WatchlistCard), findsNWidgets(2));
    expect(find.text('Sintel'), findsOneWidget);
    expect(find.text('Big Buck Bunny'), findsOneWidget);
  });

  testWidgets('an empty watchlist and a filter that hides everything say different things', (tester) async {
    await pumpScreen(tester, []);
    expect(find.text(t.watchlist.empty), findsOneWidget);
    expect(find.text(t.watchlist.emptyBody), findsOneWidget);

    await pumpScreen(tester, [entry(key: 'a', kind: MediaKind.movie)]);
    await tester.tap(find.text(t.watchlist.filterShows));
    await tester.pump();
    await tester.pump();

    expect(find.text(t.watchlist.emptyFiltered), findsOneWidget);
    expect(find.text(t.watchlist.empty), findsNothing);
  });

  testWidgets('both empty states keep a focusable action, so a remote has somewhere to go', (tester) async {
    await pumpScreen(tester, []);
    expect(find.widgetWithText(FocusableButton, t.watchlist.retry), findsOneWidget);

    await pumpScreen(tester, [entry(key: 'a')]);
    await tester.tap(find.text(t.watchlist.filterShows));
    await tester.pump();
    await tester.pump();

    expect(find.widgetWithText(FocusableButton, t.watchlist.filterAll), findsOneWidget);
  });

  testWidgets('the type filters narrow the grid', (tester) async {
    await pumpScreen(tester, [
      entry(key: 'movie', title: 'A Movie'),
      entry(key: 'show', title: 'A Show', kind: MediaKind.show),
    ]);

    await tester.tap(find.text(t.watchlist.filterMovies));
    await tester.pump();
    await tester.pump();
    expect(find.text('A Movie'), findsOneWidget);
    expect(find.text('A Show'), findsNothing);

    await tester.tap(find.text(t.watchlist.filterShows));
    await tester.pump();
    await tester.pump();
    expect(find.text('A Show'), findsOneWidget);
    expect(find.text('A Movie'), findsNothing);
  });

  // The screen regression these cover: a playable card handed MediaCard the
  // cell height, MediaCard read that as the poster height and drew its title
  // and year below it, and SliverGrid does not clip — so the caption of row 1
  // landed on the posters of row 2.
  group('grid geometry', () {
    /// Both branches wrap their poster in a [CardFocusBorder], so its rect is
    /// the poster rect regardless of which card rendered it.
    Rect posterOf(WidgetTester tester, int index) => tester.getRect(
      find.descendant(of: find.byType(WatchlistCard).at(index), matching: find.byType(CardFocusBorder)).first,
    );

    List<Rect> cardRects(WidgetTester tester) => [
      for (var i = 0; i < tester.widgetList(find.byType(WatchlistCard)).length; i++)
        tester.getRect(find.byType(WatchlistCard).at(i)),
    ];

    /// The top of the second row, from the two distinct card tops on screen.
    double secondRowTop(List<Rect> cards) {
      final tops = {for (final r in cards) (r.top * 2).roundToDouble() / 2}.toList()..sort();
      expect(tops.length, greaterThanOrEqualTo(2), reason: 'this needs two rows on screen');
      return tops[1];
    }

    /// A phone-width viewport, so three columns and the mix below spans more
    /// than one row.
    void useTallPhone(WidgetTester tester) {
      tester.view.physicalSize = const Size(420, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
    }

    Future<void> pumpTwoRows(WidgetTester tester, {TextScaler? textScaler}) async {
      useTallPhone(tester);

      await pumpScreen(
        tester,
        [
          // A playable entry renders its server match, so the two titles are
          // kept apart on purpose: find.text has to stay unambiguous.
          entry(
            key: 'a',
            title: 'Sintel',
            match: playableMatch('a', title: 'Sintel op de server'),
          ),
          entry(key: 'b', title: 'Big Buck Bunny', availability: WatchlistAvailability.notFound),
          entry(key: 'c', title: 'Een titel die veel te lang is om op een enkele regel te passen'),
          entry(key: 'd', title: 'Zonder jaar', year: null),
          entry(
            key: 'e',
            title: 'Cosmos Laundromat',
            match: playableMatch('e', title: 'Cosmos op de server'),
          ),
          entry(key: 'f', title: 'Caminandes', availability: WatchlistAvailability.checking),
        ],
        serversOnline: true,
        textScaler: textScaler,
      );
    }

    /// Column count from the rendered cards: the distinct card lefts in the
    /// first row.
    int columnsOn(WidgetTester tester) {
      final cards = cardRects(tester);
      final firstTop = (cards.map((r) => r.top).reduce((a, b) => a < b ? a : b) * 2).roundToDouble() / 2;
      return cards.where((r) => ((r.top * 2).roundToDouble() / 2) == firstTop).length;
    }

    testWidgets('a phone gets readable columns, not one more poster than fits', (tester) async {
      // 390 is a stock iPhone. Four columns there left 85pt cards, on which
      // nearly every title ellipsised and the availability badge could not show
      // its own word.
      for (final width in <double>[375, 390, 430]) {
        tester.view.physicalSize = Size(width, 1600);
        tester.view.devicePixelRatio = 1.0;
        addTearDown(tester.view.reset);

        await pumpScreen(tester, [
          for (var i = 0; i < 8; i++) entry(key: 'p$i', title: 'Titel $i'),
        ], serversOnline: true);

        expect(columnsOn(tester), 3, reason: 'at ${width}pt');
        expect(tester.takeException(), isNull);
      }
    });

    testWidgets('a very narrow phone drops to two columns rather than shrinking further', (tester) async {
      tester.view.physicalSize = const Size(320, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester, [for (var i = 0; i < 6; i++) entry(key: 'n$i', title: 'Titel $i')], serversOnline: true);

      expect(columnsOn(tester), 2);
      expect(tester.takeException(), isNull);
    });

    testWidgets('a tablet uses its extra width for more columns', (tester) async {
      tester.view.physicalSize = const Size(768, 1600);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      await pumpScreen(tester, [
        for (var i = 0; i < 10; i++) entry(key: 't$i', title: 'Titel $i'),
      ], serversOnline: true);

      expect(columnsOn(tester), greaterThanOrEqualTo(4));
      expect(tester.takeException(), isNull);
    });

    testWidgets('a title on two lines does not make its card taller than the row', (tester) async {
      await pumpTwoRows(tester);

      final cards = cardRects(tester);
      final heights = {for (final r in cards) (r.height * 2).roundToDouble() / 2};
      // 'Een titel die veel te lang is…' wraps, the others do not.
      expect(heights.length, 1, reason: 'cards in one grid must share a height');
    });

    testWidgets('no card overflows its cell, whichever branch renders it', (tester) async {
      await pumpTwoRows(tester);

      // An overflowing card is a RenderFlex overflow in a test; on a TV it was
      // 32 invisible pixels drawn over the row below.
      expect(tester.takeException(), isNull);

      final cards = cardRects(tester);
      expect(cards.length, 6);

      final context = tester.element(find.byType(WatchlistCard).first);
      // Phone widths give the title two lines, and the cell reserves both, so
      // the row keeps one height whether a title wraps or not.
      final expected = MediaCardGridLayout.cardHeightFor(context, cards.first.width, titleLines: 2);
      for (final r in cards) {
        expect(r.height, moreOrLessEquals(expected, epsilon: 0.5));
        expect(r.width, moreOrLessEquals(cards.first.width, epsilon: 0.5));
      }
    });

    testWidgets('nothing from the first row reaches into the second', (tester) async {
      await pumpTwoRows(tester);

      final cards = cardRects(tester);
      final rowTwoTop = secondRowTop(cards);

      for (final r in cards.where((r) => r.top < rowTwoTop - 0.5)) {
        expect(r.bottom, lessThanOrEqualTo(rowTwoTop + 0.5));
      }
      // And the captions themselves, which is what the screenshot showed.
      for (final title in ['Sintel op de server', 'Big Buck Bunny', 'Zonder jaar']) {
        final text = find.text(title);
        expect(text, findsOneWidget);
        final rect = tester.getRect(text);
        if (rect.top >= rowTwoTop) continue;
        expect(
          rect.bottom,
          lessThanOrEqualTo(rowTwoTop + 0.5),
          reason: '"$title" is drawn over the poster of the row below',
        );
      }
    });

    testWidgets('the second row starts at one Y, whatever is in the first', (tester) async {
      await pumpTwoRows(tester);
      final withMixedContent = secondRowTop(cardRects(tester));

      // Same grid, first row now all plain unavailable cards with a year.
      useTallPhone(tester);
      await pumpScreen(tester, [
        for (final key in ['a', 'b', 'c', 'd', 'e', 'f']) entry(key: key, title: 'Title $key'),
      ]);

      expect(secondRowTop(cardRects(tester)), moreOrLessEquals(withMixedContent, epsilon: 0.5));
    });

    testWidgets('both branches put their poster on the same pixel', (tester) async {
      useTallPhone(tester);

      await pumpScreen(tester, [
        entry(key: 'a', title: 'Playable', match: playableMatch('a')),
        entry(key: 'b', title: 'Not available', availability: WatchlistAvailability.notFound),
      ], serversOnline: true);

      final cards = cardRects(tester);
      final playable = posterOf(tester, 0);
      final unavailable = posterOf(tester, 1);

      expect(playable.size.width, moreOrLessEquals(unavailable.size.width, epsilon: 0.5));
      expect(playable.size.height, moreOrLessEquals(unavailable.size.height, epsilon: 0.5));
      expect(playable.top - cards[0].top, moreOrLessEquals(MediaCardGridLayout.topInset, epsilon: 0.5));
      expect(unavailable.top - cards[1].top, moreOrLessEquals(MediaCardGridLayout.topInset, epsilon: 0.5));
      expect(playable.height / playable.width, moreOrLessEquals(1.5, epsilon: 0.01));
    });

    testWidgets('the Not available badge does not change the geometry', (tester) async {
      useTallPhone(tester);

      await pumpScreen(tester, [entry(key: 'a', title: 'Sintel')]);
      final plain = cardRects(tester).single;

      await pumpScreen(tester, [entry(key: 'a', title: 'Sintel', availability: WatchlistAvailability.notFound)]);
      expect(cardRects(tester).single, plain);
    });

    testWidgets('focus grows the card in paint, not in layout', (tester) async {
      await pumpTwoRows(tester);

      final before = cardRects(tester);
      final rowTwoTop = secondRowTop(before);

      final firstCard = tester.firstElement(find.byType(WatchlistCard));
      final node = FocusScope.of(firstCard).traversalDescendants.firstWhere((n) => n.canRequestFocus);
      node.requestFocus();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      // Transform.scale is paint-time, so the layout boxes must be untouched.
      final after = cardRects(tester);
      for (var i = 0; i < before.length; i++) {
        if (before[i].top < rowTwoTop - 0.5) continue; // the focused row may paint larger
        expect(after[i], before[i], reason: 'focus moved a card in the row below');
      }
      expect(tester.takeException(), isNull);
    });

    testWidgets('a larger system text size still keeps the rows apart', (tester) async {
      await pumpTwoRows(tester, textScaler: const TextScaler.linear(1.5));

      expect(tester.takeException(), isNull);

      final cards = cardRects(tester);
      final rowTwoTop = secondRowTop(cards);
      for (final r in cards.where((r) => r.top < rowTwoTop - 0.5)) {
        expect(r.bottom, lessThanOrEqualTo(rowTwoTop + 0.5));
      }
    });
  });

  testWidgets('the grid never scrolls horizontally out of its own clip', (tester) async {
    await pumpScreen(tester, [entry(key: 'a')]);

    final scrollView = tester.widget<CustomScrollView>(find.byType(CustomScrollView).first);

    // A focused card grows past its cell; hardEdge would shear the ring off at
    // the viewport edge on TV.
    expect(scrollView.clipBehavior, Clip.none);
  });

  testWidgets('Remove in the sheet reaches the source and drops the card', (tester) async {
    await pumpScreen(tester, [entry(key: 'a', title: 'Sintel')]);

    await tester.tap(find.byType(WatchlistCard));
    await tester.pumpAndSettle();
    expect(find.text(t.watchlist.remove), findsOneWidget);

    await tester.tap(find.text(t.watchlist.remove));
    await tester.pumpAndSettle();

    expect(source.removed.single.remoteKey, 'a');
    // The grid emptying is the confirmation, which is why no snackbar follows.
    expect(find.byType(WatchlistCard), findsNothing);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('Request in the sheet goes to Seerr, and says so when there is no id to send', (tester) async {
    final unavailable = WatchlistEntry(
      key: 'a',
      kind: MediaKind.movie,
      item: MediaItem(id: 'a', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Sintel'),
      guid: 'plex://movie/a',
      memberships: [WatchlistMembership(scope: scope, remoteKey: 'a')],
      availability: WatchlistAvailability.notFound,
      coverageComplete: true,
    );
    await pumpScreen(tester, [unavailable], seerrConfigured: true);

    await tester.tap(find.byType(WatchlistCard));
    await tester.pumpAndSettle();
    await tester.tap(find.text(t.seerr.request));
    await tester.pumpAndSettle();

    // No TMDB id on the entry, so the request cannot be filed and the screen
    // says that rather than opening an empty sheet.
    expect(find.text(t.seerr.errorGeneric), findsOneWidget);
    expect(source.removed, isEmpty);
  });

  group('sorting', () {
    List<String> cardOrder(WidgetTester tester) =>
        tester.widgetList<WatchlistCard>(find.byType(WatchlistCard)).map((card) => card.entry.key).toList();

    Future<void> pick(WidgetTester tester, String option) async {
      await tester.tap(find.text(t.libraries.sort));
      await tester.pumpAndSettle();
      await tester.tap(find.text(option));
      await tester.pumpAndSettle();
    }

    // Positions run against the alphabet on purpose: if the screen ever fell
    // back on title order, the default would still look right by accident.
    List<WatchlistEntry> threeFilms() => [
      entry(key: 'c', title: 'Cars', year: 2006, position: 0),
      entry(key: 'a', title: 'Alien', year: 1979, position: 1),
      entry(key: 'b', title: 'Blade Runner', year: 1982, position: 2),
    ];

    testWidgets('the default is the order the list was added in', (tester) async {
      await pumpScreen(tester, threeFilms());

      expect(cardOrder(tester), ['c', 'a', 'b']);
    });

    testWidgets('title and year reorder the grid without going back to the source', (tester) async {
      await pumpScreen(tester, threeFilms());
      final fetchesAfterLoad = source.fetchCount;

      await pick(tester, t.watchlist.sortTitle);
      expect(cardOrder(tester), ['a', 'b', 'c']);

      await pick(tester, t.watchlist.sortYear);
      expect(cardOrder(tester), ['c', 'b', 'a']);

      await pick(tester, t.watchlist.sortRecentlyAdded);
      expect(cardOrder(tester), ['c', 'a', 'b']);

      // Order is a property of the list already in memory. Fetching again to
      // answer it would be a round trip for something the app knows.
      expect(source.fetchCount, fetchesAfterLoad);
    });

    testWidgets('sorting applies to what a type filter left over', (tester) async {
      await pumpScreen(tester, [
        entry(key: 'c', title: 'Cars', year: 2006, position: 0),
        entry(key: 'show', title: 'Andor', year: 2022, kind: MediaKind.show, position: 1),
        entry(key: 'a', title: 'Alien', year: 1979, position: 2),
      ]);

      await tester.tap(find.text(t.watchlist.filterMovies));
      await tester.pumpAndSettle();
      await pick(tester, t.watchlist.sortTitle);

      expect(cardOrder(tester), ['a', 'c'], reason: 'the show is filtered out and the two films are sorted');
    });

    testWidgets('at 360dp the bar stays one row: the chips scroll and the button holds its place', (tester) async {
      tester.view.physicalSize = const Size(360, 800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);

      await pumpScreen(tester, threeFilms());

      // A Row that did not fit would throw here rather than reflow, so simply
      // arriving with the button on screen is the assertion.
      final button = find.text(t.libraries.sort);
      expect(button, findsOneWidget);
      expect(tester.getTopRight(button).dx, lessThanOrEqualTo(360));

      // The chips share the row with the button instead of pushing it off.
      expect(tester.getTopRight(find.text(t.watchlist.filterAll)).dx, lessThan(tester.getTopLeft(button).dx));
    });

    testWidgets('offline the order can still be changed, but Available cannot be picked', (tester) async {
      await pumpScreen(tester, threeFilms(), offline: true);

      // Availability needs live servers; order does not.
      expect(find.text(t.watchlist.filterAvailable), findsNothing);
      expect(find.text(t.libraries.sort), findsOneWidget);

      await pick(tester, t.watchlist.sortTitle);

      expect(cardOrder(tester), ['a', 'b', 'c']);
    });
  });
}
