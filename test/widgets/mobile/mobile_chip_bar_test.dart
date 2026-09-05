import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_chip_bar.dart';

void main() {
  Future<void> pump(WidgetTester tester, MobileHomeChip selected, ValueChanged<MobileHomeChip> onSelected) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobileChipBar(selected: selected, onSelected: onSelected),
        ),
      ),
    );
  }

  testWidgets('renders exactly Series and Films — no Nieuw or Genres', (tester) async {
    await pump(tester, MobileHomeChip.home, (_) {});
    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(find.text('New'), findsNothing);
    expect(find.text('Genres'), findsNothing);
  });

  testWidgets('tapping a chip reports it once', (tester) async {
    MobileHomeChip? picked;
    await pump(tester, MobileHomeChip.home, (chip) => picked = chip);

    await tester.tap(find.text('Series'));
    expect(picked, MobileHomeChip.series);
  });

  testWidgets('tapping the already-selected chip toggles back to Home', (tester) async {
    MobileHomeChip? picked;
    await pump(tester, MobileHomeChip.movies, (chip) => picked = chip);

    await tester.tap(find.text('Movies'));
    expect(picked, MobileHomeChip.home);
  });

  testWidgets('there is no chip for Home, so a fresh Home state has nothing selected to toggle off', (tester) async {
    // Both chips render as their unselected variant when Home is active —
    // this only guards against a future Home chip reintroducing the toggle
    // guard incorrectly.
    var callCount = 0;
    await pump(tester, MobileHomeChip.home, (_) => callCount++);

    expect(find.text('Series'), findsOneWidget);
    expect(find.text('Movies'), findsOneWidget);
    expect(callCount, 0);
  });
}
