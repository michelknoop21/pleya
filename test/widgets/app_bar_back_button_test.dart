import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/app_bar_back_button.dart';

/// The drawn disc of [BackButtonStyle.circular] is a fixed 40pt circle. It used
/// to be a `Container(margin: all(8), width: 40, height: 40)`, which the
/// incoming constraints could shrink: in the 44pt mobile detail app bar the
/// painted box measured 40x28 and `BoxShape.circle` drew a 28pt circle. The
/// geometry must not depend on how much room the parent happens to offer.
void main() {
  Future<void> pumpBackButton(WidgetTester tester, {required Widget parent}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: parent),
      ),
    );
    await tester.pumpAndSettle();
  }

  /// The box that actually paints the circle.
  Size discSize(WidgetTester tester) {
    final finder = find.descendant(
      of: find.byType(AppBarBackButton),
      matching: find.byWidgetPredicate((w) {
        final decoration = w is DecoratedBox ? w.decoration : null;
        return decoration is BoxDecoration && decoration.shape == BoxShape.circle;
      }),
    );
    expect(finder, findsOneWidget);
    return tester.getSize(finder);
  }

  testWidgets('circular draws a 40x40 disc with room to spare', (tester) async {
    await pumpBackButton(
      tester,
      parent: Align(
        alignment: Alignment.topLeft,
        child: AppBarBackButton(style: BackButtonStyle.circular, onPressed: () {}),
      ),
    );

    expect(discSize(tester), const Size(40, 40));
  });

  testWidgets('circular still draws a 40x40 disc inside a 44pt app bar', (tester) async {
    await pumpBackButton(
      tester,
      parent: SizedBox(
        height: 44,
        child: Row(
          children: [
            AppBarBackButton(style: BackButtonStyle.circular, onPressed: () {}),
            const Expanded(child: Text('Dune: Part Two')),
          ],
        ),
      ),
    );

    // Before the fix this was 40x28: a circle deformed by its parent's height.
    expect(discSize(tester), const Size(40, 40));
  });

  testWidgets('the disc is square at every bar height, never derived from it', (tester) async {
    for (final barHeight in [36.0, 44.0, 56.0, 72.0]) {
      await pumpBackButton(
        tester,
        parent: SizedBox(
          height: barHeight,
          child: Row(
            children: [AppBarBackButton(style: BackButtonStyle.circular, onPressed: () {})],
          ),
        ),
      );

      expect(discSize(tester), const Size(40, 40), reason: 'bar height $barHeight must not resize the disc');
    }
  });

  testWidgets('tapping still pops through the supplied callback', (tester) async {
    var taps = 0;
    await pumpBackButton(
      tester,
      parent: Align(
        alignment: Alignment.topLeft,
        child: AppBarBackButton(style: BackButtonStyle.circular, onPressed: () => taps++),
      ),
    );

    await tester.tap(find.byType(AppBarBackButton));
    expect(taps, 1);
  });
}
