/// A-06c: the controls of a full-bleed catalog are one panel over the page. The
/// grid stays where it is, every choice is made in the panel, and the remote
/// has a way back from each page of it.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/library_menu_definition.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_catalog_empty_state.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_panel.dart';
import 'package:pleya/widgets/tv/tv_catalog_rail_scaffold.dart';
import 'package:pleya/utils/home_custom_row_labels.dart';
import 'package:pleya/widgets/tv/tv_catalog_selection_tags.dart';
import 'package:pleya/widgets/tv/tv_catalog_side_panel.dart';
import 'package:pleya/widgets/tv/tv_catalog_filter_rail_rows.dart';
import 'package:pleya/widgets/tv/tv_catalog_sort_fields.dart';
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

Finder _panelScroll() => find.descendant(of: find.byType(TvCatalogSidePanel), matching: find.byType(Scrollable));

void main() {
  FullBleedHarness.setUpAllTv();

  group('RIGHT and straight back with LEFT, while the panel is still sliding out', () {
    // Not `h.press`: that settles, and the whole point is the 240 ms it would
    // wait out.
    Future<void> tap(WidgetTester tester, LogicalKeyboardKey key, {int ms = 80}) async {
      await tester.sendKeyEvent(key);
      await tester.pump();
      await tester.pump(Duration(milliseconds: ms));
    }

    Future<FullBleedHarness> openPanel(WidgetTester tester) async {
      final h = await _open(tester);
      await h.press(tester, _right);
      await h.press(tester, _left);
      await h.press(tester, _left);
      expect(find.byType(TvCatalogSidePanel), findsOneWidget);
      return h;
    }

    testWidgets('no duplicate key, one panel left, and the remote is in it', (tester) async {
      await openPanel(tester);

      await tap(tester, _right);
      expect(find.byType(TvCatalogSidePanel), findsOneWidget, reason: 'the outgoing panel is still on its way out');
      await tap(tester, _left);
      expect(tester.takeException(), isNull);
      expect(find.byType(TvCatalogSidePanel), findsNWidgets(2), reason: 'one going, one coming');

      await tester.pumpAndSettle();
      expect(tester.takeException(), isNull);
      expect(find.byType(TvCatalogSidePanel), findsOneWidget);
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption0'), reason: 'on Bronnen, of the new panel');
    });

    testWidgets('the reopened panel works: Menu closes it and the ring is back on a card', (tester) async {
      final h = await openPanel(tester);
      await tap(tester, _right);
      await tap(tester, _left);
      await tester.pumpAndSettle();

      await h.press(tester, _menu);
      expect(find.byType(TvCatalogSidePanel), findsNothing);
      expect(tester.takeException(), isNull);
      expect(_focusedRow(), isNot(contains('TvCatalogRailSubviewOption')));
    });

    testWidgets('back and forth several times leaves nothing behind', (tester) async {
      await openPanel(tester);
      for (var i = 0; i < 3; i++) {
        await tap(tester, _right);
        await tap(tester, _left);
        expect(tester.takeException(), isNull);
      }
      await tester.pumpAndSettle();
      expect(find.byType(TvCatalogSidePanel), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

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
    expect(
      find.text(tvCatalogSortFieldLabel(UnifiedCatalogSortField.addedAt)),
      findsOneWidget,
      reason: 'on the sort page',
    );

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
    expect(find.text(tvCatalogSortFieldLabel(UnifiedCatalogSortField.addedAt)), findsNothing);

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
    expect(_focusedRow(), contains('TvCatalogRailSubviewOption3'), reason: 'four rows with nothing to clear');
    expect(h.isNavFocused, isFalse);
  });

  testWidgets('another field is chosen in its own default direction, in the panel, and lands on card 0', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.press(tester, _down);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _down);
    await h.press(tester, _select);
    expect(find.byType(TvCatalogSortPanel), findsNothing, reason: 'no centred modal');

    for (var i = 0; i < librarySortMenu.indexOf(UnifiedCatalogSortField.addedAt); i++) {
      await h.press(tester, _down);
    }
    await h.press(tester, _select);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.focused, h.cardLabel(0));
    expect(h.client.queries.last.sort?.direction, LibrarySortDirection.descending);
    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.sort, UnifiedCatalogSort.recentlyAdded, reason: 'dates start with the newest');
  });

  testWidgets('choosing the field in force turns its direction, closes and goes to the first card', (tester) async {
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
    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.sort, UnifiedCatalogSort.titleDesc, reason: 'A-Z turned into Z-A');
  });

  testWidgets('the overview shows no dashed sort tag on the default sort, and filter tags and Wissen stay', (
    tester,
  ) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    expect(find.byType(TvCatalogSelectionTagStrip), findsNothing, reason: 'default sort, no filters');
    expect(find.text('Clear filters'), findsNothing);

    final f = await FullBleedHarness.create([for (var i = 0; i < 30; i++) fakeMovie(i, year: 2000)]);
    await UnifiedCatalogQueryStore.write(
      f.catalog.query.kind,
      UnifiedCatalogPreferences.defaults.copyWith(
        filters: const UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched),
      ),
    );
    await f.pump(tester, canvas: _canvas);
    await f.open(tester);
    await f.press(tester, _left);

    expect(find.byType(TvCatalogSelectionTagStrip), findsOneWidget);
    expect(find.text(unifiedWatchFilterLabel(UnifiedWatchFilter.unwatched)), findsOneWidget);
    expect(find.text('Clear filters'), findsOneWidget, reason: 'Wissen stays while a filter is active');
  });

  group('sort page, one row per field', () {
    Future<FullBleedHarness> openSortPage(WidgetTester tester, {UnifiedCatalogSort? sort}) async {
      final h = await FullBleedHarness.create([for (var i = 0; i < 30; i++) fakeMovie(i, year: 2000)]);
      if (sort != null) {
        await UnifiedCatalogQueryStore.write(
          h.catalog.query.kind,
          UnifiedCatalogPreferences.defaults.copyWith(sort: sort),
        );
      }
      await h.pump(tester, canvas: _canvas);
      await h.open(tester);
      await h.press(tester, _left);
      await h.press(tester, _down);
      await h.press(tester, _down);
      await h.press(tester, _select);
      return h;
    }

    testWidgets('shows a row per field, the direction arrow on the active one only', (tester) async {
      await openSortPage(tester);

      for (final field in UnifiedCatalogSortField.values) {
        await tester.scrollUntilVisible(find.text(tvCatalogSortFieldLabel(field)), 40, scrollable: _panelScroll());
        expect(find.text(tvCatalogSortFieldLabel(field)), findsOneWidget, reason: field.name);
      }
      expect(find.text(sortLabel(UnifiedCatalogSort.titleAsc)), findsNothing, reason: 'no row per direction');
      expect(find.byIcon(Symbols.arrow_downward_rounded), findsOneWidget);
      expect(find.byIcon(Symbols.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Symbols.check_rounded), findsNothing, reason: 'the arrow stands in for the tick');
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption0'), reason: 'opens on the active row');
    });

    testWidgets('a source that cannot run a field leaves its row out, and the active arrow is the accent', (
      tester,
    ) async {
      final h = await FullBleedHarness.create([for (var i = 0; i < 30; i++) fakeMovie(i, year: 2000)]);
      h.client.sortKeys = const ['titleSort', 'rating'];
      await h.pump(tester, canvas: _canvas);
      await h.open(tester);
      await h.press(tester, _left);
      await h.press(tester, _down);
      await h.press(tester, _down);
      await h.press(tester, _select);

      final labels = [
        for (final row in tester.widgetList<TvCatalogRailSheetRow>(find.byType(TvCatalogRailSheetRow)))
          row.option.label,
      ];
      expect(labels, ['Title', 'Release date', 'Critics', 'Added', 'Watched']);
      final arrow = tester.widget<Icon>(find.byIcon(Symbols.arrow_downward_rounded));
      expect(arrow.color, tokens(tester.element(find.byType(TvCatalogSidePanel))).accent);
    });

    testWidgets('a sort the sources cannot run reads title, and comes back with them', (tester) async {
      final h = await FullBleedHarness.create([for (var i = 0; i < 12; i++) fakeMovie(i, year: 2000)]);
      await UnifiedCatalogQueryStore.write(
        h.catalog.query.kind,
        UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.mostProgress),
      );
      h.client.sortKeys = const ['titleSort'];
      await h.pump(tester, canvas: _canvas);
      await h.open(tester);

      expect(h.catalog.query.sortField, UnifiedCatalogSortField.title);
      await h.press(tester, _left);
      await h.press(tester, _down);
      await h.press(tester, _down);
      expect(find.text(sortLabel(UnifiedCatalogSort.titleAsc)), findsOneWidget, reason: 'the row says what runs');
      expect((await UnifiedCatalogQueryStore.read(h.catalog.query.kind)).sort, UnifiedCatalogSort.mostProgress);
    });

    testWidgets('the same row again turns the direction over, and the way back stays open', (tester) async {
      final h = await openSortPage(tester);
      await h.press(tester, _select);
      expect(find.byType(TvCatalogSidePanel), findsNothing);
      expect((await UnifiedCatalogQueryStore.read(h.catalog.query.kind)).sort, UnifiedCatalogSort.titleDesc);

      // Reopen: Menu is not needed to reach it, LEFT and the sort row are.
      await h.press(tester, _left);
      await h.press(tester, _down);
      await h.press(tester, _down);
      await h.press(tester, _select);
      expect(find.byIcon(Symbols.arrow_upward_rounded), findsOneWidget, reason: 'Z-A reads upward');
      await h.press(tester, _select);
      expect((await UnifiedCatalogQueryStore.read(h.catalog.query.kind)).sort, UnifiedCatalogSort.titleAsc);
    });

    testWidgets('Menu on the page goes back to the overview and changes nothing', (tester) async {
      final h = await openSortPage(tester);
      await h.press(tester, _menu);
      expect(find.byType(TvCatalogSidePanel), findsOneWidget);
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption2'));
      expect((await UnifiedCatalogQueryStore.read(h.catalog.query.kind)).sort, UnifiedCatalogSort.titleAsc);
    });

    testWidgets('a field with one direction has no arrow and keeps its sort when chosen again', (tester) async {
      final h = await openSortPage(tester, sort: UnifiedCatalogSort.recentlyWatched);
      expect(find.byIcon(Symbols.arrow_downward_rounded), findsNothing);
      expect(find.byIcon(Symbols.arrow_upward_rounded), findsNothing);
      expect(find.byIcon(Symbols.check_rounded), findsOneWidget, reason: 'the tick marks the field instead');
      expect(
        _focusedRow(),
        contains('TvCatalogRailSubviewOption${librarySortMenu.indexOf(UnifiedCatalogSortField.recentlyWatched)}'),
      );

      await h.press(tester, _select);

      expect(find.byType(TvCatalogSidePanel), findsNothing);
      expect((await UnifiedCatalogQueryStore.read(h.catalog.query.kind)).sort, UnifiedCatalogSort.recentlyWatched);
    });

    test('every sort is reachable from its field, and only reversible fields turn over', () {
      for (final sort in UnifiedCatalogSort.values) {
        final other = UnifiedCatalogSortField.values.firstWhere((f) => f != sort.field);
        expect(tvCatalogSortAfterChoosing(sort, other).field, other);
        expect(tvCatalogCanReverse(sort), sort != UnifiedCatalogSort.recentlyWatched);
      }
      expect(
        tvCatalogSortAfterChoosing(UnifiedCatalogSort.titleAsc, UnifiedCatalogSortField.title),
        UnifiedCatalogSort.titleDesc,
      );
      expect(
        tvCatalogSortAfterChoosing(UnifiedCatalogSort.titleDesc, UnifiedCatalogSortField.addedAt),
        UnifiedCatalogSort.recentlyAdded,
      );
      expect(
        tvCatalogSortAfterChoosing(UnifiedCatalogSort.titleAsc, UnifiedCatalogSortField.releaseDate),
        UnifiedCatalogSort.newestRelease,
      );
      expect(
        tvCatalogSortAfterChoosing(UnifiedCatalogSort.oldestRelease, UnifiedCatalogSortField.title),
        UnifiedCatalogSort.titleAsc,
      );
    });
  });

  testWidgets('a quick choice applies at once and lands on card 0', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    expect(find.byType(TvCatalogFilterPanel), findsNothing, reason: 'no centred modal');
    expect(_focusedRow(), contains('TvCatalogRailSubviewOption0'), reason: 'on Alles');

    // Alles, Ongekeken: Plex listed no media filter here.
    await h.press(tester, _down);
    await h.press(tester, _select);

    expect(find.byType(TvCatalogSidePanel), findsNothing);
    expect(h.focused, h.cardLabel(0));
    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.filters.watchState, UnifiedWatchFilter.unwatched);
  });

  testWidgets('the filter page is the definition: quick choices, a line, the categories', (tester) async {
    final h = await FullBleedHarness.create([for (var i = 0; i < 30; i++) fakeMovie(i, year: 2000)]);
    h.client.filterKeys = const ['hdr', 'duplicate'];
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);

    final labels = [
      for (final row in tester.widgetList<TvCatalogRailSheetRow>(find.byType(TvCatalogRailSheetRow))) row.option.label,
    ];
    expect(labels.take(6), ['All', 'HDR', 'Unwatched', 'In progress', 'Duplicates', 'Genre']);
    expect(labels, containsAllInOrder(['Genre', 'Year', 'Decade']));
    expect(
      tester.widgetList<TvCatalogRailSheetRow>(find.byType(TvCatalogRailSheetRow)).where((r) => r.option.dividerAbove),
      hasLength(1),
    );
  });

  testWidgets('a media quick choice runs as the boolean Plex listed', (tester) async {
    final h = await FullBleedHarness.create([for (var i = 0; i < 30; i++) fakeMovie(i, year: 2000)]);
    h.client.filterKeys = const ['hdr'];
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    await h.press(tester, _down);
    await h.press(tester, _select);

    final stored = await UnifiedCatalogQueryStore.read(h.catalog.query.kind);
    expect(stored.filters.mediaFilter, LibraryQuickFilter.hdr);
    expect(h.catalog.query.filters.single.field, 'hdr');
  });

  testWidgets('RIGHT out of a filter session changes nothing', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    await h.press(tester, _down);
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

  group('Spring naar', () {
    Future<FullBleedHarness> byLetter(WidgetTester tester, {Future<void>? laterPages}) async {
      final h = await FullBleedHarness.create([
        for (var i = 0; i < 130; i++) fakeMovie(i, title: '${String.fromCharCode(65 + i ~/ 5)} ${i % 5}'),
      ]);
      if (laterPages != null) h.client.pageGate = (query) async => query.offset > 0 ? laterPages : null;
      await h.pump(tester, canvas: _canvas);
      await h.open(tester);
      return h;
    }

    testWidgets('sits under Sort on a page sorted on title, and picks a letter in the panel', (tester) async {
      final h = await byLetter(tester);
      await h.press(tester, _left);
      for (var i = 0; i < 3; i++) {
        await h.press(tester, _down);
      }
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption3'));
      await h.press(tester, _select);
      expect(find.text('Jump to'), findsOneWidget, reason: 'the page title');
      expect(find.text('A'), findsOneWidget);

      // Down the list to K: # A B C D E F G H I J K.
      for (var i = 0; i < 11; i++) {
        await h.press(tester, _down);
      }
      final row = tester.getRect(find.text('K'));
      final panel = tester.getRect(find.byType(TvCatalogSidePanel));
      expect(row.bottom, lessThanOrEqualTo(panel.bottom), reason: 'the list follows the focus');

      await h.press(tester, _select);

      expect(find.byType(TvCatalogSidePanel), findsNothing);
      expect(h.focused, h.cardLabel(10 * 5), reason: 'the first K');
      final top = tester.getRect(find.text('K 0'));
      expect(top.bottom, lessThanOrEqualTo(_canvas.height), reason: 'and it is on screen');
    });

    testWidgets('Menu on the letters goes back to the overview, on the row it came from', (tester) async {
      final h = await byLetter(tester);
      await h.press(tester, _left);
      for (var i = 0; i < 3; i++) {
        await h.press(tester, _down);
      }
      await h.press(tester, _select);
      await h.press(tester, _menu);
      expect(find.byType(TvCatalogSidePanel), findsOneWidget);
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption3'));
      expect(h.isNavFocused, isFalse);
    });

    testWidgets('moving on while it looks leaves the ring where the viewer put it', (tester) async {
      final gate = Completer<void>();
      // Everything past page one waits, so Z is not known yet.
      final h = await byLetter(tester, laterPages: gate.future);
      await h.press(tester, _left);
      for (var i = 0; i < 3; i++) {
        await h.press(tester, _down);
      }
      await h.press(tester, _select);
      for (var i = 0; i < 26; i++) {
        await h.press(tester, _down);
      }
      final loadedBefore = h.catalog.snapshot.groups.length;
      expect(loadedBefore, lessThan(130));

      await h.press(tester, _select);
      expect(find.byType(TvCatalogSidePanel), findsNothing);
      expect(h.focused, h.cardLabel(0), reason: 'the ring waits on its card');
      await h.press(tester, _right);
      expect(h.focused, h.cardLabel(1));

      gate.complete();
      await tester.pumpAndSettle();
      await tester.pump(const Duration(milliseconds: 300));
      await tester.pumpAndSettle();
      expect(h.catalog.snapshot.groups.length, greaterThan(loadedBefore));
      expect(h.focused, h.cardLabel(1), reason: 'late content does not take the remote back');
    });

    testWidgets('is offered on Z-A too, and lands on the first K from the other end', (tester) async {
      final h = await FullBleedHarness.create([
        for (var i = 0; i < 130; i++) fakeMovie(i, title: '${String.fromCharCode(65 + i ~/ 5)} ${i % 5}'),
      ]);
      await UnifiedCatalogQueryStore.write(
        h.catalog.query.kind,
        UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.titleDesc),
      );
      await h.pump(tester, canvas: _canvas);
      await h.open(tester);
      await h.press(tester, _left);
      for (var i = 0; i < 3; i++) {
        await h.press(tester, _down);
      }
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption3'));
      await h.press(tester, _select);
      expect(find.text('Jump to'), findsOneWidget, reason: 'the page title, so the row was there');
    });

    testWidgets('is not offered on a page sorted on anything else', (tester) async {
      final h = await FullBleedHarness.create([for (var i = 0; i < 12; i++) fakeMovie(i, year: 2000)]);
      await UnifiedCatalogQueryStore.write(
        h.catalog.query.kind,
        UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.recentlyAdded),
      );
      await h.pump(tester, canvas: _canvas);
      await h.open(tester);
      await h.press(tester, _left);
      expect(find.text('Jump to'), findsNothing);
      for (var i = 0; i < 5; i++) {
        await h.press(tester, _down);
      }
      expect(_focusedRow(), contains('TvCatalogRailSubviewOption2'), reason: 'Sort is the last row');
    });
  });

  testWidgets('a filter that leaves nothing lands on the state, and LEFT reaches the panel again', (tester) async {
    final h = await _open(tester);
    await h.press(tester, _left);
    await h.press(tester, _down);
    await h.press(tester, _select);
    await h.press(tester, _down);
    h.client.items = const [];
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
