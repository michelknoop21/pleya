/// BP-08a on TV: the memory card rises over Big P's answer with the focus on
/// the safe button, is walked with the D-pad, and Menu closes it as a no.
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

  testWidgets('opens on the safe button, Big P attentive, the answer still there', (tester) async {
    await raise(tester);
    expect(find.byType(BigPMemoryCard), findsOneWidget);
    expect(find.text(card.rememberTitle), findsOneWidget);
    expect(find.text('Houdt niet van horror'), findsOneWidget);
    expect(focusedLabel(), 'assistant.memory.decline');
    expect(tester.widget<BigPAvatar>(find.byType(BigPAvatar)).mood, BigPMood.attentive);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Select on the opening focus answers no', (tester) async {
    final proposal = rememberProposal();
    await raise(tester, proposal);
    await press(tester, LogicalKeyboardKey.select);

    expect(c.memoryAnswers, [(proposal, false)]);
    expect(find.byType(BigPMemoryCard), findsNothing);
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
    c.emit();
    await settle(tester);
    expect(find.byType(BigPMemoryCard), findsNothing);
  });

  testWidgets('a second proposal rises after the first is answered', (tester) async {
    final first = rememberProposal();
    final second = forgetProposal();
    await raise(tester, first);
    await press(tester, LogicalKeyboardKey.select);
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
  });
}
