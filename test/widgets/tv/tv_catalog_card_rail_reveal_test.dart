/// SEARCH4: on a real Apple TV, RIGHT past the last visible poster of a
/// Zoeken row put the focus ring on a card outside the screen. The row did
/// not scroll, and every further press did nothing.
///
/// [TvCatalogCardRail] moved the focus with a bare `requestFocus()`.
/// `FocusableWrapper` consumes the arrow key, so Flutter's own traversal and
/// its `ensureVisible` never run, and the wrapper's scroll-into-view only
/// looks for a vertical scrollable. Nothing revealed the card on the
/// horizontal axis.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_catalog_card_rail.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('RIGHT and LEFT keep the focused card inside the row, scrolling it as needed', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final itemIds = [for (var i = 0; i < 30; i++) 'item$i'];
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: TvCatalogCardRail(
            itemIds: itemIds,
            cardHeight: (width) => 200,
            hasMore: false,
            isLoadingMore: false,
            onLoadMore: () {},
            // As a catalog card does: the key is consumed and handed to the
            // rail, so default traversal never sees it.
            itemBuilder: (context, cell) => Focus(
              focusNode: cell.focusNode,
              onFocusChange: cell.onFocusChange,
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) cell.onNavigateRight?.call();
                if (event.logicalKey == LogicalKeyboardKey.arrowLeft) cell.onNavigateLeft?.call();
                return KeyEventResult.handled;
              },
              child: SizedBox(key: ValueKey('card${cell.index}'), width: cell.width, child: Text('item${cell.index}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    final controller = tester.widget<ListView>(find.byType(ListView)).controller!;
    String? focused() => FocusManager.instance.primaryFocus?.debugLabel;
    void expectFocusedInView(int index) {
      expect(focused(), contains('(item$index)'));
      final rect = tester.getRect(find.byKey(ValueKey('card$index')));
      expect(rect.left, greaterThanOrEqualTo(0), reason: 'card $index starts left of the screen');
      expect(rect.right, lessThanOrEqualTo(1920), reason: 'card $index ends right of the screen');
    }

    Focus.of(tester.element(find.byKey(const ValueKey('card0')))).requestFocus();
    await tester.pumpAndSettle();

    for (var i = 1; i <= 20; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expectFocusedInView(i);
    }
    expect(controller.position.pixels, greaterThan(0));

    for (var i = 19; i >= 0; i--) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
      await tester.pumpAndSettle();
      expectFocusedInView(i);
    }
    expect(controller.position.pixels, 0);
  });

  testWidgets('a held RIGHT is not dropped while the next card is still to be built', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final itemIds = [for (var i = 0; i < 30; i++) 'item$i'];
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: TvCatalogCardRail(
            itemIds: itemIds,
            cardHeight: (width) => 200,
            hasMore: false,
            isLoadingMore: false,
            onLoadMore: () {},
            itemBuilder: (context, cell) => Focus(
              focusNode: cell.focusNode,
              onFocusChange: cell.onFocusChange,
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                if (event.logicalKey == LogicalKeyboardKey.arrowRight) cell.onNavigateRight?.call();
                return KeyEventResult.handled;
              },
              child: SizedBox(key: ValueKey('card${cell.index}'), width: cell.width, child: Text('item${cell.index}')),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.byKey(const ValueKey('card0')))).requestFocus();
    await tester.pumpAndSettle();

    // One frame per press, as a held key repeats: the scroll never settles.
    for (var i = 0; i < 15; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pump(const Duration(milliseconds: 16));
    }
    await tester.pumpAndSettle();

    expect(FocusManager.instance.primaryFocus?.debugLabel, contains('(item15)'));
    final rect = tester.getRect(find.byKey(const ValueKey('card15')));
    expect(rect.left, greaterThanOrEqualTo(0));
    expect(rect.right, lessThanOrEqualTo(1920));
  });
}
