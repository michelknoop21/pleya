import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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
import 'package:pleya/mixins/refreshable.dart';
import 'package:pleya/navigation/main_screen_scope.dart';
import 'package:pleya/screens/watchlist_screen.dart';
import 'package:pleya/utils/platform_detector.dart';
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
import 'package:pleya/widgets/focusable_filter_chip.dart';
import 'package:pleya/widgets/watchlist_sort_sheet.dart';
import 'package:pleya/widgets/overlay_sheet.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
import 'package:pleya/widgets/tv/tv_watchlist_card.dart';
import 'package:pleya/widgets/watchlist_card.dart';

import '../test_helpers/prefs.dart';
import '../test_helpers/notice_layer.dart';

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

  /// The key the fase-7 shell hangs on this screen, so `screenKey.currentState`
  /// resolves to the `FocusableTab` it is supposed to. Kijklijst had none: the
  /// route made a `GlobalKey` and handed it to nothing, so the shell's
  /// `focusActiveTabIfReady` was a call into null for this section (P5).
  final watchlistKey = GlobalKey<State<WatchlistScreen>>();

  // A notice keeps an auto-dismiss timer, and the test framework fails a test
  // that leaves one pending.
  tearDown(resetNotices);

  setUp(() async {
    resetNotices();
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
    bool tv = false,
    VoidCallback? focusSidebar,
  }) async {
    if (tv) {
      TvDetectionService.debugSetAppleTVOverride(true);
      addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    }
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
          builder: withNoticeLayer(
            textScaler == null
                ? null
                : (context, child) => MediaQuery(
                    data: MediaQuery.of(context).copyWith(textScaler: textScaler),
                    child: child!,
                  ),
          ),
          // Without an OfflineModeProvider the screen reads absent as online,
          // which is the state most of these tests are about.
          home: MultiProvider(
            providers: [
              ChangeNotifierProvider<WatchlistProvider>.value(value: provider),
              ChangeNotifierProvider<MultiServerProvider>.value(value: servers),
              if (offline) ChangeNotifierProvider<OfflineModeProvider>(create: (_) => _OfflineProvider()),
            ],
            // The real app always has an OverlaySheetHost above this screen
            // (MainScreen installs one), so sheets open as overlays rather than
            // routes. Pumping without it sent showAdaptive down the
            // showModalBottomSheet fallback, where a plain Navigator.pop is
            // correct -- which is exactly why the sort sheet could pop the whole
            // screen in the app while these tests stayed green.
            child: OverlaySheetHost(
              child: MainScreenFocusScope(
                focusSidebar: focusSidebar ?? () {},
                focusContent: () {},
                isSidebarFocused: false,
                sideNavigationWidth: 0,
                foregroundLeft: 0,
                foregroundWidth: 1280,
                viewportWidth: 1280,
                child: WatchlistScreen(key: watchlistKey),
              ),
            ),
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

  group('filter bar', () {
    // The screenshots showed "Alles" cut off at the left edge and the last chip
    // erased mid-word by a fade, on a bar that used a raw Material ChoiceChip
    // found nowhere else in the app.
    testWidgets('the sort control names the order it is in', (tester) async {
      await pumpScreen(tester, [entry(key: 'a')]);

      // Not hidden in a tooltip: tooltips never open on an iOS touch.
      expect(find.text(watchlistSortLabel(WatchlistSort.recentlyAdded)), findsOneWidget);
      expect(find.byType(Tooltip), findsNothing);
    });

    testWidgets('the chips are the app\'s own, not a bare Material chip', (tester) async {
      await pumpScreen(tester, [entry(key: 'a')]);

      expect(find.byType(ChoiceChip), findsNothing);
      expect(find.byType(FocusableFilterChip), findsWidgets);
    });

    testWidgets('no chip starts or ends outside the viewport', (tester) async {
      tester.view.physicalSize = const Size(360, 780);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpScreen(tester, [entry(key: 'a')]);

      for (final label in [t.watchlist.filterAll, t.watchlist.filterMovies, t.watchlist.filterShows]) {
        final chip = find.ancestor(of: find.text(label), matching: find.byType(FocusableFilterChip)).first;
        final rect = tester.getRect(chip);
        expect(rect.left, greaterThanOrEqualTo(0), reason: '$label starts off-screen');
        expect(rect.width, greaterThan(0));
      }
    });

    testWidgets('the strip keeps an inset, so the first chip is never flush left', (tester) async {
      await pumpScreen(tester, [entry(key: 'a')]);

      final chip = find
          .ancestor(of: find.text(t.watchlist.filterAll), matching: find.byType(FocusableFilterChip))
          .first;
      expect(tester.getRect(chip).left, greaterThan(0));
    });

    testWidgets('picking a filter keeps it selected and readable', (tester) async {
      await pumpScreen(tester, [entry(key: 'a'), entry(key: 'show', kind: MediaKind.show)]);

      await tester.tap(find.text(t.watchlist.filterShows));
      await tester.pumpAndSettle();

      final chip = tester.widget<FocusableFilterChip>(
        find.ancestor(of: find.text(t.watchlist.filterShows), matching: find.byType(FocusableFilterChip)).first,
      );
      expect(chip.selected, isTrue);
      expect(tester.takeException(), isNull);
    });
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

    // The sheet is an overlay, not a route, so closing it with a plain
    // Navigator.pop popped the screen underneath instead: on the phone the only
    // route below is MainScreen, and an empty Navigator paints black.
    testWidgets('picking an order closes the sheet and leaves the screen standing', (tester) async {
      await pumpScreen(tester, threeFilms());

      await tester.tap(find.text(t.libraries.sort));
      await tester.pumpAndSettle();
      expect(find.text(t.libraries.sortBy), findsOneWidget);

      await tester.tap(find.text(t.watchlist.sortYear));
      await tester.pumpAndSettle();

      expect(find.text(t.libraries.sortBy), findsNothing, reason: 'the sheet should be gone');
      expect(find.byType(WatchlistScreen), findsOneWidget, reason: 'the screen must survive the sheet closing');
      expect(cardOrder(tester), ['c', 'b', 'a']);
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

  // ---------------------------------------------------------------------------
  // P5: the kijklijst is operable with a remote
  // ---------------------------------------------------------------------------

  group('TV, in the catalog language (DEC-108, mockup 34)', () {
    List<WatchlistEntry> sixFilms() => [
      for (final id in ['a', 'b', 'c', 'd', 'e', 'f']) entry(key: id, title: 'Film ${id.toUpperCase()}'),
    ];

    TvWatchlistCard cardFor(WidgetTester tester, String key) =>
        tester.widgetList<TvWatchlistCard>(find.byType(TvWatchlistCard)).firstWhere((card) => card.entry.key == key);

    FocusNode nodeFor(WidgetTester tester, String key) => cardFor(tester, key).focusNode!;

    Future<void> openRail(WidgetTester tester) async {
      nodeFor(tester, 'a').requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
    }

    /// Select, the way a remote sends it. Nothing on a TV surface answers a tap:
    /// `FocusableWrapper` has no gesture recogniser at all, deliberately, so a
    /// test that taps a rail row proves nothing about the page.
    Future<void> select(WidgetTester tester) async {
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    /// Opens the focused rail row and walks down to the [index]th answer.
    Future<void> pickOption(WidgetTester tester, int index) async {
      await select(tester);
      for (var i = 0; i < index; i++) {
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
        await tester.pumpAndSettle();
      }
      await select(tester);
    }

    testWidgets('the grid draws the catalog card, not the kijklijst dispatcher', (tester) async {
      // CAT11: the whole finding was that this page and Aanvragen and Zoeken
      // drew items at a different size from Alle films. `WatchlistCard`
      // dispatches to `FocusableMediaCard` or `WatchlistUnavailableCard`
      // depending on whether a lookup has landed, and neither of those is the
      // catalog's card.
      await pumpScreen(tester, sixFilms(), tv: true);

      expect(find.byType(TvWatchlistCard), findsNWidgets(6));
      expect(find.byType(WatchlistCard), findsNothing);
      expect(find.byType(TvCatalogCard), findsNWidgets(6));
    });

    testWidgets('a card is exactly as wide as a card on Alle films', (tester) async {
      // P6's other half, restated on the new card: the column count, the card
      // width, the gutter and the page inset all come from
      // `TvCatalogGrid.forWidth`, never from `SettingsService.libraryDensity`.
      tester.view.physicalSize = const Size(1038, 584);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpScreen(tester, sixFilms(), tv: true);

      final grid = TvCatalogGrid.forWidth(1038, scale: 0.85);
      expect(cardFor(tester, 'a').width, closeTo(grid.cardWidth, 0.01));
    });

    testWidgets('the page carries the catalog heading, and no chip bar', (tester) async {
      await pumpScreen(tester, sixFilms(), tv: true);

      expect(find.byType(TvCatalogHeaderBar), findsOneWidget);
      expect(
        find.byType(FocusableFilterChip),
        findsNothing,
        reason: 'the controls moved into the rail (mockup 34 A/B); a chip strip above the grid is the old page',
      );
    });

    testWidgets('every card carries a focus node, keyed on the entry', (tester) async {
      await pumpScreen(tester, sixFilms(), tv: true);

      final cards = tester.widgetList<TvWatchlistCard>(find.byType(TvWatchlistCard)).toList();
      expect(cards.every((card) => card.focusNode != null), isTrue);
      expect(cards.every((card) => card.key == ValueKey(card.entry.key)), isTrue);
      expect(
        cards.map((c) => c.focusNode).toSet(),
        hasLength(cards.length),
        reason: 'one node per entry, never one node reused by position',
      );
    });

    testWidgets('the shell can put the focus on the grid, and it lands on a card', (tester) async {
      await pumpScreen(tester, sixFilms(), tv: true);

      final state = watchlistKey.currentState;
      expect(state, isA<FocusableTab>(), reason: 'the screen has to answer the shell at all');
      (state! as FocusableTab).focusActiveTabIfReady();
      await tester.pumpAndSettle();

      expect(nodeFor(tester, 'a').hasFocus, isTrue);
    });

    testWidgets('LEFT and RIGHT walk the row deterministically', (tester) async {
      await pumpScreen(tester, sixFilms(), tv: true);
      nodeFor(tester, 'a').requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expect(nodeFor(tester, 'b').hasFocus, isTrue);

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(nodeFor(tester, 'a').hasFocus, isTrue);
    });

    testWidgets('UP from the first row goes straight to the top navigation', (tester) async {
      // Since the controls moved into the rail there is no header row in
      // between any more, which is the same shape the catalog has had since
      // CAT5.
      var exits = 0;
      await pumpScreen(tester, sixFilms(), tv: true, focusSidebar: () => exits++);
      nodeFor(tester, 'a').requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
      await tester.pumpAndSettle();
      expect(exits, 1);
    });

    testWidgets('Select on the focused card opens that card\'s sheet', (tester) async {
      await pumpScreen(tester, sixFilms(), tv: true);
      nodeFor(tester, 'c').requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();

      expect(find.text('Film C'), findsWidgets, reason: 'the sheet is about the card the remote was on');
    });

    testWidgets('an availability flip leaves the focus exactly where it was', (tester) async {
      // The old card swapped widget *type* when a lookup landed, so the `Focus`
      // holding the node was unmounted and a new one mounted in the same pass,
      // and the screen had to re-request the focus afterwards. The catalog card
      // does not change type: unavailability is a marker on one card.
      final entries = sixFilms();
      await pumpScreen(tester, entries, tv: true, serversOnline: true);
      nodeFor(tester, 'b').requestFocus();
      await tester.pumpAndSettle();

      await tester.runAsync(() => provider.resolveAllUnknown());
      await tester.pumpAndSettle();

      expect(nodeFor(tester, 'b').hasFocus, isTrue, reason: 'the viewer did not move, so neither does the ring');
    });

    testWidgets('a title none of the servers has carries the Niet beschikbaar marker', (tester) async {
      await pumpScreen(tester, [
        entry(key: 'a', title: 'Film A'),
        entry(key: 'b', title: 'Film B', availability: WatchlistAvailability.notFound),
      ], tv: true);

      final badges = tester.widgetList<TvCatalogArtworkBadge>(find.byType(TvCatalogArtworkBadge)).toList();
      expect(badges.map((b) => b.label), [t.watchlist.notAvailable]);
      expect(
        cardFor(tester, 'b').width,
        cardFor(tester, 'a').width,
        reason: 'the marker is drawn on the artwork, so it cannot change the geometry',
      );
    });

    testWidgets('removing the card the remote is on leaves the remote on a card', (tester) async {
      await pumpScreen(tester, sixFilms(), tv: true);
      nodeFor(tester, 'c').requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.watchlist.remove));
      await tester.pumpAndSettle();

      expect(
        tester.widgetList<TvWatchlistCard>(find.byType(TvWatchlistCard)).any((c) => c.entry.key == 'c'),
        isFalse,
        reason: 'the card is gone, which is the precondition for the trap',
      );
      expect(
        nodeFor(tester, 'd').hasPrimaryFocus,
        isTrue,
        reason: 'the slot is kept, so the card that slid up into the empty cell takes the ring',
      );
    });

    testWidgets('removing the last card leaves the remote on the empty state, not on nothing', (tester) async {
      await pumpScreen(tester, [entry(key: 'a', title: 'Film A')], tv: true);
      nodeFor(tester, 'a').requestFocus();
      await tester.pumpAndSettle();

      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      await tester.tap(find.text(t.watchlist.remove));
      await tester.pumpAndSettle();

      expect(find.byType(TvWatchlistCard), findsNothing);
      expect(find.text(t.watchlist.empty), findsOneWidget);
      expect(
        FocusManager.instance.primaryFocus?.debugLabel,
        'TvWatchlistStateAction',
        reason: 'a page with the focus and no focused item is one the remote can neither move within nor leave',
      );
    });

    group('the rail (CAT5 on a fourth page)', () {
      testWidgets('LEFT off the first column opens it, on Soort', (tester) async {
        await pumpScreen(tester, sixFilms(), tv: true);
        await openRail(tester);

        expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvWatchlistRailKind');
      });

      testWidgets('it offers Soort, Beschikbaarheid and Sortering, and no Bronnen', (tester) async {
        // DEC-108 (2): a kijklijst item is one identity across every server
        // (hoofdstuk 20), so there is nothing to choose.
        await pumpScreen(tester, sixFilms(), tv: true);
        await openRail(tester);

        final rows = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).rows;
        expect(rows.map((r) => r.label), [t.watchlist.rail.kind, t.watchlist.rail.availability, t.libraries.sort]);
        expect(rows.map((r) => r.label), isNot(contains(t.unifiedCatalog.rail.sources)));
      });

      testWidgets('offline it drops Beschikbaarheid rather than offering a wrong answer', (tester) async {
        await pumpScreen(tester, sixFilms(), tv: true, offline: true);
        await openRail(tester);

        final rows = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).rows;
        expect(rows.map((r) => r.label), [t.watchlist.rail.kind, t.libraries.sort]);
      });

      testWidgets('a row opens a subview in place, and Menu goes one layer back', (tester) async {
        // DEC-108 (4): the opened state is a subview of the rail, not an
        // overlay panel. TOK3's segmented tab strip is what it replaces.
        await pumpScreen(tester, sixFilms(), tv: true);
        await openRail(tester);
        await select(tester);

        expect(find.byKey(tvCatalogFilterRailSubviewKey), findsOneWidget);
        expect(find.byKey(tvCatalogFilterRailKey), findsNothing, reason: 'in place, not over');
        expect(
          find.byType(TvCatalogSortPanel),
          findsNothing,
          reason: 'nothing opens over the page: the rail answers in the space it already occupies',
        );

        await tester.sendKeyEvent(LogicalKeyboardKey.escape);
        await tester.pumpAndSettle();
        expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvWatchlistRailKind');
      });

      testWidgets('the subview opens on the answer the viewer already has', (tester) async {
        await pumpScreen(tester, sixFilms(), tv: true);
        await openRail(tester);
        await select(tester);

        // Soort is Alles, which is the first option.
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvCatalogRailSubviewOption0');
      });

      testWidgets('picking Films narrows the grid and shows up as a tag', (tester) async {
        await pumpScreen(tester, [
          entry(key: 'a', title: 'Film A'),
          entry(key: 'b', title: 'Show B', kind: MediaKind.show),
        ], tv: true);
        await openRail(tester);

        // Soort ▸ Films is the second answer.
        await pickOption(tester, 1);

        expect(find.byType(TvWatchlistCard), findsOneWidget);
        expect(cardFor(tester, 'a'), isNotNull);
        // Back on the rail rows, with the choice named where the viewer can see
        // it while the rail is closed again.
        expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
        final tags = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).tags;
        expect(tags.map((tag) => tag.label), contains(t.watchlist.filterMovies));
      });

      testWidgets('RIGHT out of the rail closes it and puts the remote back on the grid', (tester) async {
        await pumpScreen(tester, sixFilms(), tv: true);
        await openRail(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();

        expect(find.byKey(tvCatalogFilterRailKey), findsNothing);
        expect(nodeFor(tester, 'a').hasFocus, isTrue);
      });

      testWidgets('UP out of the rail closes it and reaches the top navigation', (tester) async {
        var exits = 0;
        await pumpScreen(tester, sixFilms(), tv: true, focusSidebar: () => exits++);
        await openRail(tester);

        await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
        await tester.pumpAndSettle();

        expect(exits, 1);
        expect(
          find.byKey(tvCatalogFilterRailKey),
          findsNothing,
          reason: 'a rail left open with the focus elsewhere costs a column for no reason the viewer can see',
        );
      });
    });

    group('states', () {
      testWidgets('a filter that hides everything says how much it is hiding', (tester) async {
        // Mockup 34 D. An empty kijklijst and a filtered-empty one are different
        // problems, and the count is what separates them.
        await pumpScreen(tester, [
          entry(key: 'a', title: 'Show A', kind: MediaKind.show),
          entry(key: 'b', title: 'Show B', kind: MediaKind.show),
        ], tv: true);
        await openRail(tester);
        await pickOption(tester, 1);

        expect(find.text(t.watchlist.emptyFiltered), findsOneWidget);
        expect(find.text(t.watchlist.emptyFilteredBody(count: 2)), findsOneWidget);
        // Twice on purpose: the state's own way out, and the rail's Wissen row
        // standing open beside it.
        expect(find.text(t.unifiedCatalog.states.clearFilters), findsNWidgets(2));
      });

      testWidgets('and clearing from there brings the grid back', (tester) async {
        await pumpScreen(tester, [entry(key: 'a', title: 'Show A', kind: MediaKind.show)], tv: true);
        await openRail(tester);
        await pickOption(tester, 1);
        expect(find.byType(TvWatchlistCard), findsNothing);

        // RIGHT closes the rail, and with no grid to go back to the remote
        // lands on the one action the state has — which is Filters wissen.
        await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
        await tester.pumpAndSettle();
        expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvWatchlistStateAction');

        await select(tester);
        expect(find.byType(TvWatchlistCard), findsOneWidget);
      });

      testWidgets('an empty kijklijst says something else entirely', (tester) async {
        await pumpScreen(tester, const [], tv: true);

        expect(find.text(t.watchlist.empty), findsOneWidget);
        expect(find.text(t.watchlist.emptyBody), findsOneWidget);
      });
    });
  });
}
