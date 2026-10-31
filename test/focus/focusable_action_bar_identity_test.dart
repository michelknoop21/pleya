import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_action_bar.dart';
import 'package:pleya/focus/input_mode_tracker.dart';

String? get _focus => FocusManager.instance.primaryFocus?.debugLabel;

/// A row whose buttons come and go, the way a detail page's actions do when a
/// press changes what the title offers.
class _Row extends StatefulWidget {
  const _Row({super.key});

  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  var labels = ['play', 'restart', 'rate', 'watched', 'more'];

  void show(List<String> next) => setState(() => labels = next);

  @override
  Widget build(BuildContext context) => FocusableActionBar(
    actions: [
      for (final label in labels)
        FocusableAction(
          debugLabel: label,
          onPressed: () {},
          builder: (context, state) => SizedBox.square(dimension: 20),
        ),
    ],
  );
}

void main() {
  final row = GlobalKey<_RowState>();

  Future<void> pump(WidgetTester tester) async {
    await tester.pumpWidget(
      MaterialApp(
        home: InputModeTracker(
          child: Scaffold(body: _Row(key: row)),
        ),
      ),
    );
    await tester.pump();
  }

  Future<void> focus(WidgetTester tester, String label) async {
    final index = row.currentState!.labels.indexOf(label);
    tester.state<FocusableActionBarState>(find.byType(FocusableActionBar)).getFocusNode(index)!.requestFocus();
    await tester.pump();
  }

  testWidgets('a button that goes elsewhere in the row keeps the focus on the one in use', (tester) async {
    await pump(tester);
    await focus(tester, 'watched');

    row.currentState!.show(['play', 'rate', 'watched', 'more']);
    await tester.pump();
    await tester.pump();

    expect(_focus, 'watched');
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowLeft);
    await tester.pump();
    expect(_focus, 'rate');
  });

  testWidgets('a button that comes in front keeps the focus where it is too', (tester) async {
    await pump(tester);
    row.currentState!.show(['play', 'rate', 'watched', 'more']);
    await tester.pump();
    await focus(tester, 'watched');

    row.currentState!.show(['play', 'restart', 'rate', 'watched', 'more']);
    await tester.pump();
    await tester.pump();

    expect(_focus, 'watched');
  });

  testWidgets('the button in use going away hands the focus to the one in its place', (tester) async {
    await pump(tester);
    await focus(tester, 'restart');

    row.currentState!.show(['play', 'rate', 'watched', 'more']);
    await tester.pump();
    await tester.pump();

    expect(_focus, 'rate');
  });

  testWidgets('the last button going away hands the focus to the one before it', (tester) async {
    await pump(tester);
    await focus(tester, 'more');

    row.currentState!.show(['play', 'restart', 'rate', 'watched']);
    await tester.pump();
    await tester.pump();

    expect(_focus, 'watched');
  });

  testWidgets('nothing moves a focus the row does not have', (tester) async {
    await pump(tester);
    final outside = FocusNode(debugLabel: 'outside');
    addTearDown(outside.dispose);
    await tester.pumpWidget(
      MaterialApp(
        home: InputModeTracker(
          child: Scaffold(
            body: Column(
              children: [
                Focus(focusNode: outside, child: const SizedBox.square(dimension: 10)),
                _Row(key: row),
              ],
            ),
          ),
        ),
      ),
    );
    outside.requestFocus();
    await tester.pump();

    row.currentState!.show(['play', 'more']);
    await tester.pump();
    await tester.pump();

    expect(_focus, 'outside');
  });
}
