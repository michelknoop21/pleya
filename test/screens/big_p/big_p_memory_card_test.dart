/// BP-08a on iPhone and iPad: the memory card in Big P's balloon under the
/// answer (43 K, 43 H), without the question field while it waits, and the
/// link under an answer that stored something.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_input_bar.dart';
import 'package:pleya/screens/big_p/big_p_mobile_conversation.dart';
import 'package:pleya/screens/big_p/big_p_mobile_followups.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_memory_card.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv/assistant/tv_assistant_test_support.dart';
import 'big_p_mobile_fixtures.dart';

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;
  late final card = t.assistant.memory.card;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    c = FakeAssistantController();
    session = BigPMobileSession(c);
    addTearDown(() {
      session.dispose();
      c.dispose();
    });
  });

  Future<void> pumpHost(WidgetTester tester, {Size size = const Size(375, 667), double textScale = 1}) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final dispatcher = tester.platformDispatcher..localeTestValue = const Locale('nl', 'NL');
    addTearDown(dispatcher.clearLocaleTestValue);
    session.summon();
    await tester.pumpWidget(
      TranslationProvider(
        child: ChangeNotifierProvider<BigPMobileSession>.value(
          value: session,
          child: MaterialApp(
            theme: monoTheme(dark: true),
            home: Builder(
              builder: (context) => MediaQuery(
                data: MediaQuery.of(
                  context,
                ).copyWith(disableAnimations: true, textScaler: TextScaler.linear(textScale)),
                child: const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  for (final (name, size) in const [
    ('iPhone SE', Size(375, 667)),
    ('iPhone', Size(402, 874)),
    ('iPad', Size(1180, 820)),
  ]) {
    testWidgets('$name: the card under the answer, no question field and no follow-ups while it waits', (tester) async {
      answerMemoryCard(c, rememberProposal());
      await pumpHost(tester, size: size);

      expect(find.byType(BigPMemoryCard), findsOneWidget);
      expect(find.text(card.rememberTitle), findsOneWidget);
      expect(find.text('Houdt niet van horror'), findsOneWidget);
      expect(find.text(t.assistant.memory.categories.dislike), findsOneWidget);
      // Under the answer, not in its place (43 K).
      final answer = find.textContaining('Drie spannende titels zonder horror');
      expect(answer, findsOneWidget);
      expect(tester.getTopLeft(answer).dy, lessThan(tester.getTopLeft(find.byType(BigPMemoryCard)).dy));
      expect(find.byType(BigPInputBar), findsNothing);
      expect(BigPMobileFollowUps.questions(c), isEmpty);
      expect(bigPMood(c), BigPMood.attentive);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('both buttons are 44 pt targets on one row, the safe one on the right and white', (tester) async {
    answerMemoryCard(c, rememberProposal());
    await pumpHost(tester);

    final accept = find.widgetWithText(BigPButton, card.remember);
    final decline = find.widgetWithText(BigPButton, card.notRemember);
    expect(tester.getSize(accept).height, greaterThanOrEqualTo(44));
    expect(tester.getSize(decline).height, greaterThanOrEqualTo(44));
    expect(tester.getCenter(accept).dy, tester.getCenter(decline).dy);
    expect(tester.getCenter(accept).dx, lessThan(tester.getCenter(decline).dx));
    expect(tester.widget<BigPButton>(decline).primary, isTrue);
    expect(tester.widget<BigPButton>(accept).primary, isFalse);
  });

  testWidgets('"Niet onthouden" answers no, "Onthouden" answers yes, and the card goes', (tester) async {
    final proposal = rememberProposal();
    answerMemoryCard(c, proposal);
    await pumpHost(tester);
    await tester.tap(find.text(card.notRemember));
    await settle(tester);

    expect(c.memoryAnswers, [(proposal, false)]);
    expect(find.byType(BigPMemoryCard), findsNothing);
    expect(find.byType(BigPInputBar), findsOneWidget);

    final again = rememberProposal();
    c
      ..memoryProposal = again
      ..emit();
    await settle(tester);
    await tester.tap(find.text(card.remember));
    await settle(tester);
    expect(c.memoryAnswers.last, (again, true));
  });

  testWidgets('replacing shows what disappears and what is new (43 H)', (tester) async {
    answerMemoryCard(c, replaceProposal());
    await pumpHost(tester, size: const Size(402, 874));

    expect(find.text(card.replaceTitle), findsOneWidget);
    final old = find.text('Kijkt op vrijdagavond met het gezin');
    final fresh = find.text('Kijkt op zaterdagavond met het gezin');
    expect(tester.getTopLeft(find.text(card.disappears)).dy, lessThan(tester.getTopLeft(old).dy));
    expect(tester.getTopLeft(old).dy, lessThan(tester.getTopLeft(find.text(card.fresh)).dy));
    expect(tester.getTopLeft(find.text(card.fresh)).dy, lessThan(tester.getTopLeft(fresh).dy));
    expect(find.text(card.replace), findsOneWidget);
    expect(tester.widget<BigPButton>(find.widgetWithText(BigPButton, card.notReplace)).primary, isTrue);
  });

  testWidgets('forgetting shows the fact that disappears', (tester) async {
    answerMemoryCard(c, forgetProposal());
    await pumpHost(tester, size: const Size(402, 874));

    expect(find.text(card.forgetTitle), findsOneWidget);
    expect(find.text(card.disappears), findsOneWidget);
    expect(find.text('Houdt niet van horror'), findsOneWidget);
    expect(find.text(card.forget), findsOneWidget);
    expect(find.text(card.notForget), findsOneWidget);
  });

  testWidgets('a sentence of 200 characters at a large text size keeps both buttons in the balloon', (tester) async {
    answerMemoryCard(
      c,
      AssistantMemoryProposal(
        kind: AssistantMemoryProposalKind.replace,
        memory: rememberProposal().memory,
        value: 'Kijkt op zaterdagavond met het hele gezin ${'en de buren ' * 13}'.trim(),
        category: MemoryCategory.household,
        target: memoryFact(
          'Kijkt op vrijdagavond met het hele gezin ${'en de buren ' * 13}'.trim(),
          MemoryCategory.household,
        ),
      ),
    );
    await pumpHost(tester, textScale: 1.6);

    expect(tester.takeException(), isNull);
    final screen = tester.getRect(find.byType(BigPMobileHost));
    for (final label in [card.replace, card.notReplace]) {
      final button = tester.getRect(find.widgetWithText(BigPButton, label));
      expect(screen.contains(button.topLeft) && screen.contains(button.bottomRight), isTrue, reason: label);
    }
  });

  testWidgets('negative control: without a proposal there is no card and the field is back', (tester) async {
    answerMemoryCard(c, rememberProposal());
    c.memoryProposal = null;
    await pumpHost(tester);
    expect(find.byType(BigPMemoryCard), findsNothing);
    expect(find.byType(BigPInputBar), findsOneWidget);
  });

  group('"Bekijk geheugen" (43 K)', () {
    Future<void> pumpConversation(WidgetTester tester, {VoidCallback? onOpenMemory}) => tester.pumpWidget(
      TranslationProvider(
        child: MaterialApp(
          theme: monoTheme(dark: true),
          home: Scaffold(
            body: BigPMobileConversation(
              controller: c,
              name: 'Michel',
              onExample: (_) {},
              onSetup: () {},
              onOpenTitle: (_) {},
              onOpenMemory: onOpenMemory,
            ),
          ),
        ),
      ),
    );

    testWidgets('shows under an answer that stored something and opens the memory', (tester) async {
      var opened = 0;
      answerMemoryStored(c);
      await pumpConversation(tester, onOpenMemory: () => opened++);

      expect(find.text('Onthouden: Kijkt op vrijdagavond met het gezin.'), findsOneWidget);
      final link = find.byType(BigPMemoryLink);
      expect(link, findsOneWidget);
      expect(tester.getSize(link).height, greaterThanOrEqualTo(44));
      await tester.tap(find.text(t.assistant.memory.view));
      expect(opened, 1);
    });

    testWidgets('is absent when nothing was stored, and while no destination is wired', (tester) async {
      answerMemoryStored(c);
      c.memoryStored = false;
      await pumpConversation(tester, onOpenMemory: () {});
      expect(find.byType(BigPMemoryLink), findsNothing);

      c.memoryStored = true;
      await pumpConversation(tester);
      expect(find.byType(BigPMemoryLink), findsNothing);
    });

    testWidgets('the host wires no destination yet: the answer shows without the link', (tester) async {
      answerMemoryStored(c);
      await pumpHost(tester);
      expect(find.textContaining('Onthouden: Kijkt op vrijdagavond met het gezin.'), findsOneWidget);
      expect(find.byType(BigPMemoryLink), findsNothing);
    });
  });
}
