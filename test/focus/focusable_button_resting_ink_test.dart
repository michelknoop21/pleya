/// What a dimmed, unfocused [FocusableButton] gives the Material button inside
/// it to paint its label with. Without this the label is the brand red at 60%.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_button.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';

void main() {
  final theme = monoTheme(dark: true, oled: true);

  Color? ink(WidgetTester tester, String label) => DefaultTextStyle.of(tester.element(find.text(label))).style.color;

  testWidgets('a resting text or outlined button is labelled in the text colour, the focused one keeps the accent', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: theme,
        home: InputModeTracker(
          child: Scaffold(
            body: Row(
              children: [
                FocusableButton(
                  autofocus: true,
                  onPressed: () {},
                  child: OutlinedButton(onPressed: () {}, child: const Text('outlined')),
                ),
                FocusableButton(
                  onPressed: () {},
                  child: TextButton(onPressed: () {}, child: const Text('text')),
                ),
                FocusableButton(
                  onPressed: () {},
                  child: OutlinedButton(
                    onPressed: () {},
                    style: OutlinedButton.styleFrom(foregroundColor: theme.colorScheme.error),
                    child: const Text('own colour'),
                  ),
                ),
                FocusableButton(child: const OutlinedButton(onPressed: null, child: Text('disabled'))),
              ],
            ),
          ),
        ),
      ),
    );
    // The first real key puts the app in D-pad mode, which is where the dim applies.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();

    expect(ink(tester, 'outlined'), kAccent, reason: 'in the ring');
    expect(ink(tester, 'text'), theme.colorScheme.onSurface);
    expect(ink(tester, 'own colour'), theme.colorScheme.error);
    expect(ink(tester, 'disabled')!.a, closeTo(0.38, 0.01), reason: 'disabled stays the faded Material default');

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();

    expect(ink(tester, 'outlined'), theme.colorScheme.onSurface);
    expect(ink(tester, 'text'), kAccent, reason: 'in the ring');
  });
}
