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

  group('as a release build runs it: a FocusNode keeps no label', () {
    setUp(() => FocusableActionBar.debugOmitNodeLabels = true);
    tearDown(() => FocusableActionBar.debugOmitNodeLabels = false);

    FocusNode? node(WidgetTester tester, int index) =>
        tester.state<FocusableActionBarState>(find.byType(FocusableActionBar)).getFocusNode(index);

    testWidgets('a button going away in front keeps the focus on the one in use', (tester) async {
      await pump(tester);
      await focus(tester, 'watched');
      final used = FocusManager.instance.primaryFocus;

      row.currentState!.show(['play', 'rate', 'watched', 'more']);
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(used));
      expect(node(tester, 2), same(used));
    });

    testWidgets('a button coming in front keeps it too', (tester) async {
      await pump(tester);
      row.currentState!.show(['play', 'rate', 'watched', 'more']);
      await tester.pump();
      await focus(tester, 'watched');
      final used = FocusManager.instance.primaryFocus;

      row.currentState!.show(['play', 'restart', 'rate', 'watched', 'more']);
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(used));
      expect(node(tester, 3), same(used));
    });
  });

  group('a row without labels', () {
    testWidgets('a stateful button stays what it was when the row grows or shrinks', (tester) async {
      _Probe.inits = 0;
      late StateSetter set;
      FocusableAction probe() => FocusableAction(onPressed: () {}, child: const _Probe());
      var actions = [probe(), probe()];
      await tester.pumpWidget(
        MaterialApp(
          home: InputModeTracker(
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setter) {
                  set = setter;
                  return FocusableActionBar(actions: actions);
                },
              ),
            ),
          ),
        ),
      );
      expect(_Probe.inits, 2);

      set(() => actions = [probe(), probe(), probe()]);
      await tester.pump();
      expect(_Probe.inits, 3);

      set(() => actions = [probe()]);
      await tester.pump();
      expect(_Probe.inits, 3);
    });

    testWidgets('its focus stays in its place', (tester) async {
      late StateSetter set;
      FocusableAction plain() =>
          FocusableAction(onPressed: () {}, builder: (context, state) => const SizedBox.square(dimension: 20));
      var actions = [plain(), plain(), plain()];
      await tester.pumpWidget(
        MaterialApp(
          home: InputModeTracker(
            child: Scaffold(
              body: StatefulBuilder(
                builder: (context, setter) {
                  set = setter;
                  return FocusableActionBar(actions: actions);
                },
              ),
            ),
          ),
        ),
      );
      final bar = tester.state<FocusableActionBarState>(find.byType(FocusableActionBar));
      final used = bar.getFocusNode(1)!..requestFocus();
      await tester.pump();

      set(() => actions = [plain(), plain(), plain(), plain()]);
      await tester.pump();
      await tester.pump();

      expect(FocusManager.instance.primaryFocus, same(used));
    });
  });

  testWidgets('two buttons with one label both stand, whatever the row does', (tester) async {
    await pump(tester);
    row.currentState!.show(['x', 'x', 'y']);
    await tester.pump();
    row.currentState!.show(['x', 'x', 'x', 'y']);
    await tester.pump();
    row.currentState!.show(['y', 'x']);
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.byType(SizedBox), findsWidgets);
  });

  testWidgets('a row that empties under the focus and comes back throws nothing', (tester) async {
    await pump(tester);
    await focus(tester, 'more');
    row.currentState!.show(const []);
    await tester.pump();
    await tester.pump();
    row.currentState!.show(['more']);
    await tester.pump();
    await tester.pump();

    expect(tester.takeException(), isNull);
  });
}

/// Counts how often a button is built from nothing.
class _Probe extends StatefulWidget {
  const _Probe();

  static var inits = 0;

  @override
  State<_Probe> createState() => _ProbeState();
}

class _ProbeState extends State<_Probe> {
  @override
  void initState() {
    super.initState();
    _Probe.inits++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox.square(dimension: 20);
}
