import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/utils/native_input_session.dart';

/// The leak this covers is specifically the *real* event path: the tvOS engine
/// hands Siri Remote presses to Dart as key events, so they arrive through
/// [FocusManager], not through the synthetic dispatch that
/// `native_input_session_test.dart` gates. A handler answering "handled" further
/// up does not stop the focus-tree walk; only an early key handler does.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('test_native_entry_key_gate');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  tearDown(() {
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
  });

  late FocusNode first;
  late FocusNode second;
  late List<KeyEvent> seen;

  Future<void> pumpTwoFocusables(WidgetTester tester) async {
    seen = <KeyEvent>[];
    first = FocusNode(debugLabel: 'first');
    second = FocusNode(debugLabel: 'second');
    addTearDown(first.dispose);
    addTearDown(second.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Column(
          children: [
            Focus(
              focusNode: first,
              onKeyEvent: (_, event) {
                seen.add(event);
                return KeyEventResult.ignored;
              },
              child: const SizedBox(width: 100, height: 100),
            ),
            Focus(focusNode: second, child: const SizedBox(width: 100, height: 100)),
          ],
        ),
      ),
    );
    first.requestFocus();
    await tester.pump();
    expect(first.hasPrimaryFocus, isTrue);
  }

  /// Opens a real session over [channel] and hands back the completer that ends
  /// it, so the keyboard stays "up" for the duration of a test.
  Future<(Future<AppleTvTextEntryResult>, Completer<Map<String, dynamic>>, List<String>)> openSession() async {
    final calls = <String>[];
    final opened = Completer<void>();
    final release = Completer<Map<String, dynamic>>();
    messenger.setMockMethodCallHandler(channel, (call) {
      calls.add(call.method);
      if (call.method == 'edit') {
        opened.complete();
        return release.future;
      }
      return Future<dynamic>.value();
    });

    final session = AppleTvNativeTextEntry(channel: channel).edit(text: '');
    await opened.future;
    expect(NativeInputSession.isActive, isTrue);
    return (session, release, calls);
  }

  testWidgets('real key events drive the focus tree when no native surface is up', (tester) async {
    await pumpTwoFocusables(tester);

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(seen, isNotEmpty);
    expect(second.hasPrimaryFocus, isTrue);
  });

  testWidgets('real key events are blocked while the native keyboard owns the remote', (tester) async {
    await pumpTwoFocusables(tester);
    final (session, release, _) = await openSession();

    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();

    expect(seen, isEmpty, reason: 'the widget behind the keyboard must not see the press');
    expect(first.hasPrimaryFocus, isTrue, reason: 'focus must not move underneath the keyboard');

    release.complete(<String, dynamic>{'text': '', 'submitted': false});
    await session;
    expect(NativeInputSession.isActive, isFalse);

    // The gate stays registered for the app's lifetime, so it has to be inert
    // the moment the session ends.
    await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
    await tester.pump();

    expect(seen, isNotEmpty);
    expect(second.hasPrimaryFocus, isTrue);
  });

  testWidgets('a back key that reaches Dart closes the surface instead of vanishing', (tester) async {
    await pumpTwoFocusables(tester);
    final (session, release, calls) = await openSession();

    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await tester.pump();
    // The close request is fire-and-forget over the channel.
    await tester.idle();

    expect(calls, contains('cancel'));
    expect(seen, isEmpty);
    expect(first.hasPrimaryFocus, isTrue);

    release.complete(<String, dynamic>{'text': '', 'submitted': false});
    await session;
  });
}
