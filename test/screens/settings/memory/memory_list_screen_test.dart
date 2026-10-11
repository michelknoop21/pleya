// "Herinneringen" (43 D) and the sheet of one memory (43 E, F): search,
// filter, add, edit, delete, the fixed refusals and the reading error.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_fact_sheet.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';

import 'memory_finders.dart';
import 'memory_screen_support.dart';

/// Read per use: the locale is set inside each test.
TranslationsAssistantMemoryScreenEn get s => t.assistant.memory.screen;

void main() {
  late MemoryScreenHarness h;

  Future<void> open(WidgetTester tester, {bool seed = true, Size size = phoneSize}) async {
    await tester.runAsync(useDutch);
    if (seed) await tester.runAsync(h.seed);
    // Every change of the list asks for a new overview; any reply will do.
    h.overviewModel = ScriptedModel([for (var i = 0; i < 6; i++) say(mockupOverviewReply())]);
    await pumpMemoryApp(tester, MemoryListScreen(model: h.model), size: size);
    await tester.runAsync(h.model.load);
    await settle(tester);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.dispose);
  }

  Finder fact(int i) => memoryId(AutomationIds.settingsMemoryFact, '$i');
  Finder chip(String id) => memoryId(AutomationIds.settingsMemoryChip, id);
  Finder sheetButton(String id) => memoryId(AutomationIds.settingsMemorySheetButton, id);
  Finder sheetField() =>
      find.descendant(of: memoryId(AutomationIds.settingsMemorySheetField), matching: find.byType(EditableText));
  Finder search() => find.descendant(of: memoryAction('search'), matching: find.byType(EditableText));

  Future<void> openAdd(WidgetTester tester) async {
    await tester.dragUntilVisible(memoryAction('add'), find.byType(ListView).first, const Offset(0, -120));
    await tapOn(tester, memoryAction('add'));
    await settle(tester);
  }

  Future<void> save(WidgetTester tester, String text) async {
    await tester.enterText(sheetField(), text);
    await tester.pump();
    await tapOn(tester, sheetButton('save'));
    await settle(tester, 8);
  }

  setUp(() => h = MemoryScreenHarness());

  testWidgets('lists every memory with its text, category and origin, newest change first', (tester) async {
    await open(tester);

    expect(find.text(s.list.title), findsOneWidget);
    expect(find.text(s.list.profile(name: 'Michel')), findsOneWidget);
    expect(find.text(s.list.count(n: 6)), findsOneWidget);
    expect(
      find.descendant(of: fact(0), matching: find.text('Kijkt doordeweeks geen films langer dan twee uur')),
      findsOne,
    );
    expect(find.text('${t.assistant.memory.categories.habit} · ${s.sources.userExplicit}'), findsOneWidget);
    expect(find.text('${t.assistant.memory.categories.dislike} · ${s.sources.assistantConfirmed}'), findsNWidgets(2));
    expect(find.text('${t.assistant.memory.categories.preference} · ${s.sources.settingsManual}'), findsOneWidget);
    await close(tester);
  });

  testWidgets('a category chip filters the list and the counter says how many are left (43 D)', (tester) async {
    await open(tester);
    await tapOn(tester, chip('dislike'));
    await settle(tester);

    expect(find.text(s.list.countOf(n: 2, m: 6)), findsOneWidget);
    expect(find.text('Houdt niet van horror'), findsOneWidget);
    expect(find.text('Heeft een hekel aan musicals'), findsOneWidget);
    expect(find.text('Kijkt op vrijdagavond met het gezin'), findsNothing);

    await tapOn(tester, chip('all'));
    await settle(tester);
    expect(find.text(s.list.count(n: 6)), findsOneWidget);
    await close(tester);
  });

  testWidgets('searching keeps the memories that hold every word, whatever the case or accents', (tester) async {
    await open(tester);
    await tester.enterText(search(), 'GEZIN vrijdagavond');
    await settle(tester);

    expect(find.text(s.list.countOf(n: 1, m: 6)), findsOneWidget);
    expect(find.text('Kijkt op vrijdagavond met het gezin'), findsOneWidget);

    await tester.enterText(search(), 'westerns');
    await settle(tester);
    expect(find.text(s.list.none), findsOneWidget);
    expect(find.text(s.list.countOf(n: 0, m: 6)), findsOneWidget);
    await close(tester);
  });

  group('leeftijden kinderen', () {
    testWidgets('a reference row to Kinderprofiel under the list, only when ages are set', (tester) async {
      h.kidsAges = const [11, 8];
      await open(tester);
      await tester.dragUntilVisible(memoryAction('kidsAges'), find.byType(ListView).first, const Offset(0, -120));
      await settle(tester);

      expect(find.text(s.list.kidsHeader.toUpperCase()), findsOneWidget);
      expect(find.text(s.list.kidsAges), findsOneWidget);
      expect(find.text(s.list.kidsAgesNote), findsOneWidget);
      expect(find.text('8 en 11'), findsOneWidget);
      // Outside the list of memories: it is no memory and is not counted.
      expect(tester.state<MemoryListScreenState>(find.byType(MemoryListScreen)).shown, hasLength(6));
      expect(h.model.count, 6);
      expect(tester.getTopLeft(memoryAction('kidsAges')).dy, greaterThan(tester.getBottomLeft(fact(5)).dy));
      expect(
        find.ancestor(
          of: memoryAction('kidsAges'),
          matching: find.byWidget(tester.widget(find.ancestor(of: fact(5), matching: find.byType(Material)).first)),
        ),
        findsNothing,
      );
      await close(tester);
    });

    testWidgets('no row without ages', (tester) async {
      await open(tester);
      expect(find.text(s.list.kidsHeader.toUpperCase()), findsNothing);
      expect(memoryAction('kidsAges'), findsNothing);
      await close(tester);
    });
  });

  group('herinnering toevoegen (43 F)', () {
    testWidgets('stores what the user typed as a manual memory in the chosen category', (tester) async {
      await open(tester);
      await openAdd(tester);

      expect(find.descendant(of: find.byType(MemoryFactSheet), matching: find.text(s.sheet.addTitle)), findsOne);
      expect(find.text('0/200'), findsOneWidget);
      expect(find.text(s.sheet.privacy), findsOneWidget);
      // Nothing to save yet.
      await tapOn(tester, sheetButton('save'));
      await settle(tester);
      expect(find.byType(MemoryFactSheet), findsOneWidget);

      await tester.enterText(sheetField(), 'Kijkt graag westerns');
      await tester.pump();
      expect(find.text('20/200'), findsOneWidget);
      await tapOn(tester, memoryId(AutomationIds.settingsMemorySheetChip, 'habit'));
      await tester.pump();
      await tapOn(tester, sheetButton('save'));
      await settle(tester, 8);

      expect(find.byType(MemoryFactSheet), findsNothing);
      final stored = (await tester.runAsync(h.service.list))!.first;
      expect(stored.value, 'Kijkt graag westerns');
      expect(stored.category, MemoryCategory.habit);
      expect(stored.source, MemorySource.settingsManual);
      expect(h.model.count, 7);
      expect(find.text('Kijkt graag westerns', skipOffstage: false), findsOneWidget);
      // The facts changed with the screen open: the overview is written again.
      expect(h.overviewModel.calls, 2);
      await close(tester);
    });

    testWidgets('Annuleren stores nothing', (tester) async {
      await open(tester);
      await openAdd(tester);
      await tester.enterText(sheetField(), 'Kijkt graag westerns');
      await tester.pump();
      await tapOn(tester, sheetButton('cancel'));
      await settle(tester);

      expect(find.byType(MemoryFactSheet), findsNothing);
      expect(await tester.runAsync(h.values), hasLength(6));
      await close(tester);
    });

    for (final (text, code) in [
      ('Onze dochter is 8 jaar', MemoryCode.ownedKidsAges),
      ('Ik wil altijd Nederlandse ondertitels', MemoryCode.ownedLanguage),
      ('houdt niet van HORROR!', MemoryCode.exists),
      ('x' * 201, MemoryCode.tooLong),
    ]) {
      testWidgets('a refused sentence stays in the sheet with a readable line: ${code.name}', (tester) async {
        await open(tester);
        await openAdd(tester);
        await save(tester, text);

        expect(find.byType(MemoryFactSheet), findsOneWidget);
        final line = switch (code) {
          MemoryCode.ownedKidsAges => s.codes.ownedKidsAges,
          MemoryCode.ownedLanguage => s.codes.ownedLanguage,
          MemoryCode.exists => s.codes.exists,
          _ => s.codes.tooLong(max: 200),
        };
        expect(find.text(line), findsOneWidget);
        expect(await tester.runAsync(h.values), hasLength(6));
        await close(tester);
      });
    }
  });

  group('herinnering bewerken (43 E)', () {
    testWidgets('shows the text, the category, the origin and both dates', (tester) async {
      await open(tester);
      await tapOn(tester, chip('dislike'));
      await settle(tester);
      await tapOn(tester, fact(1));
      await settle(tester);

      expect(find.text(s.sheet.title), findsOneWidget);
      expect(tester.widget<EditableText>(sheetField()).controller.text, 'Houdt niet van horror');
      expect(find.text('21/200'), findsOneWidget);
      expect(find.text(s.sheet.source), findsOneWidget);
      expect(
        find.descendant(of: find.byType(MemoryFactSheet), matching: find.text(s.sources.assistantConfirmed)),
        findsOne,
      );
      expect(find.text(s.sheet.created), findsOneWidget);
      expect(find.text(s.sheet.updated), findsOneWidget);
      expect(find.text('11 oktober 2026'), findsNWidgets(2));
      await close(tester);
    });

    testWidgets('saving a change makes it a manual memory', (tester) async {
      await open(tester);
      await tapOn(tester, chip('dislike'));
      await settle(tester);
      await tapOn(tester, fact(1));
      await settle(tester);
      await tapOn(tester, memoryId(AutomationIds.settingsMemorySheetChip, 'other'));
      await tester.pump();
      await save(tester, 'Houdt niet van horror of slashers');

      expect(find.byType(MemoryFactSheet), findsNothing);
      final changed = (await tester.runAsync(h.service.list))!.first;
      expect(changed.value, 'Houdt niet van horror of slashers');
      expect(changed.category, MemoryCategory.other);
      expect(changed.source, MemorySource.settingsManual);
      expect(await tester.runAsync(h.values), hasLength(6));
      await close(tester);
    });

    testWidgets('a change into the sentence of another memory is refused as a duplicate', (tester) async {
      await open(tester);
      await tapOn(tester, fact(0));
      await settle(tester);
      await save(tester, 'Houdt niet van horror');

      expect(find.byType(MemoryFactSheet), findsOneWidget);
      expect(find.text(s.codes.duplicate), findsOneWidget);
      expect(await tester.runAsync(h.values), contains('Kijkt doordeweeks geen films langer dan twee uur'));
      await close(tester);
    });

    testWidgets('Verwijderen asks first, and removes only after the yes', (tester) async {
      await open(tester);
      await tapOn(tester, fact(0));
      await settle(tester);
      await tapOn(tester, sheetButton('delete'));
      await settle(tester);

      expect(find.text(s.sheet.deleteTitle), findsOneWidget);
      expect(holdsFocus(tester, memoryId(AutomationIds.settingsMemoryDialogButton, 'cancel')), isTrue);
      expect(await tester.runAsync(h.values), hasLength(6));

      await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'cancel'));
      await settle(tester);
      expect(await tester.runAsync(h.values), hasLength(6));
      expect(find.byType(MemoryFactSheet), findsOneWidget);

      await tapOn(tester, sheetButton('delete'));
      await settle(tester);
      await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm'));
      await settle(tester, 8);
      expect(find.byType(MemoryFactSheet), findsNothing);
      final values = await tester.runAsync(h.values);
      expect(values, hasLength(5));
      expect(values, isNot(contains('Kijkt doordeweeks geen films langer dan twee uur')));
      expect(find.text(s.list.count(n: 5)), findsOneWidget);
      await close(tester);
    });
  });

  testWidgets('a children\'s profile looks and removes: no adding, no editing', (tester) async {
    h.kids = true;
    await open(tester);

    expect(memoryAction('add'), findsNothing);
    await tapOn(tester, fact(0));
    await settle(tester);
    expect(find.text(s.sheet.readOnly), findsOneWidget);
    expect(sheetButton('save'), findsNothing);
    expect(sheetField(), findsNothing);

    await tapOn(tester, sheetButton('delete'));
    await settle(tester);
    await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm'));
    await settle(tester, 8);
    expect(await tester.runAsync(h.values), hasLength(5));
    // No overview is written on a children's profile.
    expect(h.overviewModel.calls, 0);
    await close(tester);
  });

  testWidgets('unreadable facts are an error with a retry, never "geen herinneringen"', (tester) async {
    h = MemoryScreenHarness(unreadable: true);
    await open(tester);

    expect(h.model.view, MemoryScreenView.error);
    expect(find.text(s.error.title), findsOneWidget);
    expect(find.text(s.list.none), findsNothing);
    expect(find.text(s.list.count(n: 0)), findsNothing);
    expect(find.text(s.list.header.toUpperCase()), findsNothing);
    expect(memoryAction('add'), findsNothing);

    (h.service as UnreadableMemoryService).broken = false;
    await tapOn(tester, memoryAction('retry'));
    await settle(tester, 8);
    expect(find.text(s.list.count(n: 6)), findsOneWidget);
    await close(tester);
  });

  testWidgets('an empty memory says so and offers to add', (tester) async {
    await open(tester, seed: false);

    expect(find.text(s.list.none), findsOneWidget);
    expect(memoryAction('add'), findsOneWidget);
    await close(tester);
  });

  testWidgets('iPhone SE with text at 1.3: the sheet keeps its buttons on screen', (tester) async {
    await tester.runAsync(useDutch);
    await tester.runAsync(h.seed);
    h.overviewModel = ScriptedModel([say(mockupOverviewReply())]);
    await pumpMemoryApp(tester, MemoryListScreen(model: h.model), size: phoneSeSize, textScale: 1.3);
    await tester.runAsync(h.model.load);
    await settle(tester);
    await tapOn(tester, fact(0));
    await settle(tester);

    expect(tester.takeException(), isNull);
    await tester.ensureVisible(sheetButton('delete'));
    await settle(tester);
    expect(tester.getRect(sheetButton('delete')).bottom, lessThanOrEqualTo(phoneSeSize.height));
    await close(tester);
  });
}
