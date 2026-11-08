import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/main/scroll_tab_to_top.dart';
import 'package:pleya/screens/main_screen.dart';

Widget _tab() => ListView(
  children: [
    SizedBox(
      height: 120,
      child: ListView(scrollDirection: Axis.horizontal, children: const [SizedBox(width: 3000)]),
    ),
    const SizedBox(height: 5000),
  ],
);

List<ScrollableState> _vertical() => find
    .byType(Scrollable, skipOffstage: false)
    .evaluate()
    .map((e) => (e as StatefulElement).state as ScrollableState)
    .where((s) => s.position.axis == Axis.vertical)
    .toList();

void main() {
  Future<void> pump(WidgetTester t, GlobalKey key, ValueNotifier<int> index) async {
    await t.pumpWidget(
      MaterialApp(
        home: ValueListenableBuilder<int>(
          valueListenable: index,
          builder: (_, i, _) => mainScreenDestinationStack(screens: [_tab(), _tab()], currentIndex: i, stackKey: key),
        ),
      ),
    );
    for (final s in _vertical()) {
      s.position.jumpTo(800);
    }
  }

  testWidgets('re-tap scrolls the active tab to offset 0 and leaves the other tab alone', (t) async {
    final key = GlobalKey();
    await pump(t, key, ValueNotifier(0));
    scrollTabToTop(key, 0);
    await t.pumpAndSettle();
    expect(_vertical().map((s) => s.position.pixels), [0, 800]);
  });

  testWidgets('switching to another tab scrolls nothing', (t) async {
    final index = ValueNotifier(0);
    await pump(t, GlobalKey(), index);
    index.value = 1;
    await t.pumpAndSettle();
    expect(_vertical().map((s) => s.position.pixels), [800, 800]);
  });
}
