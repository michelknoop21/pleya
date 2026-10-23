/// Paging look-ahead of the TV catalog grid: the next page is requested four
/// rows before the end, and again after a finished load when the focus still
/// sits inside that window (fast scrolling must not stall on every page).
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const Size _canvas = Size(1038, 584);

void main() {
  testWidgets('load more fires inside the four-row window and chains after a finished load', (tester) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ids = [for (var i = 0; i < 90; i++) 'm$i'];
    final nodes = <String, FocusNode>{};
    final loading = ValueNotifier<bool>(false);
    var loadMoreCalls = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Material(
            child: ValueListenableBuilder<bool>(
              valueListenable: loading,
              builder: (context, isLoading, _) => SizedBox(
                width: _canvas.width,
                height: _canvas.height,
                child: TvCatalogCardGrid(
                  itemIds: ids,
                  cardHeight: (width) => TvCatalogLayout.cardHeight(width, 0.85),
                  hasMore: true,
                  isLoadingMore: isLoading,
                  onLoadMore: () => loadMoreCalls++,
                  itemBuilder: (context, cell) {
                    nodes[ids[cell.index]] = cell.focusNode;
                    return TvCatalogCard(
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
          ),
        ),
      ),
    );

    final first = tester.getTopLeft(find.text('m0'));
    final columns = ids
        .takeWhile((id) => nodes.containsKey(id) && tester.getTopLeft(find.text(id)).dy == first.dy)
        .length;
    expect(columns, greaterThan(1));
    final rows = (ids.length / columns).ceil();

    // Five rows from the end: outside the window, no request.
    final far = ids[(rows - 6) * columns];
    nodes[far]!.requestFocus();
    await tester.pump();
    expect(loadMoreCalls, 0);

    // Three rows from the end: inside the four-row window.
    final near = ids[(rows - 4) * columns];
    nodes[near]!.requestFocus();
    await tester.pump();
    expect(loadMoreCalls, 1);

    // A load starts and finishes with the focus still inside the window: the
    // grid asks again without any focus movement.
    loading.value = true;
    await tester.pump();
    loading.value = false;
    await tester.pump();
    await tester.pump();
    expect(loadMoreCalls, 2);
  });
}
