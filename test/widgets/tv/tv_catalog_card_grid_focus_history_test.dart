/// Row-aligned TV grid: UP and DOWN move the focus themselves, LEFT and RIGHT go
/// through Flutter's directional traversal. That traversal keeps a history and
/// answers the opposite direction by popping it, so a history from another row
/// must not survive a row move: the ring would jump back to a card rows away.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const Size _canvas = Size(1038, 584);

void main() {
  testWidgets('LEFT after RIGHT and a row move stays in the new row', (tester) async {
    tester.view.physicalSize = _canvas;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);

    final ids = [for (var i = 0; i < 90; i++) 'm$i'];
    final nodes = <String, FocusNode>{};
    final gridKey = GlobalKey<TvCatalogCardGridState>();

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Material(
            child: SizedBox(
              width: _canvas.width,
              height: _canvas.height,
              child: TvCatalogCardGrid(
                key: gridKey,
                rowAligned: true,
                itemIds: ids,
                cardHeight: (width) => TvCatalogLayout.cardHeight(width, 0.85),
                hasMore: false,
                isLoadingMore: false,
                onLoadMore: () {},
                itemBuilder: (context, cell) {
                  nodes[ids[cell.index]] = cell.focusNode;
                  return TvCatalogCard(
                    width: cell.width,
                    artwork: const SizedBox(),
                    title: ids[cell.index],
                    meta: '',
                    focusNode: cell.focusNode,
                    onFocusChange: cell.onFocusChange,
                    onNavigateUp: cell.onNavigateUp,
                    onNavigateDown: cell.onNavigateDown,
                    onNavigateLeft: cell.onNavigateLeft,
                    onNavigateRight: cell.onNavigateRight,
                    onSelect: () {},
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    final top = tester.getTopLeft(find.text('m0')).dy;
    final columns = ids.takeWhile((id) => tester.getTopLeft(find.text(id)).dy == top).length;
    expect(columns, greaterThan(3));

    Future<void> press(LogicalKeyboardKey key) async {
      await tester.sendKeyEvent(key);
      await tester.pumpAndSettle();
    }

    String focused() => nodes.entries.firstWhere((e) => e.value.hasPrimaryFocus).key;

    nodes['m${3 * columns}']!.requestFocus();
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'm${3 * columns + 2}');

    for (var i = 0; i < 3; i++) {
      await press(LogicalKeyboardKey.arrowUp);
    }
    expect(focused(), 'm2');

    await press(LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'm1');

    // Coming back from outside the grid, as the filter rail and a detail route do.
    await press(LogicalKeyboardKey.arrowRight);
    await press(LogicalKeyboardKey.arrowRight);
    expect(focused(), 'm3');
    expect(gridKey.currentState!.focusItem('m${2 * columns + 1}'), isTrue);
    await tester.pumpAndSettle();
    await press(LogicalKeyboardKey.arrowLeft);
    expect(focused(), 'm${2 * columns}');
  });
}
