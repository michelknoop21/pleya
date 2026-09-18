import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_input.dart';
import 'package:pleya/utils/native_input_session.dart';

void main() {
  tearDown(() => NativeInputSession.end());

  testWidgets('select dispatches through the real focus tree and activates a button', (tester) async {
    var pressed = false;
    final focusNode = FocusNode();
    addTearDown(focusNode.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Focus(
          focusNode: focusNode,
          autofocus: true,
          onKeyEvent: (node, event) {
            if (event is! KeyDownEvent) return KeyEventResult.ignored;
            if (event.logicalKey == LogicalKeyboardKey.select) {
              pressed = true;
              return KeyEventResult.handled;
            }
            return KeyEventResult.ignored;
          },
          child: const SizedBox(width: 10, height: 10),
        ),
      ),
    );
    await tester.pump();

    final result = dispatchAutomationKey('select');
    await tester.pump();

    expect(result, AutomationInputResult.dispatched);
    expect(pressed, isTrue);
  });

  test('an unrecognized key name is rejected without touching the focus tree', () {
    expect(dispatchAutomationKey('doubleclick'), AutomationInputResult.unknownKey);
  });

  test('blocked while a native input session owns the remote', () async {
    NativeInputSession.begin();
    expect(dispatchAutomationKey('select'), AutomationInputResult.blockedByNativeSession);
    expect(await dispatchAutomationPointerTap(Offset.zero), AutomationInputResult.blockedByNativeSession);
  });

  testWidgets('a pointer tap goes through the real hit-test pipeline and activates a button', (tester) async {
    var pressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: SizedBox(
            width: 100,
            height: 50,
            child: ElevatedButton(onPressed: () => pressed = true, child: const Text('go')),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(ElevatedButton));
    final result = await dispatchAutomationPointerTap(center);
    await tester.pump();

    expect(result, AutomationInputResult.dispatched);
    expect(pressed, isTrue);
  });

  testWidgets('a held pointer down triggers a real onLongPress recognizer, not a synthetic callback', (tester) async {
    var longPressed = false;

    await tester.pumpWidget(
      MaterialApp(
        home: Center(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onLongPress: () => longPressed = true,
            child: const SizedBox(width: 100, height: 100),
          ),
        ),
      ),
    );

    final center = tester.getCenter(find.byType(GestureDetector));
    final hold = kLongPressTimeout + const Duration(milliseconds: 50);
    final future = dispatchAutomationPointerTap(center, hold: hold);
    await tester.pump(hold); // fake-clock advance resolves both the internal delay and the recognizer's own timer
    await future;

    expect(longPressed, isTrue, reason: 'held between down and up for at least kLongPressTimeout');
  });

  testWidgets('text inserts into the focused field through its own controller', (tester) async {
    final controller = TextEditingController();
    addTearDown(controller.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller, autofocus: true)),
      ),
    );
    await tester.pump();

    final result = dispatchAutomationText('batman');
    await tester.pump();

    expect(result, AutomationInputResult.dispatched);
    expect(controller.text, 'batman');
    expect(controller.selection, const TextSelection.collapsed(offset: 6));
  });

  testWidgets('text inserts at the current selection rather than replacing the whole field', (tester) async {
    final controller = TextEditingController(text: 'bat');
    addTearDown(controller.dispose);
    controller.selection = const TextSelection.collapsed(offset: 3);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: TextField(controller: controller, autofocus: true)),
      ),
    );
    await tester.pump();

    dispatchAutomationText('man');
    await tester.pump();

    expect(controller.text, 'batman');
  });

  test('rejected when no text field is focused', () {
    expect(dispatchAutomationText('batman'), AutomationInputResult.noEditableTarget);
  });

  test('blocked while a native input session owns the remote', () {
    NativeInputSession.begin();
    expect(dispatchAutomationText('batman'), AutomationInputResult.blockedByNativeSession);
  });
}
