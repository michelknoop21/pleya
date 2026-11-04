/// Roadmap A-06c, CAT-SCROLL429: a late source inserts earlier sorted titles.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_grid.dart';
import 'package:pleya/widgets/tv/tv_catalog_compact_card.dart';
import 'package:pleya/widgets/tv/tv_catalog_full_bleed_layout.dart';

void main() {
  testWidgets('late sorted source preserves focused title viewport anchor', (tester) async {
    tester.view.physicalSize = const Size(1038, 584);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final ids = ValueNotifier<List<String>>([for (var i = 0; i < 450; i++) 'm$i']);
    final controller = ScrollController();
    addTearDown(ids.dispose);
    addTearDown(controller.dispose);
    final nodes = <String, FocusNode>{};
    final outside = FocusNode();
    addTearDown(outside.dispose);
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: InputModeTracker(
          child: Material(
            child: Stack(
              children: [
                Focus(focusNode: outside, child: const SizedBox.shrink()),
                Positioned.fill(
                  child: ValueListenableBuilder<List<String>>(
                    valueListenable: ids,
                    builder: (context, items, _) => TvCatalogCardGrid(
                      controller: controller,
                      itemIds: items,
                      rowAligned: true,
                      gridResolver: (w, h) => TvCatalogFullBleedLayout.grid(width: w, height: h, scale: 0.85),
                      cardHeight: (w) => TvCatalogFullBleedLayout.cardHeight(w, 0.85),
                      hasMore: false,
                      isLoadingMore: false,
                      onLoadMore: () {},
                      itemBuilder: (context, cell) {
                        final id = items[cell.index];
                        nodes[id] = cell.focusNode;
                        return TvCatalogCompactCard(
                          key: ValueKey(id),
                          width: cell.width,
                          artwork: const SizedBox(),
                          title: id,
                          meta: '',
                          focusNode: cell.focusNode,
                          onSelect: () {},
                          onFocusChange: cell.onFocusChange,
                          onNavigateUp: cell.onNavigateUp,
                          onNavigateDown: cell.onNavigateDown,
                          onNavigateLeft: cell.onNavigateLeft,
                          onNavigateRight: cell.onNavigateRight,
                        );
                      },
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
    nodes['m60']!.requestFocus();
    await tester.pumpAndSettle();
    final before = tester.getTopLeft(find.byKey(const ValueKey('m60'))).dy;
    final offset = controller.offset;
    ids.value = [for (var i = 0; i < 12; i++) 'late$i', ...ids.value];
    await tester.pumpAndSettle();
    expect(nodes['m60']!.hasPrimaryFocus, isTrue);
    expect(
      tester
          .widget<AnimatedScale>(
            find.descendant(of: find.byKey(const ValueKey('m60')), matching: find.byType(AnimatedScale)),
          )
          .scale,
      TvCatalogFullBleedLayout.posterFocusScale,
      reason: 'a retained focused node also keeps its visible focus ring',
    );
    debugPrint(
      'anchor before=$before after=${tester.getTopLeft(find.byKey(const ValueKey('m60'))).dy} offsets=$offset -> ${controller.offset}',
    );
    expect(tester.getTopLeft(find.byKey(const ValueKey('m60'))).dy, closeTo(before, 0.01));
    // Appending pages must not move an existing viewport at all.
    final afterInsert = controller.offset;
    ids.value = [...ids.value, for (var i = 450; i < 462; i++) 'm$i'];
    await tester.pumpAndSettle();
    expect(controller.offset, afterInsert);
    expect(tester.getTopLeft(find.byKey(const ValueKey('m60'))).dy, closeTo(before, 0.01));
    // Deduplication/removal of earlier rows is the inverse operation.
    ids.value = ids.value.where((id) => !id.startsWith('late')).toList();
    await tester.pumpAndSettle();
    expect(controller.offset, closeTo(offset, 0.01));
    expect(tester.getTopLeft(find.byKey(const ValueKey('m60'))).dy, closeTo(before, 0.01));
    // A late page arriving while a directional row animation is in flight
    // must replace the obsolete row target and settle on the selected title.
    nodes['m90']!.requestFocus();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 30));
    expect(controller.position.isScrollingNotifier.value, isTrue);
    ids.value = [for (var i = 0; i < 18; i++) 'late$i', ...ids.value];
    await tester.pumpAndSettle();
    expect(nodes['m90']!.hasPrimaryFocus, isTrue);
    final selected = tester.getRect(find.byKey(const ValueKey('m90')));
    expect(selected.top, greaterThanOrEqualTo(0));
    expect(selected.bottom, lessThanOrEqualTo(584));
    // Remembered focus is not ownership: controls outside the grid keep both
    // their focus and the scroll position on further catalog updates.
    outside.requestFocus();
    await tester.pumpAndSettle();
    final beforeExternal = controller.offset;
    ids.value = [for (var i = 0; i < 12; i++) 'other$i', ...ids.value];
    await tester.pumpAndSettle();
    expect(outside.hasPrimaryFocus, isTrue);
    expect(controller.offset, beforeExternal);
  });
}
