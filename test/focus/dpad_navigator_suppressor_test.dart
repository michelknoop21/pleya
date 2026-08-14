import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/dpad_navigator.dart';
import 'package:pleya/focus/focusable_wrapper.dart';

KeyDownEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
  physicalKey: PhysicalKeyboardKey.select,
  logicalKey: key,
  timeStamp: Duration.zero,
  deviceType: ui.KeyEventDeviceType.directionalPad,
);

KeyUpEvent _up(LogicalKeyboardKey key) => KeyUpEvent(
  physicalKey: PhysicalKeyboardKey.select,
  logicalKey: key,
  timeStamp: Duration.zero,
  deviceType: ui.KeyEventDeviceType.directionalPad,
);

void main() {
  tearDown(SelectKeyUpSuppressor.clearSuppression);

  test('armed suppressor eats the in-flight select key-up and clears', () {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();

    expect(SelectKeyUpSuppressor.consumeIfSuppressed(_up(LogicalKeyboardKey.select)), isTrue);
    // Cleared: the next release passes through untouched.
    expect(SelectKeyUpSuppressor.consumeIfSuppressed(_up(LogicalKeyboardKey.select)), isFalse);
  });

  test('a fresh select key-down is never consumed and clears suppression', () {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();

    // A new press can't be the in-flight release the suppressor was armed for.
    expect(SelectKeyUpSuppressor.consumeIfSuppressed(_down(LogicalKeyboardKey.select)), isFalse);
    // And its own key-up must fire normally afterwards.
    expect(SelectKeyUpSuppressor.consumeIfSuppressed(_up(LogicalKeyboardKey.select)), isFalse);
  });

  test('non-select keys pass through while armed', () {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();

    expect(SelectKeyUpSuppressor.consumeIfSuppressed(_down(LogicalKeyboardKey.arrowDown)), isFalse);
    // Still armed for the actual select release.
    expect(SelectKeyUpSuppressor.consumeIfSuppressed(_up(LogicalKeyboardKey.select)), isTrue);
  });

  testWidgets('context-menu press without onLongPress leaves the next select press working', (tester) async {
    var selects = 0;
    final focusNode = FocusNode(debugLabel: 'wrapper');
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FocusableWrapper(
            focusNode: focusNode,
            onSelect: () => selects++,
            enableLongPress: true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    focusNode.requestFocus();
    await tester.pump();

    // Context-menu key on a wrapper with no onLongPress: nothing opens, and it
    // must not arm the global suppressor.
    await tester.sendKeyDownEvent(LogicalKeyboardKey.contextMenu);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.contextMenu);
    await tester.pump();

    await tester.sendKeyDownEvent(LogicalKeyboardKey.select);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.select);
    await tester.pump();

    expect(selects, 1);
  });
}
