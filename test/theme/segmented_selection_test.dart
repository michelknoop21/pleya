import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';

/// The audio "Prioriteit" control was reported as unselectable. It wrote the
/// setting fine; it just never looked any different, because Material paints
/// the selected segment with secondaryContainer and this palette maps that onto
/// the very surface the row sits on. With showSelectedIcon off there was then
/// no cue left at all.
void main() {
  Future<void> pumpSegmented(WidgetTester tester, {required bool dark, required int selected}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: dark),
        home: Scaffold(
          body: Center(
            child: SegmentedButton<int>(
              segments: const [
                ButtonSegment(value: 0, label: Text('Gelijkmatig volume')),
                ButtonSegment(value: 1, label: Text('Originele Dolby Atmos')),
              ],
              selected: {selected},
              showSelectedIcon: false,
              onSelectionChanged: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The painted background of the segment carrying [label].
  Color? segmentBackground(WidgetTester tester, String label) {
    final material = tester.widget<Material>(
      find.ancestor(of: find.text(label), matching: find.byType(Material)).first,
    );
    return material.color;
  }

  for (final dark in [true, false]) {
    testWidgets('the selected segment is visibly different in ${dark ? 'dark' : 'light'} mode', (tester) async {
      await pumpSegmented(tester, dark: dark, selected: 0);

      final selectedFill = segmentBackground(tester, 'Gelijkmatig volume');
      final unselectedFill = segmentBackground(tester, 'Originele Dolby Atmos');

      expect(selectedFill, isNotNull);
      expect(selectedFill, isNot(unselectedFill), reason: 'selection has to be visible without a checkmark');
    });
  }

  testWidgets('moving the selection moves the fill with it', (tester) async {
    await pumpSegmented(tester, dark: true, selected: 0);
    final firstWhenSelected = segmentBackground(tester, 'Gelijkmatig volume');

    await pumpSegmented(tester, dark: true, selected: 1);
    final firstWhenNot = segmentBackground(tester, 'Gelijkmatig volume');
    final secondWhenSelected = segmentBackground(tester, 'Originele Dolby Atmos');

    expect(firstWhenSelected, isNot(firstWhenNot));
    expect(secondWhenSelected, firstWhenSelected);
  });

  testWidgets('the selected segment does not blend into the surface behind it', (tester) async {
    await pumpSegmented(tester, dark: true, selected: 0);

    final theme = monoTheme(dark: true);
    expect(segmentBackground(tester, 'Gelijkmatig volume'), isNot(theme.colorScheme.surface));
  });
}
