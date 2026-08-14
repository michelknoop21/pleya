import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/utils/key_event_simulator.dart';
import 'package:pleya/utils/native_input_session.dart';

/// A focus node that records every key event walked into it.
class _RecordingFocusNode extends FocusNode {
  final events = <KeyEvent>[];

  _RecordingFocusNode() {
    onKeyEvent = (node, event) {
      events.add(event);
      return KeyEventResult.handled;
    };
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  tearDown(NativeInputSession.debugReset);

  Future<_RecordingFocusNode> pumpFocusedNode(WidgetTester tester) async {
    final node = _RecordingFocusNode();
    addTearDown(node.dispose);
    await tester.pumpWidget(Focus(key: ValueKey(node), focusNode: node, child: const SizedBox()));
    node.requestFocus();
    await tester.pump();
    expect(node.hasPrimaryFocus, isTrue);
    return node;
  }

  testWidgets('synthetic keys reach the focus tree when no native surface is up', (tester) async {
    final node = await pumpFocusedNode(tester);

    simulateKeyPress(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(node.events, hasLength(2));
    expect(node.events.first, isA<KeyDownEvent>());
    expect(node.events.last, isA<KeyUpEvent>());
  });

  testWidgets('synthetic keys are dropped while the tvOS keyboard owns the remote', (tester) async {
    final node = await pumpFocusedNode(tester);

    NativeInputSession.begin();
    simulateKeyPress(LogicalKeyboardKey.arrowDown);
    simulateKeyDown(LogicalKeyboardKey.enter);
    simulateKeyUp(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(node.events, isEmpty);
  });

  testWidgets('a release arriving mid-session is dropped and its hold forgotten', (tester) async {
    final first = await pumpFocusedNode(tester);

    simulateKeyDown(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(first.events, hasLength(1));

    // The keyboard takes over while the key is still down.
    NativeInputSession.begin();
    simulateKeyUp(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(first.events.whereType<KeyUpEvent>(), isEmpty);
    NativeInputSession.end();

    // Focus has moved on since. The dropped hold must not drag a later release
    // back to the node that was focused when the key went down.
    final second = await pumpFocusedNode(tester);
    simulateKeyUp(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(first.events.whereType<KeyUpEvent>(), isEmpty);
    expect(second.events.whereType<KeyUpEvent>(), hasLength(1));
  });
}
