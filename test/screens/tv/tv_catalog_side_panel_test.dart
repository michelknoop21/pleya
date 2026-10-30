/// A-06c: the controls of a full-bleed catalog are one panel over the page. The
/// grid stays where it is, every choice is made in the panel, and the remote
/// has a way back from each page of it.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/widgets/tv/tv_catalog_empty_state.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_panel.dart';
import 'package:pleya/widgets/tv/tv_catalog_rail_scaffold.dart';
import 'package:pleya/widgets/tv/tv_catalog_side_panel.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_panel.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/tv_full_bleed_catalog_harness.dart';

const Size _canvas = Size(1038, 584);
const _left = LogicalKeyboardKey.arrowLeft;
const _right = LogicalKeyboardKey.arrowRight;
const _up = LogicalKeyboardKey.arrowUp;
const _down = LogicalKeyboardKey.arrowDown;
const _select = LogicalKeyboardKey.select;
const _menu = LogicalKeyboardKey.escape;

Future<FullBleedHarness> _open(WidgetTester tester, {int titles = 30, bool reduceMotion = false}) async {
  final h = await FullBleedHarness.create([for (var i = 0; i < titles; i++) fakeMovie(i, year: 2000)]);
  await h.pump(tester, canvas: _canvas, reduceMotion: reduceMotion);
  await h.open(tester);
  return h;
}

/// Which label the white pill is on.
String? _focusedRow() => FocusManager.instance.primaryFocus?.debugLabel;

void main() {
  FullBleedHarness.setUpAllTv();

  testWidgets('LEFT off column 0 opens the panel over the page, and the wall does not move', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _right);
    await h.press(tester, _left);
    final before = [h.posterRect(tester, 2), h.posterRect(tester, 7)];
    expect(find.byType(TvCatalogSidePanel), findsNothing);

    await h.press(tester, _left);

    final panel = tester.getRect(find.byType(TvCatalogSidePanel));
    expect(panel.left, closeTo(_canvas.width * 33 / 2000, 0.5), reason: 'stands clear of the left edge');
    expect(panel.width, closeTo(_canvas.width * 667 / 2000, 0.5));
    expect(panel.top, closeTo(_canvas.width * 33 / 2000, 0.5));
    expect(h.posterRect(tester, 2), before[0], reason: 'the grid keeps its place and its six columns');
    expect(h.posterRect(tester, 7), before[1]);
    final dim = tester.widget<AnimatedOpacity>(find.byKey(tvCatalogPanelDimKey));
    expect(dim.opacity, TvCatalogFullBleedLayout.sheetDimAlpha);
    expect(_focusedRow(), contains('TvCatalogRailSubviewOption0'), reason: 'on Bronnen');
  });

  testWidgets('RIGHT closes from anywhere and puts the ring back on the card it came from', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _down);
    expect(h.focused, h.cardLabel(6));
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _down);
    await h.press(tester, _select);
    expect(find.text(sortLabel(UnifiedCatalogSort.oldestAdded)), findsOneWidget, reason: 'on the sort page');

    await h.press(tester, _right);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.focused, h.cardLabel(6));
    final dim = tester.widget<AnimatedOpacity>(find.byKey(tvCatalogPanelDimKey));
    expect(dim.opacity, 0);
  });

  testWidgets('Menu goes back a page, then closes, and never leaves the route on the way', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _down);
    await h.press(tester, _select);

    await h.press(tester, _menu);
    expect(find.byType(TvCatalogSidePanel), findsOneWidget, reason: 'back on the overview');
    expect(_focusedRow(), contains('TvCatalogRailSubviewOption2'), reason: 'on the row that opened the page');
    expect(find.text(sortLabel(UnifiedCatalogSort.oldestAdded)), findsNothing);

    await h.press(tester, _menu);
    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.focused, h.cardLabel(0));

    await h.press(tester, _menu);
    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.coordinator.activeCanPop, isFalse, reason: 'the third Menu leaves the route');
  });

  testWidgets('UP and DOWN stop at the ends of the panel, LEFT on the overview stays', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    final top = _focusedRow();
    await h.press(tester, _up);
    expect(_focusedRow(), top);
    await h.press(tester, _left);
    expect(_focusedRow(), top);
    for (var i = 0; i < 5; i++) {
      await h.press(tester, _down);
    }
    expect(_focusedRow(), contains('TvCatalogRailSubviewOption2'), reason: 'three rows with nothing to clear');
    expect(h.isNavFocused, isFalse);
  });

  testWidgets('sorting happens in the panel, closes it and lands on card 0', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _down);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _down);
    await h.press(tester, _select);
    expect(find.byType(TvCatalogSortPanel), findsNothing, reason: 'no centred modal');

    await h.press(tester, _down);
    await h.press(tester, _select);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.focused, h.cardLabel(0));
    expect(h.client.queries.last.sort?.direction, LibrarySortDirection.descending);
    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.sort, UnifiedCatalogSort.titleDesc);
  });

  testWidgets('choosing the sort in force still closes and goes to the first card', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _down);
    await h.press(tester, _down);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _down);
    await h.press(tester, _select);
    await h.press(tester, _select);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.focused, h.cardLabel(0));
    expect(h.posterRect(tester, 1).top, closeTo(32.44, 0.5), reason: 'at the top of the wall');
  });

  testWidgets('filters batch behind Apply, in the panel', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    expect(find.byType(TvCatalogFilterPanel), findsNothing, reason: 'no centred modal');

    // Status, Unwatched.
    await h.press(tester, _select);
    await h.press(tester, _down);
    await h.press(tester, _select);
    expect(UnifiedWatchFilter.values, contains(UnifiedWatchFilter.unwatched));
    expect(h.client.queries.last.filters, isNot(contains('unwatched')), reason: 'nothing applied yet');
    final queriesBefore = h.client.queries.length;

    await h.press(tester, _menu);
    expect(_focusedRow(), isNotNull);
    await h.press(tester, _select);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.client.queries.length, greaterThan(queriesBefore));
    expect(h.focused, h.cardLabel(0));
    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.filters.watchState, UnifiedWatchFilter.unwatched);
  });

  testWidgets('RIGHT out of a filter session throws the draft away', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    await h.press(tester, _select);
    await h.press(tester, _down);
    await h.press(tester, _select);
    final queries = h.client.queries.length;

    await h.press(tester, _right);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.client.queries.length, queries);
    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.filters.watchState, UnifiedWatchFilter.all);
  });

  testWidgets('a grid emptied by the server under the ring lands in the panel', (tester) async {
    final h = await _open(tester, titles: 8);
    h.client.items = const [];
    await h.catalog.refresh();
    await tester.pumpAndSettle();

    expect(find.byType(TvCatalogEmptyState), findsOneWidget);
    expect(h.isNavFocused, isFalse);
    await h.press(tester, _left);
    expect(find.byType(TvCatalogSidePanel), findsOneWidget, reason: 'the one action opens the panel');
  });

  testWidgets('a filter that leaves nothing lands on the state, and LEFT reaches the panel again', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    await h.press(tester, _select);
    await h.press(tester, _down);
    await h.press(tester, _select);
    h.client.items = const [];
    await h.press(tester, _menu);
    await h.press(tester, _select);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(find.byType(TvCatalogEmptyState), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget);
    expect(h.isNavFocused, isFalse);

    await h.press(tester, _left);
    expect(find.byType(TvCatalogSidePanel), findsOneWidget);
  });

  testWidgets('reduce motion draws the panel at once', (tester) async {
    final h = await _open(tester, reduceMotion: true);
    await tester.sendKeyEvent(_left);
    await tester.pump();
    await tester.pump();
    expect(tester.getRect(find.byType(TvCatalogSidePanel)).left, closeTo(_canvas.width * 33 / 2000, 0.5));
    expect(h.isNavFocused, isFalse);
  });
}
