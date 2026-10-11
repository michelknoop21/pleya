/// BP-08a on TV: the memory card stands in the balloon under Big P's answer
/// with the focus on the safe button, is walked with the D-pad, and Menu
/// closes it as a no.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_answer.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_memory_card.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';

import '../../big_p/big_p_mobile_fixtures.dart';
import 'tv_assistant_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_memory_entry');
  late FakeAssistantController c;
  late final card = t.assistant.memory.card;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    NativeInputSession.debugReset();
    c.dispose();
  });

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  /// The surface, then the answer with a memory card under it.
  Future<void> raise(WidgetTester tester, [AssistantMemoryProposal? proposal]) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantScreen(
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
      ),
    );
    answerMemoryCard(c, proposal ?? rememberProposal());
    c.emit();
    await settle(tester);
  }

  testWidgets('opens on the safe button, Big P attentive, under the answer and not over it', (tester) async {
    await raise(tester);
    expect(find.byType(BigPMemoryCard), findsOneWidget);
    expect(find.text(card.rememberTitle), findsOneWidget);
    expect(find.text('Houdt niet van horror'), findsOneWidget);
    expect(focusedLabel(), 'assistant.memory.decline');
    expect(tester.widget<BigPAvatar>(find.byType(BigPAvatar)).mood, BigPMood.attentive);

    // The answer is on screen, readable, and the card starts below its last line.
    final screen = Offset.zero & tester.view.physicalSize;
    final answer = tester.getRect(find.byType(BigPAnswer));
    final cardRect = tester.getRect(find.byType(BigPMemoryCard));
    expect(screen.contains(answer.topLeft) && screen.contains(answer.bottomRight), isTrue);
    expect(screen.contains(cardRect.topLeft) && screen.contains(cardRect.bottomRight), isTrue);
    expect(cardRect.top, greaterThanOrEqualTo(answer.bottom));
    expect(answer.height, greaterThan(40));
    // Nothing else to land on while the card waits.
    expect(find.text(t.assistant.idle.ask), findsNothing);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a fact of 200 characters keeps the answer and both buttons on screen', (tester) async {
    final long = AssistantMemoryProposal(
      kind: AssistantMemoryProposalKind.remember,
      memory: rememberProposal().memory,
      value: List.filled(10, 'Kijkt het liefst lange films').join(' ').substring(0, 200),
      category: MemoryCategory.habit,
    );
    await raise(tester, long);

    final screen = Offset.zero & tester.view.physicalSize;
    for (final label in [card.remember, card.notRemember]) {
      final rect = tester.getRect(find.text(label));
      expect(screen.contains(rect.topLeft) && screen.contains(rect.bottomRight), isTrue, reason: label);
    }
    expect(
      tester.getRect(find.byType(BigPMemoryCard)).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(BigPAnswer)).bottom),
    );
    expect(tester.takeException(), isNull);
  });

  testWidgets('Up reads the answer; Down comes back on the safe button, also from the yes side', (tester) async {
    await raise(tester);
    await press(tester, LogicalKeyboardKey.arrowRight);
    expect(focusedLabel(), 'assistant.memory.decline');
    await press(tester, LogicalKeyboardKey.arrowDown);
    expect(focusedLabel(), 'assistant.memory.decline');

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), isNot('assistant.memory.decline'));
    await press(tester, LogicalKeyboardKey.arrowUp);
    expect(focusedLabel(), 'assistant.answer');
    // Select on the answer answers nothing.
    await press(tester, LogicalKeyboardKey.select);
    expect(c.memoryAnswers, isEmpty);
    // Down first reads on to the last line, then leaves the answer.
    for (var i = 0; i < 6 && focusedLabel() == 'assistant.answer'; i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    expect(focusedLabel(), 'assistant.memory.decline');
  });

  testWidgets('Select on the opening focus answers no', (tester) async {
    final proposal = rememberProposal();
    await raise(tester, proposal);
    await press(tester, LogicalKeyboardKey.select);

    expect(c.memoryAnswers, [(proposal, false)]);
    expect(find.byType(BigPMemoryCard), findsNothing);
    // The remote is back on the answer's own button, and the Select that
    // answered the card (down and up) pressed nothing there.
    expect(focusedLabel(), 'assistant.ask');
    expect(c.listenContexts, isEmpty);
    expect(c.submitted, isEmpty);
  });

  testWidgets('D-pad left to the other button and Select answers yes', (tester) async {
    final proposal = replaceProposal();
    await raise(tester, proposal);
    expect(find.text(card.replaceTitle), findsOneWidget);
    expect(find.text('Kijkt op vrijdagavond met het gezin'), findsOneWidget);
    expect(find.text('Kijkt op zaterdagavond met het gezin'), findsOneWidget);

    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), isNot('assistant.memory.decline'));
    await press(tester, LogicalKeyboardKey.select);

    expect(c.memoryAnswers, [(proposal, true)]);
    expect(find.byType(BigPMemoryCard), findsNothing);
  });

  testWidgets('Menu closes the card as a no; the answer stays and the card does not come back', (tester) async {
    final proposal = forgetProposal();
    await raise(tester, proposal);
    expect(find.text(card.forgetTitle), findsOneWidget);
    await press(tester, LogicalKeyboardKey.escape);

    expect(c.memoryAnswers, [(proposal, false)]);
    expect(find.byType(BigPMemoryCard), findsNothing);
    expect(find.textContaining('Drie spannende titels zonder horror'), findsOneWidget);
    expect(find.text(t.assistant.idle.ask), findsOneWidget, reason: 'Big P stays, with the answer and its buttons');
    expect(focusedLabel(), 'assistant.ask');
    c.emit();
    await settle(tester);
    expect(find.byType(BigPMemoryCard), findsNothing);
  });

  testWidgets('a second proposal opens on the safe button too, after a yes on the first', (tester) async {
    final first = rememberProposal();
    final second = forgetProposal();
    await raise(tester, first);
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(focusedLabel(), isNot('assistant.memory.decline'));
    await press(tester, LogicalKeyboardKey.select);
    expect(c.memoryAnswers, [(first, true)]);
    c
      ..memoryProposal = second
      ..emit();
    await settle(tester);

    expect(find.text(card.forgetTitle), findsOneWidget);
    expect(focusedLabel(), 'assistant.memory.decline');
  });

  testWidgets('a card the controller dropped goes without an answer', (tester) async {
    await raise(tester);
    c
      ..memoryProposal = null
      ..emit();
    await settle(tester);
    expect(find.byType(BigPMemoryCard), findsNothing);
    expect(c.memoryAnswers, isEmpty);
  });

  testWidgets('the summoned Big P raises the same card', (tester) async {
    final presses = StreamController<void>.broadcast();
    addTearDown(presses.close);
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
    answerMemoryCard(c, rememberProposal());
    c.emit();
    await settle(tester);
    expect(find.byType(BigPMemoryCard), findsOneWidget);
    expect(focusedLabel(), 'assistant.memory.decline');
    expect(
      tester.getRect(find.byType(BigPMemoryCard)).top,
      greaterThanOrEqualTo(tester.getRect(find.byType(BigPAnswer)).bottom),
    );

    // Menu answers the card with no and leaves Big P where he is.
    final proposal = c.memoryProposal!;
    await press(tester, LogicalKeyboardKey.escape);
    expect(c.memoryAnswers, [(proposal, false)]);
    expect(find.byType(BigPMemoryCard), findsNothing);
    expect(find.textContaining('Drie spannende titels zonder horror'), findsOneWidget);
    expect(focusedLabel(), 'assistant.ask');
  });
}
