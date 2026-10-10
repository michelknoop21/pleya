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

  /// Puts the app in D-pad mode with the focus back where it started.
  Future<void> dpad(WidgetTester tester) async {
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pumpAndSettle();
  }

  Widget app(ThemeData theme, Widget body) => MaterialApp(
    theme: theme,
    home: InputModeTracker(child: Scaffold(body: body)),
  );

  for (final mode in ['pointer', 'D-pad']) {
    testWidgets('an inherited IconTheme reaches the child of a FocusableButton in $mode mode', (tester) async {
      const inherited = IconThemeData(color: Color(0xFF00FF00), size: 31);
      await tester.pumpWidget(
        app(
          theme,
          IconTheme(
            data: inherited,
            child: Row(
              children: [
                FocusableButton(autofocus: true, onPressed: () {}, child: const Icon(Icons.star)),
                FocusableButton(onPressed: () {}, child: const Icon(Icons.add)),
              ],
            ),
          ),
        ),
      );
      if (mode == 'D-pad') await dpad(tester);

      IconThemeData at(IconData icon) => IconTheme.of(tester.element(find.byIcon(icon)));
      expect(at(Icons.star).color, inherited.color, reason: 'focused in D-pad mode, plain in pointer mode');
      expect(at(Icons.star).size, inherited.size);
      expect(at(Icons.add).color, inherited.color, reason: 'dimmed in D-pad mode, plain in pointer mode');
      expect(at(Icons.add).size, inherited.size);
    });
  }

  testWidgets('in pointer mode an outlined and a text button paint exactly as they do without a FocusableButton', (
    tester,
  ) async {
    Widget outlined(String label, IconData icon) =>
        OutlinedButton.icon(onPressed: () {}, icon: Icon(icon), label: Text(label));
    Widget text(String label, IconData icon) => TextButton.icon(onPressed: () {}, icon: Icon(icon), label: Text(label));

    await tester.pumpWidget(
      app(
        theme,
        // What an ancestor sets and a button does not override must arrive too.
        IconTheme.merge(
          data: const IconThemeData(opacity: 0.5),
          child: Wrap(
            children: [
              outlined('bare outlined', Icons.star),
              FocusableButton(onPressed: () {}, child: outlined('wrapped outlined', Icons.add)),
              text('bare text', Icons.remove),
              FocusableButton(onPressed: () {}, child: text('wrapped text', Icons.check)),
            ],
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(InputModeTracker.isKeyboardMode(tester.element(find.text('bare text'))), isFalse);

    IconThemeData iconAt(IconData icon) => IconTheme.of(tester.element(find.byIcon(icon)));
    for (final (bare, wrapped, bareIcon, wrappedIcon) in [
      ('bare outlined', 'wrapped outlined', Icons.star, Icons.add),
      ('bare text', 'wrapped text', Icons.remove, Icons.check),
    ]) {
      expect(ink(tester, wrapped), kAccent);
      expect(ink(tester, wrapped), ink(tester, bare));
      expect(iconAt(wrappedIcon).color, kAccent);
      expect(iconAt(wrappedIcon), iconAt(bareIcon), reason: '$wrapped: the icon theme of the bare button');
      expect(tester.widget<FadeTransition>(_dim(wrapped)).opacity.value, 1.0, reason: 'no dim without a remote');
    }
  });

  testWidgets('on the light theme a resting label is the text colour in D-pad mode, the focused one the accent', (
    tester,
  ) async {
    final light = monoTheme(dark: false);
    expect(light.colorScheme.onSurface, isNot(theme.colorScheme.onSurface), reason: 'a different ink than dark');
    await tester.pumpWidget(
      app(
        light,
        Row(
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
          ],
        ),
      ),
    );
    await dpad(tester);

    expect(ink(tester, 'outlined'), kAccent, reason: 'in the ring');
    expect(ink(tester, 'text'), light.colorScheme.onSurface);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowRight);
    await tester.pumpAndSettle();
    expect(ink(tester, 'outlined'), light.colorScheme.onSurface);
    expect(ink(tester, 'text'), kAccent, reason: 'in the ring');
  });

  testWidgets('a disabled text button keeps the faded Material default at rest', (tester) async {
    await tester.pumpWidget(
      app(
        theme,
        Row(
          children: [
            FocusableButton(
              autofocus: true,
              onPressed: () {},
              child: TextButton(onPressed: () {}, child: const Text('enabled')),
            ),
            const TextButton(onPressed: null, child: Text('bare disabled')),
            FocusableButton(child: const TextButton(onPressed: null, child: Text('disabled'))),
          ],
        ),
      ),
    );
    await dpad(tester);

    expect(ink(tester, 'disabled'), ink(tester, 'bare disabled'));
    expect(ink(tester, 'disabled')!.a, closeTo(0.38, 0.01));
    expect(ink(tester, 'disabled')!.withValues(alpha: 1), theme.colorScheme.onSurface);
  });

  testWidgets('a rebuild of a resting FocusableButton does not rebuild what reads the button themes', (tester) async {
    var builds = 0;
    final child = Builder(
      builder: (context) {
        builds++;
        OutlinedButtonTheme.of(context);
        TextButtonTheme.of(context);
        return const SizedBox(width: 10, height: 10);
      },
    );
    late StateSetter rebuild;
    await tester.pumpWidget(
      app(
        theme,
        Row(
          children: [
            FocusableButton(autofocus: true, onPressed: () {}, child: const Text('focused')),
            StatefulBuilder(
              builder: (context, setState) {
                rebuild = setState;
                return FocusableButton(onPressed: () {}, child: child);
              },
            ),
          ],
        ),
      ),
    );
    await dpad(tester);
    final before = builds;

    rebuild(() {});
    await tester.pump();
    expect(builds, before);
  });
}

/// The dim a [FocusableButton] puts around the button labelled [label].
Finder _dim(String label) => find.ancestor(of: find.text(label), matching: find.byType(FadeTransition)).first;
