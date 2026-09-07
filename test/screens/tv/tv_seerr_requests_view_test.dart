/// Alle aanvragen on TV, pumped on its own (DEC-108 (3) and (4), mockup 35 C1
/// and 35 D).
///
/// `SeerrRequestsScreen` needs a live Seerr session to reach, and the view takes
/// finished lists and callbacks and owns no provider — which is what lets the
/// contract be asserted without one.
library;

import 'package:flutter/material.dart';
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

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  late TvSeerrRequestFilter picked;

  Future<void> pumpView(
    WidgetTester tester,
    List<SeerrRequest> requests, {
    TvSeerrRequestFilter filter = TvSeerrRequestFilter.all,
    TvSeerrRequestCounts? counts,
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
              hasMore: false,
              isLoadingMore: false,
              onLoadMore: () {},
              onReload: () {},
              counts: counts,
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

    expect(find.text(t.seerr.requestedBy(name: 'rapmadri')), findsOneWidget);
    final card = tester.widget<TvCatalogCard>(find.byType(TvCatalogCard));
    expect(card.tertiary, t.seerr.requestedBy(name: 'rapmadri'));
    expect(
      TvCatalogLayout.cardHeight(card.width, 1, extraMetaLines: 1),
      greaterThan(TvCatalogLayout.cardHeight(card.width, 1)),
    );
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
      await pumpView(
        tester,
        [_request(1)],
        counts: (total: 389, pending: 27, approved: 108, available: 35, processing: 4),
      );
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
      expect(subview.options.map((option) => option.count), [389, 27, 108, 35, null]);
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
      await pumpView(
        tester,
        [_request(1)],
        counts: (total: 389, pending: 27, approved: 108, available: 35, processing: 4),
      );

      final strip = tester.widget<TvCatalogSelectionTagStrip>(find.byType(TvCatalogSelectionTagStrip));
      expect(strip.tags.map((tag) => tag.label), [t.seerr.requestCount(count: 389)]);
    });

    testWidgets('and names the status once one is chosen', (tester) async {
      await pumpView(
        tester,
        [_request(1)],
        filter: TvSeerrRequestFilter.pending,
        counts: (total: 389, pending: 27, approved: 108, available: 35, processing: 4),
      );

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
}
