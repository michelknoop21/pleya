/// T8 on iPhone and iPad: the ages card in Big P's balloon, without the
/// question field while it waits (39 G), and the age notice under the
/// answer.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/big_p/big_p_input_bar.dart';
import 'package:pleya/screens/big_p/big_p_mobile_followups.dart';
import 'package:pleya/screens/big_p/big_p_mobile_host.dart';
import 'package:pleya/screens/big_p/big_p_mobile_session.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_kids_ages_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_title_facts.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../tv/assistant/tv_assistant_test_support.dart';
import 'big_p_mobile_fixtures.dart';

void main() {
  late FakeAssistantController c;
  late BigPMobileSession session;

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

  Future<void> pumpHost(WidgetTester tester, {Size size = const Size(375, 667)}) async {
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
                data: MediaQuery.of(context).copyWith(disableAnimations: true),
                child: const Stack(fit: StackFit.expand, children: [Scaffold(), BigPMobileHost()]),
              ),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
  }

  Future<void> tapText(WidgetTester tester, String text) async {
    await tester.ensureVisible(find.text(text));
    await tester.pump();
    await tester.tap(find.text(text));
    await settle(tester);
  }

  for (final (name, size) in const [('iPhone SE', Size(375, 667)), ('iPad', Size(1180, 820))]) {
    testWidgets('$name: the card, no question field and no follow-ups while it waits', (tester) async {
      answerKidsAges(c);
      await pumpHost(tester, size: size);
      expect(find.byType(BigPKidsAgesCard), findsOneWidget);
      expect(find.text(t.assistant.kids.title), findsOneWidget);
      expect(find.byType(BigPInputBar), findsNothing);
      expect(BigPMobileFollowUps.questions(c), isEmpty);
      expect(tester.takeException(), isNull);
    });
  }

  testWidgets('Bewaar stays off until an age is chosen, then saves the chosen ages', (tester) async {
    answerKidsAges(c);
    await pumpHost(tester);

    await tapText(tester, t.assistant.kids.save);
    expect(c.savedAges, isEmpty, reason: 'nothing chosen yet');

    await tapText(tester, '9');
    await tapText(tester, '4');
    await tapText(tester, '12');
    await tapText(tester, '12'); // chosen and unchosen again
    await tapText(tester, t.assistant.kids.save);

    expect(c.savedAges, [
      [4, 9],
    ]);
    expect(c.unfilteredRetries, 0);
  });

  testWidgets('Zonder filter asks again without saving', (tester) async {
    answerKidsAges(c);
    await pumpHost(tester);
    await tapText(tester, t.assistant.kids.skip);
    expect(c.unfilteredRetries, 1);
    expect(c.savedAges, isEmpty);
  });

  testWidgets('negative control: without the card the question field is back', (tester) async {
    answerFactsTitles(c);
    await pumpHost(tester);
    expect(find.byType(BigPKidsAgesCard), findsNothing);
    expect(find.byType(BigPInputBar), findsOneWidget);
  });

  testWidgets('the age notice shows under the answer, above the title cards', (tester) async {
    answerFactsTitles(c);
    c.answer = '${c.answer}\n\n${t.assistant.kids.filterNotice}';
    await pumpHost(tester);
    expect(find.textContaining(t.assistant.kids.filterNotice), findsOneWidget);
    expect(find.byType(BigPTitleFacts), findsWidgets);
    expect(tester.takeException(), isNull);
  });
}
