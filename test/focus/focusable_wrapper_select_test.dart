import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/focusable_wrapper.dart';

void main() {
  tearDown(SelectKeyUpSuppressor.clearSuppression);

  Future<(FocusNode, FocusNode)> pumpTwoWrappers(
    WidgetTester tester, {
    required VoidCallback onSelectA,
    required VoidCallback onSelectB,
  }) async {
    final nodeA = FocusNode(debugLabel: 'wrapperA');
    final nodeB = FocusNode(debugLabel: 'wrapperB');
    addTearDown(nodeA.dispose);
    addTearDown(nodeB.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              FocusableWrapper(
                focusNode: nodeA,
                onSelect: onSelectA,
                enableLongPress: true,
                child: const SizedBox(width: 100, height: 100),
              ),
              FocusableWrapper(
                focusNode: nodeB,
                onSelect: onSelectB,
                enableLongPress: true,
                child: const SizedBox(width: 100, height: 100),
              ),
            ],
          ),
        ),
      ),
    );
    return (nodeA, nodeB);
  }

  testWidgets('plain select press activates exactly once', (tester) async {
    var a = 0, b = 0;
    final (nodeA, _) = await pumpTwoWrappers(tester, onSelectA: () => a++, onSelectB: () => b++);

    nodeA.requestFocus();
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(a, 1);
    expect(b, 0);
  });

  testWidgets('key-up landing on a wrapper that never saw the key-down fires nothing', (tester) async {
    var a = 0, b = 0;
    final (nodeA, nodeB) = await pumpTwoWrappers(tester, onSelectA: () => a++, onSelectB: () => b++);

    nodeA.requestFocus();
    await tester.pump();

    // Press down on A, move focus to B mid-press (a rebuild/autoscroll in the
    // real app), then release: the orphaned key-up must not activate B, and A's
    // in-flight press was reset when it lost focus.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    nodeB.requestFocus();
    await tester.pump();
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(a, 0);
    expect(b, 0);

    // The next full press on B works normally — the orphan didn't poison it.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(b, 1);
  });
}
