/// Zoeken on TV, pumped on its own (DEC-108, mockup 36 A, B and C).
///
/// `SearchScreen` needs a fan-out across live servers to reach; the view takes
/// finished bands and callbacks and owns no provider, which is what lets the
/// contract be asserted without one. The end-to-end path — a real query, real
/// projection, LAND4 between two bands — is in `search_screen_test.dart`.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_search_view.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_rail.dart';
import 'package:pleya/widgets/tv/tv_catalog_empty_state.dart';
import 'package:pleya/widgets/tv/tv_section_header.dart';

TvSearchSection _band(String id, String title, int count, {String? actionLabel, VoidCallback? onAction}) =>
    TvSearchSection(
      id: id,
      title: title,
      itemIds: [for (var i = 0; i < count; i++) '$id-$i'],
      actionLabel: actionLabel,
      onAction: onAction,
      actionFocusNode: onAction == null ? null : FocusNode(debugLabel: 'action.$id'),
      cardBuilder: (context, cell) => TvCatalogCard(
        width: cell.width,
        artwork: const ColoredBox(color: Colors.black),
        title: '$title ${cell.index}',
        meta: '2024  ·  Sciencefiction',
        onSelect: () {},
        focusNode: cell.focusNode,
        onFocusChange: cell.onFocusChange,
        onNavigateUp: cell.onNavigateUp,
        onNavigateDown: cell.onNavigateDown,
        onNavigateLeft: cell.onNavigateLeft,
        onNavigateRight: cell.onNavigateRight,
      ),
    );

void main() {
  setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  late GlobalKey<TvSearchViewState> key;

  Future<void> pumpView(
    WidgetTester tester, {
    List<TvSearchSection> sections = const [],
    bool hasQuery = true,
    bool isSearching = false,
    int? totalResultCount,
    String? error,
    VoidCallback? onRetry,
    VoidCallback? onSearchOnRequests,
    int serverCount = 3,
    VoidCallback? onExitTop,
    VoidCallback? onExitLeft,
  }) async {
    key = GlobalKey<TvSearchViewState>();
    await tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: TvSearchView(
              key: key,
              searchField: const SizedBox(height: 60, key: Key('field')),
              sections: sections,
              hasQuery: hasQuery,
              isSearching: isSearching,
              totalResultCount: totalResultCount,
              error: error,
              onRetry: onRetry,
              onSearchOnRequests: onSearchOnRequests,
              serverCount: serverCount,
              onExitLeft: onExitLeft ?? () {},
              onExitTop: onExitTop ?? () {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  group('36 B: results are catalog cards under a heading', () {
    testWidgets('a section is a band of catalog cards, and its name is a heading (SEARCH1)', (tester) async {
      await pumpView(tester, sections: [_band('movies', 'Films', 4), _band('shows', 'Series', 2)]);

      expect(find.byType(TvCatalogCardRail), findsNWidgets(2));
      expect(find.byType(TvCatalogCard), findsNWidgets(6));
      expect(find.byType(TvSectionHeader), findsNWidgets(2));
    });

    testWidgets('and the heading carries the count, which the focus does not move', (tester) async {
      await pumpView(tester, sections: [_band('movies', 'Films', 4), _band('shows', 'Series', 2)]);

      final headers = tester.widgetList<TvSectionHeader>(find.byType(TvSectionHeader)).toList();
      expect(headers.map((header) => (header.title, header.count)), [('Films', 4), ('Series', 2)]);

      // Move within the first band; the second band's heading is unchanged,
      // which is the whole of SEARCH1: it names a section, not a position.
      tester.widgetList<TvCatalogCard>(find.byType(TvCatalogCard)).first.focusNode!.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();

      final after = tester.widgetList<TvSectionHeader>(find.byType(TvSectionHeader)).toList();
      expect(after.map((header) => (header.title, header.count)), [('Films', 4), ('Series', 2)]);
    });

    testWidgets('the count beside the pill is a statement about the query, not about a band', (tester) async {
      String? label(int? total, {bool hasQuery = true, bool isSearching = false}) =>
          TvSearchViewState.resultCountLabel(hasQuery: hasQuery, isSearching: isSearching, total: total);

      expect(label(14), t.search.resultCount(count: 14));
      expect(label(1), t.search.oneResult);
      expect(label(0), t.search.noResultsShort, reason: '36 C says "geen resultaten" in the pill, not a zero');
      expect(label(14, isSearching: true), isNull, reason: 'a running query has nothing to count yet');
      expect(label(null, hasQuery: false), isNull);
    });
  });

  group('36 B: results still lead to Aanvragen (REQ3)', () {
    testWidgets('a way down from the last band opens Zoek in aanvragen', (tester) async {
      var requested = 0;
      await pumpView(tester, sections: [_band('movies', 'Films', 2)], onSearchOnRequests: () => requested++);

      expect(find.text(t.search.searchOnRequests), findsOneWidget);

      final action = Focus.maybeOf(tester.element(find.text(t.search.searchOnRequests)), scopeOk: true)!;
      action.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(requested, 1);
    });

    testWidgets('without a Seerr the results page offers no way to Aanvragen', (tester) async {
      await pumpView(tester, sections: [_band('movies', 'Films', 2)]);
      expect(find.text(t.search.searchOnRequests), findsNothing);
    });
  });

  group('36 C: nothing found', () {
    testWidgets('names the servers that were searched and offers Aanvragen', (tester) async {
      var requested = 0;
      await pumpView(tester, onSearchOnRequests: () => requested++, serverCount: 3);

      expect(find.text(t.search.nothingOnServersTitle), findsOneWidget);
      expect(find.text(t.search.nothingOnServersBody(count: 3)), findsOneWidget);

      final action = Focus.maybeOf(tester.element(find.text(t.search.searchOnRequests)), scopeOk: true)!;
      action.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
      await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
      expect(requested, 1);
    });

    testWidgets('one server does not get a number it would read wrong', (tester) async {
      await pumpView(tester, onSearchOnRequests: () {}, serverCount: 1);

      expect(find.text(t.search.nothingOnOneServerBody), findsOneWidget);
    });

    testWidgets('without a Seerr it offers Opnieuw, and without either it offers nothing at all', (tester) async {
      await pumpView(tester, onRetry: () {});
      expect(find.text(t.common.retry), findsOneWidget);
      expect(find.text(t.search.searchOnRequests), findsNothing);

      // A label with no callback behind it would draw a button that does
      // nothing, which is the CAT14 shape: `TvCatalogEmptyState` draws only
      // its button, so an inert one is worse than none.
      await pumpView(tester);
      expect(find.text(t.common.retry), findsNothing);
      expect(find.byType(TvCatalogEmptyState), findsOneWidget);
    });
  });

  testWidgets('36 A: at rest the page is the row of titles, with a way to clear it', (tester) async {
    var cleared = 0;
    await pumpView(
      tester,
      hasQuery: false,
      sections: [
        _band('recent', t.search.recentSearches, 3, actionLabel: t.search.clearHistory, onAction: () => cleared++),
      ],
    );

    expect(find.byType(TvCatalogCardRail), findsOneWidget);
    expect(find.text(t.search.recentSearches), findsOneWidget);

    final action = Focus.maybeOf(tester.element(find.text(t.search.clearHistory)), scopeOk: true)!;
    action.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pumpAndSettle();
    expect(cleared, 1);
  });

  testWidgets('with nothing searched and nothing opened, the page says what it is for', (tester) async {
    await pumpView(tester, hasQuery: false);

    expect(find.text(t.search.searchYourMedia), findsOneWidget);
    // No action, and deliberately none: the search field above is focusable and
    // is the only thing to do here, so this state is not a page you can be
    // stranded on the way CAT14's was.
    expect(find.byKey(const Key('field')), findsOneWidget);
  });

  testWidgets('focusFirstResult lands on the first band, and says so when there is none', (tester) async {
    await pumpView(tester, sections: [_band('movies', 'Films', 3)]);
    expect(key.currentState!.focusFirstResult(), isTrue);
    await tester.pumpAndSettle();
    expect(FocusManager.instance.primaryFocus?.debugLabel, 'TvSearchCard(movies)(movies-0)');

    // A running query is a body of skeletons: the caller keeps the focus on the
    // field rather than dropping it into a page with nowhere to put it.
    await pumpView(tester, isSearching: true);
    expect(key.currentState!.focusFirstResult(), isFalse);
  });

  testWidgets('UP out of the first band is the search field above it', (tester) async {
    var exits = 0;
    await pumpView(tester, sections: [_band('movies', 'Films', 3)], onExitTop: () => exits++);

    tester.widgetList<TvCatalogCard>(find.byType(TvCatalogCard)).first.focusNode!.requestFocus();
    await tester.pumpAndSettle();
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowUp);
    await tester.pumpAndSettle();
    expect(exits, 1);
  });

  group('LEFT off the one action an error or no-results state has', () {
    // Every sibling empty state on the catalog-language pages wires
    // `onActionNavigateLeft` so LEFT reaches the sidebar — directional
    // traversal cannot cross from this page's content `FocusScope` to that
    // one on its own. These two states drew the button without it: LEFT did
    // nothing on the one state a viewer most wants out of.
    testWidgets('on the error state', (tester) async {
      var exits = 0;
      await pumpView(tester, error: 'boom', onRetry: () {}, onExitLeft: () => exits++);

      final action = Focus.maybeOf(tester.element(find.text(t.common.retry)), scopeOk: true)!;
      action.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(exits, 1);
    });

    testWidgets('on the no-results state (36 C)', (tester) async {
      var exits = 0;
      await pumpView(tester, onSearchOnRequests: () {}, onExitLeft: () => exits++);

      final action = Focus.maybeOf(tester.element(find.text(t.search.searchOnRequests)), scopeOk: true)!;
      action.requestFocus();
      await tester.pumpAndSettle();
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expect(exits, 1);
    });
  });
}
