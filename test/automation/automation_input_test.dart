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

  test('blocked while a native input session owns the remote', () {
    NativeInputSession.begin();
    expect(dispatchAutomationKey('select'), AutomationInputResult.blockedByNativeSession);
    expect(dispatchAutomationPointerTap(Offset.zero), AutomationInputResult.blockedByNativeSession);
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
    final result = dispatchAutomationPointerTap(center);
    await tester.pump();

    expect(result, AutomationInputResult.dispatched);
    expect(pressed, isTrue);
  });
}
