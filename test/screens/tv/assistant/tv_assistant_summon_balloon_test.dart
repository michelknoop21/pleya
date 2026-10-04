// Mockup 39 J: summoned Big P speaks from a balloon whose tail points at
// him; the focus contracts stay those of tv_assistant_summon_test.dart.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/big_p_balloon.dart';

import 'tv_assistant_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_balloon_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeAssistantController c;
  late StreamController<void> presses;

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
    presses = StreamController<void>.broadcast();
    messenger.setMockMethodCallHandler(channel, (_) async => <String, dynamic>{'text': 'Vraag', 'submitted': true});
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
    unawaited(presses.close());
    c.dispose();
  });

  Future<void> summoned(WidgetTester tester) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantSummonHost(
        longPresses: presses.stream,
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
        screenContext: () => null,
        child: const SizedBox.expand(),
      ),
    );
    presses.add(null);
    await settle(tester);
  }

  Future<void> answer(WidgetTester tester, String text, [List<AssistantDisplay> displays = const []]) async {
    c
      ..state = AssistantSurfaceState.result
      ..answer = text
      ..displays = displays
      ..emit();
    await settle(tester);
  }

  /// Where the tail's tip is on screen, as a fraction down Big P's height.
  double tailOnBigP(WidgetTester tester) {
    final balloon = tester.widget<BigPBalloon>(find.byType(BigPBalloon));
    expect(balloon.tail, AxisDirection.right);
    final box = tester.getRect(find.byType(BigPBalloon));
    final him = tester.getRect(find.byType(BigPAvatar));
    expect(box.right, lessThanOrEqualTo(him.left), reason: 'Big P stands clear of the balloon');
    return (box.top + box.height * balloon.tailAt - him.top) / him.height;
  }

  testWidgets('the conversation is a balloon whose tail points at his face, short or long', (tester) async {
    await summoned(tester);
    await answer(tester, 'De scan van Films loopt.');
    final short = tester.getRect(find.byType(BigPBalloon));
    final atShort = tailOnBigP(tester);
    expect(atShort, inInclusiveRange(0.2, 0.45), reason: 'head, not his feet');

    await answer(tester, List.filled(40, 'Ik heb veel films met Tom Cruise gevonden.').join(' '));
    final long = tester.getRect(find.byType(BigPBalloon));
    expect(long.height, greaterThan(short.height));
    expect(long.top, greaterThanOrEqualTo(60 - 0.5), reason: 'the balloon tops out at 60 pt (pt = 1 at 1080p)');
    expect(tailOnBigP(tester), closeTo(atShort, 0.01), reason: 'the tail stays on him as the balloon grows');
  });

  testWidgets('a result with choices puts the focus on the first option', (tester) async {
    await summoned(tester);
    await answer(tester, 'Ik vond twee titels. Welke bedoel je?', [
      AssistantRequestOptions(AssistantToolContext(servers: MultiServerManager()), const [
        AssistantRequestOption(
          seerrId: 'movie:1',
          title: 'The Martian',
          year: 2015,
          kind: 'movie',
          posterUrl: '',
          overview: '',
          status: 'not_requested',
        ),
        AssistantRequestOption(
          seerrId: 'tv:1',
          title: 'The Expanse',
          year: 2015,
          kind: 'series',
          posterUrl: '',
          overview: '',
          status: 'not_requested',
        ),
      ]),
    ]);
    expect(focusedLabel(), 'assistant.option');
    final option = FocusManager.instance.primaryFocus!.rect;
    final balloon = tester.getRect(find.byType(BigPBalloon));
    expect(balloon.contains(option.center), isTrue, reason: 'the focused card is inside the balloon');
  });
}
