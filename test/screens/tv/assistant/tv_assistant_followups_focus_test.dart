/// F9 of the Big P density audit: the follow-ups under a TV answer wrap into
/// two rows; the remote has to reach every one of them, Up and Down.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';

import 'tv_assistant_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_followups_entry');
  late FakeAssistantController c;

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    c.dispose();
  });

  /// The instance of the follow-up chip the remote is on, if it is on one.
  String? focusedFollowUp() {
    final chip = FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BigPChip>();
    return chip?.automationId == AutomationIds.assistantFollowUp ? chip?.automationInstance : null;
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  testWidgets('the remote reaches all three follow-ups, up from the field and down again', (tester) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantScreen(
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
      ),
    );
    c
      ..prompt = 'Hoeveel films staan er?'
      ..answer = 'Op Zolder staan 1.284 films.'
      ..state = AssistantSurfaceState.result
      ..emit();
    await settle(tester);
    expect(
      find.byWidgetPredicate((w) => w is BigPChip && w.automationId == AutomationIds.assistantFollowUp),
      findsNWidgets(3),
    );
    expect(focusedLabel(), 'assistant.ask');

    final up = <String?>[];
    for (var i = 0; i < 3; i++) {
      await press(tester, LogicalKeyboardKey.arrowUp);
      up.add(focusedFollowUp());
    }
    // The stacked column is walked bottom to top: 2, 1, 0.
    expect(up, ['2', '1', '0']);

    final down = <String?>[];
    for (var i = 0; i < 2; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
      down.add(focusedFollowUp());
    }
    expect(down, ['1', '2']);
  });
}
