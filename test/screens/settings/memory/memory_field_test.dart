// Instellingen > Big P > Geheugen on a phone: the field "Vraag of werk bij"
// with its card (43 H), the follow-ups, and the profile the screen is of.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_memory_card.dart';

import 'memory_finders.dart';
import 'memory_screen_support.dart';

/// Read per use: the locale is set inside each test.
TranslationsAssistantMemoryScreenEn get s => t.assistant.memory.screen;

void main() {
  late MemoryScreenHarness h;

  Future<void> open(WidgetTester tester, {bool seed = true, List<Object>? overview, Size size = phoneSize}) async {
    await tester.runAsync(useDutch);
    if (seed) await tester.runAsync(h.seed);
    h.overviewModel = ScriptedModel(overview ?? [say(mockupOverviewReply())]);
    await pumpMemoryApp(tester, AssistantMemoryScreen(model: h.model), size: size);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.dispose);
  }

  Finder input() =>
      find.descendant(of: memoryId(AutomationIds.settingsMemoryInput), matching: find.byType(EditableText));

  Future<void> type(WidgetTester tester, String text) async {
    await tester.enterText(input(), text);
    await tester.pump();
    await tester.tap(memoryAction('send'));
    await settle(tester, 10);
  }

  setUp(() => h = MemoryScreenHarness());

  group('vraag of werk bij (43 H)', () {
    testWidgets('a typed "onthoud dat" stores at once, and the overview is written again', (tester) async {
      await open(tester, overview: [say(mockupOverviewReply()), say(mockupOverviewReply())]);
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {'value': 'Kijkt graag thrillers', 'category': 'preference'}),
        say('Genoteerd.'),
      ]);
      await type(tester, 'Onthoud dat ik graag thrillers kijk');

      expect(h.host.asked, [(text: 'Onthoud dat ik graag thrillers kijk', typed: true)]);
      expect(await tester.runAsync(h.values), contains('Ik graag thrillers kijk'));
      expect(find.byType(BigPMemoryCard), findsNothing);
      expect(find.textContaining('Ik graag thrillers kijk'), findsOneWidget);
      // The screen stayed open: one more call, for the changed facts.
      expect(h.overviewModel.calls, 2);
      expect(h.model.view, MemoryScreenView.overview);
      await close(tester);
    });

    testWidgets('a sentence that contradicts a memory gets the card above the field, safe button white', (
      tester,
    ) async {
      await open(tester, overview: [say(mockupOverviewReply()), say(mockupOverviewReply())]);
      final friday = (await tester.runAsync(h.service.list))!.firstWhere((f) => f.value.contains('vrijdagavond'));
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {
          'value': 'Kijkt op zaterdagavond met het gezin',
          'category': 'household',
          'replaces': friday.ref,
        }),
        say('Dat pas ik aan als je het goed vindt.'),
      ]);
      await type(tester, 'We kijken tegenwoordig op zaterdag met het gezin');

      final card = find.byType(BigPMemoryCard);
      expect(card, findsOneWidget);
      expect(find.text(t.assistant.memory.card.replaceTitle), findsOneWidget);
      expect(find.text('Kijkt op vrijdagavond met het gezin'), findsOneWidget);
      expect(find.text('Kijkt op zaterdagavond met het gezin'), findsOneWidget);
      expect(find.text(s.status.waiting), findsOneWidget);
      // Above the field, and nothing changed yet.
      expect(tester.getBottomLeft(card).dy, lessThanOrEqualTo(tester.getTopLeft(input()).dy));
      expect(await tester.runAsync(h.values), contains('Kijkt op vrijdagavond met het gezin'));
      expect(tester.widget<EditableText>(input()).readOnly, isTrue);

      await tester.tap(memoryId(AutomationIds.assistantMemoryButton, 'accept'));
      await settle(tester, 10);
      final values = await tester.runAsync(h.values);
      expect(values, contains('Kijkt op zaterdagavond met het gezin'));
      expect(values, isNot(contains('Kijkt op vrijdagavond met het gezin')));
      expect(find.byType(BigPMemoryCard), findsNothing);
      expect(h.overviewModel.calls, 2);
      await close(tester);
    });

    testWidgets('"Niet vervangen" changes nothing and writes no new overview', (tester) async {
      await open(tester);
      final friday = (await tester.runAsync(h.service.list))!.firstWhere((f) => f.value.contains('vrijdagavond'));
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {'value': 'Kijkt op zaterdag', 'category': 'household', 'replaces': friday.ref}),
        say('Zal ik dat aanpassen?'),
      ]);
      await type(tester, 'We kijken tegenwoordig op zaterdag met het gezin');
      await tester.tap(memoryId(AutomationIds.assistantMemoryButton, 'decline'));
      await settle(tester);

      expect(await tester.runAsync(h.values), contains('Kijkt op vrijdagavond met het gezin'));
      expect(find.byType(BigPMemoryCard), findsNothing);
      expect(h.overviewModel.calls, 1);
      await close(tester);
    });

    testWidgets('an answer can be closed, and no model says why nothing came', (tester) async {
      await open(tester);
      h.config = null;
      await type(tester, 'Wat weet je over mij?');
      expect(find.text(s.needsSetup), findsOneWidget);

      await tester.tap(memoryAction('dismiss'));
      await settle(tester);
      expect(find.text(s.needsSetup), findsNothing);
      await close(tester);
    });
  });

  group('duik dieper', () {
    testWidgets('a tapped follow-up is asked as a follow-up, never as the user\'s typed words', (tester) async {
      await open(tester);
      h.hostModel = ScriptedModel([callTool('recall_memory'), say('Je houdt niet van horror.')]);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await settle(tester);
      await tester.tap(memoryId(AutomationIds.settingsMemoryFollowUp, '1'));
      await settle(tester, 10);

      expect(h.host.asked, [(text: 'Welke misdaadseries heb ik nog niet gezien?', typed: false)]);
      expect(find.text('Je houdt niet van horror.'), findsOneWidget);
      await close(tester);
    });

    testWidgets('a follow-up that leads to a write gets a card and stores nothing by itself', (tester) async {
      await open(tester);
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {'value': 'Kijkt graag thrillers', 'category': 'preference'}),
        say('Zal ik dat onthouden?'),
      ]);
      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await settle(tester);
      await tester.tap(memoryId(AutomationIds.settingsMemoryFollowUp, '0'));
      await settle(tester, 10);

      expect(find.byType(BigPMemoryCard), findsOneWidget);
      expect(await tester.runAsync(h.values), hasLength(6));
      await close(tester);
    });
  });

  group('profile isolation', () {
    testWidgets('another profile session shows none of the first profile\'s facts', (tester) async {
      await open(tester);
      expect(find.text('Je houdt niet van horror. Aan musicals heb je een hekel.'), findsOneWidget);

      // The profile switch: a new session with its own service on the same database.
      final other = MemoryScreenHarness(profileId: 'profile-b', database: h.db);
      await tester.runAsync(
        () => other.service.add(
          value: 'Kijkt het liefst anime',
          category: MemoryCategory.preference,
          source: MemorySource.settingsManual,
        ),
      );
      other.config = null;
      await pumpMemoryApp(
        tester,
        AssistantMemoryScreen(key: const ValueKey('profile-b'), model: other.model),
        sessionKey: const ValueKey('session-b'),
      );

      expect(find.text('Kijkt het liefst anime'), findsOneWidget);
      expect(find.textContaining('horror'), findsNothing);
      expect(find.textContaining('vrijdagavond'), findsNothing);
      expect(other.model.count, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      other.model.dispose();
      other.servers.dispose();
      await close(tester);
    });

    testWidgets('a screen whose profile is no longer the active one shows no facts and writes none', (tester) async {
      await open(tester);
      h.active = 'profile-b';
      await tester.runAsync(h.model.load);
      await settle(tester);

      expect(h.model.view, MemoryScreenView.error);
      expect(find.textContaining('horror'), findsNothing);
      final result = await tester.runAsync(() => h.model.add('Houdt van westerns', MemoryCategory.preference));
      expect(result!.code, MemoryCode.profileGone);
      expect(await tester.runAsync(h.values), hasLength(6));
      await close(tester);
    });
  });

  group('sizes', () {
    testWidgets('iPhone SE: nothing overflows, with the card up as well', (tester) async {
      await open(tester, size: phoneSeSize);
      final friday = (await tester.runAsync(h.service.list))!.firstWhere((f) => f.value.contains('vrijdagavond'));
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {'value': 'Kijkt op zaterdag', 'category': 'household', 'replaces': friday.ref}),
        say('Zal ik dat aanpassen?'),
      ]);
      await type(tester, 'We kijken tegenwoordig op zaterdag met het gezin');

      expect(tester.takeException(), isNull);
      final decline = memoryId(AutomationIds.assistantMemoryButton, 'decline');
      expect(tester.getRect(decline).bottom, lessThanOrEqualTo(tester.getTopLeft(input()).dy));
      expect(tester.getRect(decline).height, greaterThanOrEqualTo(44));
      await close(tester);
    });
  });
}
