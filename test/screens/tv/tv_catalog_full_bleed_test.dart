/// A-06c: Alle films and Alle series as a wall of six by two on the whole
/// window, through the production shell. The grid is measured, not derived.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query_store.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_catalog_compact_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_header_bar.dart';
import 'package:pleya/widgets/tv/tv_catalog_row_alignment.dart';
import 'package:pleya/widgets/tv/tv_catalog_skeleton_grid.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

import '../../test_helpers/tv_full_bleed_catalog_harness.dart';

const Size _canvas = Size(1038, 584);

/// The part of the 1038 by 584 window the grid draws in.
Rect _visibleBand(WidgetTester tester) {
  final clip = tester.widget<ClipRect>(
    find.descendant(of: find.byType(TvCatalogCardGrid), matching: find.byType(ClipRect)).first,
  );
  return clip.clipper!.getClip(_canvas);
}

Future<FullBleedHarness> _harness([int titles = 30]) =>
    FullBleedHarness.create([for (var i = 0; i < titles; i++) fakeMovie(i, year: 2000 + i % 20)]);

void main() {
  FullBleedHarness.setUpAllTv();
  setUpAll(() => initializeDateFormatting('en'));

  testWidgets('six by two whole cards on 1038 by 584, with the poster it measures', (tester) async {
    final h = await _harness();
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);

    // Card 0 holds the focus and is scaled, so the resting poster is card 1.
    final first = h.posterRect(tester, 1);
    final next = h.posterRect(tester, 2);
    final below = h.posterRect(tester, 7);
    debugPrint(
      'A-06c poster on 1038x584: ${first.width.toStringAsFixed(2)} x ${first.height.toStringAsFixed(2)} logical, '
      '${(first.width * 1.85).toStringAsFixed(1)} x ${(first.height * 1.85).toStringAsFixed(1)} pt; '
      'column pitch ${(next.left - first.left).toStringAsFixed(2)}, '
      'row pitch ${(below.top - first.top).toStringAsFixed(2)}, top ${first.top.toStringAsFixed(2)}',
    );

    expect(find.byType(TvCatalogCompactCard), findsNWidgets(30));
    expect(find.byType(TvCatalogHeaderBar), findsNothing, reason: 'no heading above the grid');
    expect(first.width, greaterThanOrEqualTo(137), reason: 'the floor the plan set for reporting back');
    expect(first.width / first.height, closeTo(2 / 3, 0.01));

    // Exactly six in the row, the seventh on the next one.
    expect(h.posterRect(tester, 5).top, first.top);
    expect(below.top, greaterThan(first.top));
    expect(h.posterRect(tester, 5).right, lessThanOrEqualTo(_canvas.width));

    // The second row and its footer are whole, the third is cut away.
    final clip = _visibleBand(tester);
    expect(below.bottom + 37, lessThanOrEqualTo(clip.bottom), reason: 'two rows with footer inside the band');
    expect(h.posterRect(tester, 13).top, greaterThanOrEqualTo(clip.bottom), reason: 'no strip of a third row');
  });

  testWidgets('the band shows nothing of the row above, and leaves the focused ring and footer whole', (tester) async {
    final h = await _harness(36);
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(h.focused, h.cardLabel(12));

    final clip = _visibleBand(tester);
    // Row 1 is the top row now, row 2 holds the focus.
    final rest = h.posterRect(tester, 7);
    final reach = TvCatalogFullBleedLayout.focusedRingReach(rest.height, 0.85);
    expect(rest.top - reach, greaterThanOrEqualTo(clip.top), reason: 'the ring of the top row fits the band');
    final aboveFooterBottom = h.posterRect(tester, 1).bottom + 37;
    expect(aboveFooterBottom, lessThanOrEqualTo(clip.top + 0.01), reason: 'the year above is cut away');

    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(h.focused, h.cardLabel(18));
    final focusedFooter = tester.getRect(find.text('T018'));
    final shift = TvCatalogFullBleedLayout.focusedFooterShift(rest.height, 0.85);
    expect(focusedFooter.top + 31, lessThanOrEqualTo(clip.bottom), reason: 'the shifted footer stays inside');
    expect(shift, lessThan(10), reason: 'it shifts by less than the row gap');
  });

  testWidgets('the Apple TV canvas gives the same wall, up behind the bar', (tester) async {
    final h = await _harness();
    await h.pump(tester);
    await h.open(tester);

    expect(h.isNavFocused, isFalse);
    expect(h.focused, h.cardLabel(0));
    final first = h.posterRect(tester, 1);
    // Reads the grid's own box: the route covers the window, not the band below the bar.
    final grid = h.logical(tester.getRect(find.byType(TvCatalogCardGrid)));
    expect(grid.top, closeTo(0, 0.01));
    expect(grid.height, closeTo(h.windowHeight, 0.01));
    expect(first.top, closeTo(h.windowHeight * 60 / 1080, 0.01));
    expect(h.posterRect(tester, 7).bottom + 37, lessThanOrEqualTo(h.windowHeight));
    debugPrint(
      'A-06c poster on the Apple TV canvas: ${first.width.toStringAsFixed(2)} x ${first.height.toStringAsFixed(2)}',
    );
  });

  testWidgets('focus scales the poster alone: neighbours and the row stay put', (tester) async {
    final h = await _harness();
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    final restRight = h.posterRect(tester, 1);
    final title = find.text('T001');
    final restTitle = tester.getRect(title);

    await h.press(tester, LogicalKeyboardKey.arrowRight);

    expect(h.focused, h.cardLabel(1));
    final focused = h.posterRect(tester, 1);
    expect(focused.width, closeTo(restRight.width * TvCatalogFullBleedLayout.posterFocusScale, 0.01));
    expect(focused.center.dx, closeTo(restRight.center.dx, 0.01), reason: 'about its own centre');
    expect(h.posterRect(tester, 2).left, greaterThan(focused.right), reason: 'the neighbour keeps its place');

    final focusedTitle = tester.getRect(title);
    expect(focusedTitle.width, restTitle.width, reason: 'the footer is not scaled');
    final reach = TvCatalogFullBleedLayout.focusedRingReach(restRight.height, 0.85);
    expect(focusedTitle.top, greaterThanOrEqualTo(restRight.bottom + reach), reason: 'the ring clears the title');
    expect(find.byType(TvCatalogCardGrid), findsOneWidget);
    expect(h.posterRect(tester, 7).top, h.posterRect(tester, 8).top);
  });

  testWidgets('rest and focus keep a focus ring clear of both rows', (tester) async {
    final h = await _harness();
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    final rowZeroYear = tester.getRect(find.text('2000').first);
    final focused = h.posterRect(tester, 6);
    expect(h.focused, h.cardLabel(6));
    final ringTop = focused.top - (FocusTheme.focusBorderWidth + TvCatalogFullBleedLayout.ringGap * 0.85);
    expect(
      ringTop,
      greaterThanOrEqualTo(rowZeroYear.bottom - 1),
      reason: 'the ring may touch the line box, not the text',
    );
  });

  testWidgets('UP from the first row goes nowhere, the bar stays away, Menu leaves', (tester) async {
    final h = await _harness();
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);

    await h.press(tester, LogicalKeyboardKey.arrowUp);
    expect(h.focused, h.cardLabel(0));
    expect(h.isNavFocused, isFalse);

    await h.press(tester, LogicalKeyboardKey.escape);
    expect(find.byType(TvCatalogCardGrid), findsNothing, reason: 'Menu pops the route');
  });

  testWidgets('DOWN walks whole pages of two rows, also past the first', (tester) async {
    final h = await _harness(36);
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    final top = h.posterRect(tester, 1).top;
    final pitch = h.posterRect(tester, 7).top - top;

    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(h.focused, h.cardLabel(6));
    expect(h.posterRect(tester, 1).top, top, reason: 'the second row is already on screen');

    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(h.focused, h.cardLabel(12));
    expect(h.posterRect(tester, 7).top, closeTo(top, 0.5), reason: 'moved by exactly one row');
    expect(h.posterRect(tester, 13).top, closeTo(top + pitch, 0.5));

    await h.press(tester, LogicalKeyboardKey.arrowLeft);
    expect(h.focused, isNot(h.cardLabel(11)), reason: 'column 0 opens the rail, it does not wrap');
  });

  testWidgets('a row change followed by LEFT and RIGHT stays in the new row', (tester) async {
    final h = await _harness(36);
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);

    await h.press(tester, LogicalKeyboardKey.arrowRight);
    await h.press(tester, LogicalKeyboardKey.arrowRight);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(h.focused, h.cardLabel(8));
    await h.press(tester, LogicalKeyboardKey.arrowLeft);
    expect(h.focused, h.cardLabel(7));
    await h.press(tester, LogicalKeyboardKey.arrowRight);
    expect(h.focused, h.cardLabel(8));
  });

  testWidgets('the last row shows the footer under it', (tester) async {
    final h = await _harness(13);
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    await h.press(tester, LogicalKeyboardKey.arrowDown);
    expect(h.focused, h.cardLabel(12));
    final count = tester.getRect(find.text('13 titles'));
    expect(count.bottom, lessThanOrEqualTo(_visibleBand(tester).bottom));
  });

  testWidgets('the skeleton stands where the cards land', (tester) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final grid = TvCatalogFullBleedLayout.grid(width: _canvas.width, height: _canvas.height, scale: 0.85);

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Material(
          child: SizedBox(
            width: _canvas.width,
            height: _canvas.height,
            child: const TvCatalogSkeletonGrid(fullBleed: true),
          ),
        ),
      ),
    );
    final posters = find.byKey(tvCatalogPosterKey);
    expect(posters, findsNWidgets(12));
    final first = tester.getRect(posters.at(0));
    expect(first.width, closeTo(grid.cardWidth, 0.01));
    expect(first.left, closeTo(grid.inset, 0.01));
    expect(first.top, closeTo(grid.topInset!, 0.01));
    expect(tester.getRect(posters.at(6)).top - first.top, closeTo(first.height + 37 + grid.rowGutter, 0.5));
    expect(tester.takeException(), isNull);
  });

  testWidgets('density 3 to 5 keep the full size, 1 and 2 give margin and stay six by two', (tester) async {
    for (final density in [1, 2, 3, 5]) {
      final scale = tvCatalogDensityScale(density);
      final grid = TvCatalogFullBleedLayout.grid(width: 1038, height: 584, scale: 0.85, density: scale);
      final full = TvCatalogFullBleedLayout.grid(width: 1038, height: 584, scale: 0.85);
      final rowsEnd = grid.topInset! + 2 * TvCatalogFullBleedLayout.cardHeight(grid.cardWidth, 0.85) + grid.rowGutter;
      expect(rowsEnd, closeTo(584 - grid.bottomSafeMargin, 0.01), reason: 'density $density');
      expect(grid.columns, 6);
      if (density >= 3) {
        expect(grid.cardWidth, full.cardWidth);
      } else {
        expect(grid.cardWidth, lessThan(full.cardWidth));
        expect(grid.inset, greaterThan(full.inset));
        expect(grid.topInset, greaterThan(full.topInset!));
      }
    }
  });

  testWidgets('going offline on this route removes it with its destination', (tester) async {
    final h = await _harness();
    await h.pump(tester, canvas: _canvas);
    h.coordinator.activate(TvDestinationId.movies);
    await tester.pumpAndSettle();
    await h.open(tester);
    expect(find.byType(TvCatalogCardGrid), findsOneWidget);

    final displaced = h.coordinator.updateConditions(const TvNavConditions(hasLiveTv: false, isOffline: true));
    await tester.pumpAndSettle();

    expect(displaced, isNotNull, reason: 'Films is not in the offline bar');
    expect(h.coordinator.activeCanPop, isFalse);
    expect(find.byType(TvCatalogCardGrid), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('when the card with the ring leaves and none survive, onEmptied gets the remote', (tester) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    var emptied = 0;
    var exitedTop = 0;
    FocusNode? first;

    Widget grid(List<String> ids) => MaterialApp(
      theme: monoTheme(dark: true),
      home: InputModeTracker(
        child: Material(
          child: TvCatalogCardGrid(
            itemIds: ids,
            cardHeight: (width) => TvCatalogFullBleedLayout.cardHeight(width, 0.85),
            hasMore: false,
            isLoadingMore: false,
            onLoadMore: () {},
            onExitTop: () => exitedTop++,
            onEmptied: () => emptied++,
            itemBuilder: (context, cell) {
              first ??= cell.focusNode;
              return TvCatalogCompactCard(
                width: cell.width,
                artwork: const SizedBox(),
                title: ids[cell.index],
                meta: '',
                focusNode: cell.focusNode,
                onFocusChange: cell.onFocusChange,
                onSelect: () {},
              );
            },
          ),
        ),
      ),
    );

    await tester.pumpWidget(grid(const ['a']));
    first!.requestFocus();
    await tester.pumpAndSettle();
    await tester.pumpWidget(grid(const []));
    await tester.pumpAndSettle();

    expect(emptied, 1);
    expect(exitedTop, 0);
  });

  testWidgets('without fullBleed the route keeps the heading and the wrapped card', (tester) async {
    final h = await _harness();
    await h.pump(tester, canvas: _canvas);
    await h.open(tester, fullBleed: false);
    expect(find.byType(TvCatalogHeaderBar), findsOneWidget);
    expect(find.byType(TvCatalogCompactCard), findsNothing);
    expect(find.byType(TvCatalogCard), findsWidgets);
  });

  testWidgets('the second line follows the sort the page runs on', (tester) async {
    final added = DateTime.utc(2024, 3, 9, 12).millisecondsSinceEpoch ~/ 1000;
    final h = await FullBleedHarness.create([for (var i = 0; i < 12; i++) fakeMovie(i, year: 2011, addedAt: added)]);
    await UnifiedCatalogQueryStore.write(
      h.catalog.query.kind,
      UnifiedCatalogPreferences.defaults.copyWith(sort: UnifiedCatalogSort.recentlyAdded),
    );
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    expect(find.text('Mar 9, 2024'), findsWidgets);
    expect(find.text('2011'), findsNothing);
  });

  testWidgets('titles switched off keep the footer height', (tester) async {
    final h = await _harness();
    await SettingsService.instance.write(SettingsService.tvShowTitlesUnderPosters, false);
    await h.pump(tester, canvas: _canvas);
    await h.open(tester);
    expect(find.text('T000'), findsNothing);
    expect(h.posterRect(tester, 7).top - h.posterRect(tester, 1).top, closeTo(254.56 + 10, 1));
    expect(TvLayoutConstants.scaleForSize(_canvas), 0.85);
  });
}
