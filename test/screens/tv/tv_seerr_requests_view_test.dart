/// Alle aanvragen on TV, pumped on its own (DEC-108 (3) and (4), mockup 35 C1
/// and 35 D).
///
/// `SeerrRequestsScreen` needs a live Seerr session to reach, and the view takes
/// finished lists and callbacks and owns no provider — which is what lets the
/// contract be asserted without one.
library;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/models/seerr/seerr_request.dart';
import 'package:pleya/screens/tv/tv_seerr_requests_view.dart';
import 'package:pleya/services/seerr/seerr_constants.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/seerr_request_row.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_seerr_card.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

SeerrRequest _request(
  int id, {
  String title = 'Nosferatu',
  SeerrRequestStatus status = SeerrRequestStatus.pending,
  SeerrMediaStatus mediaStatus = SeerrMediaStatus.unknown,
  String? by = 'michel',
  String type = 'movie',
}) => SeerrRequest(
  id: id,
  status: status,
  mediaType: type,
  tmdbId: 1000 + id,
  mediaTitle: title,
  mediaYear: '2024',
  mediaStatus: mediaStatus,
  requestedByName: by,
);

/// What `/request/count` can be shown for. Beschikbaar and Afgewezen have no
/// entry: the count route's "available" is not the list route's, and it has no
/// declined figure at all.
const _counts = {TvSeerrRequestFilter.all: 389, TvSeerrRequestFilter.pending: 27, TvSeerrRequestFilter.approved: 108};

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  late TvSeerrRequestFilter picked;

  Future<void> pumpView(
    WidgetTester tester,
    List<SeerrRequest> requests, {
    TvSeerrRequestFilter filter = TvSeerrRequestFilter.all,
    Map<TvSeerrRequestFilter, int>? counts,
    TvSeerrCountsScope countsScope = TvSeerrCountsScope.all,
    bool loadMoreFailed = false,
    bool filterUnsupported = false,
    VoidCallback? onDiscover,
    VoidCallback? onLoadMore,
    bool isLoading = false,
    String? error,
  }) async {
    picked = filter;
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvSeerrRequestsView(
              title: t.seerr.allRequests,
              requests: requests,
              filter: filter,
              onFilterChanged: (value) => picked = value,
              onActivate: (_) {},
              isLoading: isLoading,
              hasMore: loadMoreFailed,
              isLoadingMore: false,
              loadMoreFailed: loadMoreFailed,
              onLoadMore: onLoadMore ?? () {},
              onReload: () {},
              onDiscover: onDiscover,
              countFor: counts == null ? null : (filter) => counts[filter],
              countsScope: countsScope,
              filterUnsupported: filterUnsupported,
              error: error,
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  Future<void> openRail(WidgetTester tester) async {
    tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).first.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
  }

  Future<void> select(WidgetTester tester) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
  }

  testWidgets('the page is a raster of catalog cards, not the request list (35 C1)', (tester) async {
    await pumpView(tester, [for (var i = 0; i < 6; i++) _request(i, title: 'Title $i')]);

    expect(find.byType(TvSeerrRequestCard), findsNWidgets(6));
    expect(find.byType(TvCatalogCard), findsNWidgets(6));
    expect(
      find.byType(SeerrRequestRow),
      findsNothing,
      reason: '35 C2 was the list, and it is the option DEC-108 did not take',
    );
  });

  testWidgets('a card is exactly as wide as a card on Alle films', (tester) async {
    tester.view.physicalSize = const Size(1038, 584);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await pumpView(tester, [_request(1)]);

    final grid = TvCatalogGrid.forWidth(1038, scale: 0.85);
    expect(tester.widget<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).width, closeTo(grid.cardWidth, 0.01));
  });

  testWidgets('a request card is one line taller than every other catalog card', (tester) async {
    // It says who asked for it, and the grid it sits in has to reserve that or
    // the last row loses its footer into the overscan band.
    await pumpView(tester, [_request(1, by: 'rapmadri')]);

    final card = tester.widget<TvCatalogCard>(find.byType(TvCatalogCard));
    expect(card.tertiary, 'rapmadri');
    expect(
      TvCatalogLayout.cardHeight(card.width, 1, extraMetaLines: 1),
      greaterThan(TvCatalogLayout.cardHeight(card.width, 1)),
    );
  });

  group('who asked is readable on the card, not only announced (UF2)', () {
    // The names of the Verify fixture: the same first seven characters, and
    // then the part that tells them apart.
    const names = ['verify-admin', 'verify-guest'];

    /// The requester line of one card as it was laid out, wherever its text
    /// starts. Looked up by what it contains, so a line that buries the name
    /// behind a prefix is found and judged too, instead of merely not found.
    RenderParagraph requesterLine(WidgetTester tester, String name) =>
        tester.renderObject<RenderParagraph>(find.textContaining(name));

    void expectNamesWhole(WidgetTester tester, String when) {
      for (final name in names) {
        final line = requesterLine(tester, name);
        expect(line.didExceedMaxLines, isFalse, reason: '"$name" is cut off $when');
        final shown = line.text.toPlainText();
        expect(shown.indexOf(name), 0, reason: 'the name leads the line $when, so a cut can only cost its tail');
      }
    }

    Future<void> pumpTv(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1920, 1080);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      await pumpView(tester, [for (var i = 0; i < names.length; i++) _request(i + 1, title: 'Title $i', by: names[i])]);
    }

    testWidgets('at rest, each card shows its whole requester name', (tester) async {
      await pumpTv(tester);
      expectNamesWhole(tester, 'at rest');
    });

    testWidgets('with a card focused', (tester) async {
      await pumpTv(tester);
      tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).first.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      expectNamesWhole(tester, 'with a card focused');
    });

    testWidgets('with the rail open, where the cards are at their narrowest', (tester) async {
      await pumpTv(tester);
      final before = tester.widget<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard).first).width;
      await openRail(tester);
      expect(tester.widget<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard).first).width, lessThanOrEqualTo(before));
      expectNamesWhole(tester, 'with the rail open');
    });

    testWidgets('the full sentence is still what a screen reader hears', (tester) async {
      await pumpTv(tester);
      final labels = tester.widgetList<TvCatalogCard>(find.byType(TvCatalogCard)).map((c) => c.semanticLabel).toList();
      for (var i = 0; i < names.length; i++) {
        expect(labels[i], contains(t.seerr.requestedBy(name: names[i])));
      }
    });
  });

  group('the status capsule', () {
    TvCatalogArtworkBadge badgeOn(WidgetTester tester, int index) =>
        tester.widgetList<TvCatalogArtworkBadge>(find.byType(TvCatalogArtworkBadge)).elementAt(index);

    testWidgets('says where the request stands', (tester) async {
      await pumpView(tester, [
        _request(1, status: SeerrRequestStatus.pending),
        _request(2, status: SeerrRequestStatus.approved),
        _request(3, status: SeerrRequestStatus.declined),
      ]);

      expect(
        [for (var i = 0; i < 3; i++) badgeOn(tester, i).label],
        [t.seerr.pending, t.seerr.approved, t.seerr.declined],
      );
    });

    testWidgets('and availability wins over it, because it is the later fact', (tester) async {
      await pumpView(tester, [
        _request(1, status: SeerrRequestStatus.approved, mediaStatus: SeerrMediaStatus.available),
      ]);

      expect(badgeOn(tester, 0).label, t.seerr.available);
      expect(badgeOn(tester, 0).muted, isFalse, reason: 'the one status that is good news reads at full ink');
    });
  });

  group('the rail (TOK3)', () {
    testWidgets('LEFT off the first column opens it, on Status', (tester) async {
      await pumpView(tester, [_request(1)]);
      await openRail(tester);

      expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
      final rows = tester.widget<TvCatalogFilterRailPanel>(find.byKey(tvCatalogFilterRailKey)).rows;
      expect(rows.map((row) => row.label), [t.seerr.railStatus]);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrRailStatus');
    });

    testWidgets('Status opens a subview with the counts beside each answer (35 D)', (tester) async {
      await pumpView(tester, [_request(1)], counts: _counts);
      await openRail(tester);
      await select(tester);

      expect(find.byKey(tvCatalogFilterRailSubviewKey), findsOneWidget);
      final subview = tester.widget<TvCatalogFilterRailSubview>(find.byKey(tvCatalogFilterRailSubviewKey));
      expect(subview.options.map((option) => option.label), [
        t.seerr.filterAll,
        t.seerr.filterPending,
        t.seerr.filterApproved,
        t.seerr.filterAvailable,
        t.seerr.filterDeclined,
      ]);
      expect(subview.options.map((option) => option.count), [389, 27, 108, null, null]);
      expect(find.text('389'), findsOneWidget);
      expect(find.text('27'), findsOneWidget);
    });

    testWidgets('a status with no count reported shows no number rather than a zero', (tester) async {
      await pumpView(tester, [_request(1)]);
      await openRail(tester);
      await select(tester);

      final subview = tester.widget<TvCatalogFilterRailSubview>(find.byKey(tvCatalogFilterRailSubviewKey));
      expect(subview.options.every((option) => option.count == null), isTrue);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('picking one reports it and returns to the rail row', (tester) async {
      await pumpView(tester, [_request(1)]);
      await openRail(tester);
      await select(tester);

      // Alles is selected, so the subview opens on it; In afwachting is next.
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      await tester.pumpAndSettle();
      await select(tester);

      expect(picked, TvSeerrRequestFilter.pending);
      expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
      expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrRailStatus');
    });

    testWidgets('Menu inside the subview goes one layer back, not out of the page', (tester) async {
      await pumpView(tester, [_request(1)]);
      await openRail(tester);
      await select(tester);
      expect(find.byKey(tvCatalogFilterRailSubviewKey), findsOneWidget);

      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      await tester.pumpAndSettle();

      expect(find.byKey(tvCatalogFilterRailKey), findsOneWidget);
      expect(picked, TvSeerrRequestFilter.all, reason: 'backing out changes nothing');
    });
  });

  group('the heading', () {
    testWidgets('says how many requests there are when nothing is filtered', (tester) async {
      await pumpView(tester, [_request(1)], counts: _counts);

      final strip = tester.widget<TvCatalogSelectionTagStrip>(find.byType(TvCatalogSelectionTagStrip));
      expect(strip.tags.map((tag) => tag.label), [t.seerr.requestCount(count: 389)]);
    });

    testWidgets('and names the status once one is chosen', (tester) async {
      await pumpView(tester, [_request(1)], filter: TvSeerrRequestFilter.pending, counts: _counts);

      final strip = tester.widget<TvCatalogSelectionTagStrip>(find.byType(TvCatalogSelectionTagStrip));
      expect(strip.tags.map((tag) => tag.label), [t.seerr.filterPending]);
    });
  });

  testWidgets('a status with nothing in it says something else than an empty account', (tester) async {
    await pumpView(tester, const [], filter: TvSeerrRequestFilter.declined);

    expect(find.text(t.seerr.noRequestsInFilter(status: t.seerr.filterDeclined)), findsOneWidget);
    expect(find.text(t.unifiedCatalog.states.clearFilters), findsOneWidget);
  });

  testWidgets('and an account with no requests at all says that', (tester) async {
    await pumpView(tester, const []);

    expect(find.text(t.seerr.noRequestsYet), findsOneWidget);
  });

  testWidgets('the entry focus waits for the first page instead of landing nowhere', (tester) async {
    // The page is pushed as a route, so nothing places the focus for it the way
    // `FocusedScrollScaffold` used to. `SeerrRequestsScreen` asks once, a frame
    // after mounting, and at that moment the grid is still a skeleton: the ask
    // has to survive until the requests arrive, or Alle aanvragen opens focused
    // with no item on it, which on tvOS is a page the remote cannot leave.
    final key = GlobalKey<TvSeerrRequestsViewState>();

    Future<void> pumpWith(List<SeerrRequest> requests, {required bool isLoading}) async {
      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Scaffold(
              body: TvSeerrRequestsView(
                key: key,
                title: t.seerr.allRequests,
                requests: requests,
                filter: TvSeerrRequestFilter.all,
                onFilterChanged: (_) {},
                onActivate: (_) {},
                isLoading: isLoading,
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                onReload: () {},
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    await pumpWith(const [], isLoading: true);
    key.currentState!.focusContent();
    await tester.pumpAndSettle();
    expect(find.byType(TvSeerrRequestCard), findsNothing);

    await pumpWith([_request(1), _request(2)], isLoading: false);
    expect(
      tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).any((card) => card.focusNode!.hasFocus),
      isTrue,
      reason: 'the ask made while the grid was a skeleton has to land once the cards are there',
    );
  });

  group('counts say no more than was counted', () {
    testWidgets("the viewer's own list shows no numbers and says why", (tester) async {
      await pumpView(tester, [_request(1)], counts: _counts, countsScope: TvSeerrCountsScope.own);
      expect(find.text(t.seerr.requestCount(count: 389)), findsNothing, reason: 'no global total over an own list');

      await openRail(tester);
      await select(tester);
      final subview = tester.widget<TvCatalogFilterRailSubview>(find.byKey(tvCatalogFilterRailSubviewKey));
      expect(subview.options.every((option) => option.count == null && !option.countUnavailable), isTrue);
      expect(find.text(t.seerr.countsOwnScopeNote), findsOneWidget);
    });

    testWidgets('a count that did not load is a dash, not a zero', (tester) async {
      await pumpView(tester, [_request(1)], countsScope: TvSeerrCountsScope.failed);
      await openRail(tester);
      await select(tester);

      expect(find.text('–'), findsNWidgets(TvSeerrRequestFilter.values.length));
      expect(find.text('0'), findsNothing);
      expect(find.text(t.seerr.countsNotLoaded), findsOneWidget);
    });
  });

  testWidgets('an empty list is sent to Ontdekken instead of offered a retry (TVUX-36)', (tester) async {
    var discovered = 0;
    await pumpView(tester, const [], onDiscover: () => discovered++);

    expect(find.text(t.common.retry), findsNothing);
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrStateAction');
    await select(tester);
    expect(discovered, 1);
  });

  testWidgets('a status the server did not filter on is named as that, with the way back', (tester) async {
    await pumpView(tester, const [], filter: TvSeerrRequestFilter.declined, filterUnsupported: true);

    expect(find.text(t.seerr.filterUnsupportedTitle(status: t.seerr.filterDeclined)), findsOneWidget);
    await select(tester);
    expect(picked, TvSeerrRequestFilter.all);
  });

  testWidgets('a page that failed to load leaves the cards and one retry under them', (tester) async {
    var asked = 0;
    await pumpView(
      tester,
      [for (var i = 0; i < 4; i++) _request(i, title: 'Title $i')],
      loadMoreFailed: true,
      onLoadMore: () => asked++,
    );

    expect(find.byType(TvSeerrRequestCard), findsNWidgets(4));
    tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).first.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    expect(asked, 0, reason: 'a failed page is not asked for again by itself');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSeerrLoadMoreRetry');
    await select(tester);
    expect(asked, 1);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(
      tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).any((card) => card.focusNode!.hasFocus),
      isTrue,
    );
  });

  testWidgets('a busy card says so in place of its status and has no menu', (tester) async {
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvSeerrRequestsView(
              title: t.seerr.allRequests,
              requests: [_request(1), _request(2)],
              filter: TvSeerrRequestFilter.all,
              onFilterChanged: (_) {},
              onActivate: (_) {},
              onContextMenu: (_) {},
              busyIds: const {2},
              isLoading: false,
              hasMore: false,
              isLoadingMore: false,
              onLoadMore: () {},
              onReload: () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final cards = tester.widgetList<TvSeerrRequestCard>(find.byType(TvSeerrRequestCard)).toList();
    expect(cards[0].onContextMenu, isNotNull);
    expect(cards[1].onContextMenu, isNull);
    expect(find.text(t.seerr.actionBusy), findsOneWidget);
  });
}
