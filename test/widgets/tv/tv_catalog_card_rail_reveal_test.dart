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
              // and a key without a callback falls through, as
              // `FocusableWrapper` lets it.
              onKeyEvent: (_, event) {
                if (event is KeyUpEvent) return KeyEventResult.ignored;
                final callback = switch (event.logicalKey) {
                  LogicalKeyboardKey.arrowRight => cell.onNavigateRight,
                  LogicalKeyboardKey.arrowLeft => cell.onNavigateLeft,
                  _ => null,
                };
                if (callback == null) return KeyEventResult.ignored;
                callback();
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

    // To the end of the row, and one more: the last card keeps the key,
    // so it cannot fall through to a card in another row.
    for (var i = 21; i <= 29; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
      expectFocusedInView(i);
    }
    expect(controller.position.pixels, controller.position.maxScrollExtent);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expectFocusedInView(29);

    for (var i = 28; i >= 0; i--) {
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

  testWidgets('RIGHT on the last card of a row stays there, it does not drop into the next row', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    Widget rail(String name) => TvCatalogCardRail(
      nodeDebugLabel: name,
      itemIds: [for (var i = 0; i < 12; i++) 'item$i'],
      cardHeight: (width) => 200,
      hasMore: false,
      isLoadingMore: false,
      onLoadMore: () {},
      itemBuilder: (context, cell) => Focus(
        focusNode: cell.focusNode,
        onFocusChange: cell.onFocusChange,
        onKeyEvent: (_, event) {
          if (event is KeyUpEvent) return KeyEventResult.ignored;
          final callback = event.logicalKey == LogicalKeyboardKey.arrowRight ? cell.onNavigateRight : null;
          if (callback == null) return KeyEventResult.ignored;
          callback();
          return KeyEventResult.handled;
        },
        child: SizedBox(key: ValueKey('$name${cell.index}'), width: cell.width, child: Text('$name ${cell.index}')),
      ),
    );
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: Column(children: [rail('first'), rail('second')])),
      ),
    );
    await tester.pumpAndSettle();
    Focus.of(tester.element(find.byKey(const ValueKey('first0')))).requestFocus();
    await tester.pumpAndSettle();

    for (var i = 0; i < 14; i++) {
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
      await tester.pumpAndSettle();
    }

    expect(FocusManager.instance.primaryFocus?.debugLabel, 'first(item11)');
  });
}
