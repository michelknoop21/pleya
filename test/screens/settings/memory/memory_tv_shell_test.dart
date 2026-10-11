// The memory screens on TV inside the shell: under the band of the top
// navigation, with the app's own fonts and the panel the shell hosts. What
// has to fit the screen is measured here, and where the remote stands after
// every press.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_fact_sheet.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';

import '../../../test_helpers/golden.dart';
import 'memory_finders.dart';
import 'memory_screen_support.dart';

void main() {
  late MemoryScreenHarness h;
  late FakeSpeech speech;

  /// The lowest line the tvOS safe area leaves: 60 pt of the 1080 pt canvas.
  final safeBottom = tvSize.height * (1 - 60 / 1080);
  final band = tvNavBand(tvSize);

  Future<void> open(WidgetTester tester, {bool list = false, List<(String, dynamic, dynamic)>? facts}) async {
    await tester.runAsync(useDutch);
    await tester.runAsync(() => facts == null ? h.seed() : h.seed([for (final f in facts) (f.$1, f.$2, f.$3)]));
    if (h.overviewModel is! HeldModel) {
      h.overviewModel = ScriptedModel([for (var i = 0; i < 6; i++) say(mockupOverviewReply())]);
    }
    await pumpMemoryApp(
      tester,
      list ? MemoryListScreen(model: h.model, speech: speech) : AssistantMemoryScreen(model: h.model, speech: speech),
      size: tvSize,
      tv: true,
    );
    if (list) {
      await tester.runAsync(h.model.load);
      await settle(tester);
    }
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.dispose);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key, [int times = 1]) async {
    for (var i = 0; i < times; i++) {
      await tester.sendKeyEvent(key);
      await tester.pump(const Duration(milliseconds: 80));
    }
    await tester.pump(const Duration(milliseconds: 400));
  }

  const down = LogicalKeyboardKey.arrowDown;
  const up = LogicalKeyboardKey.arrowUp;
  const left = LogicalKeyboardKey.arrowLeft;
  const right = LogicalKeyboardKey.arrowRight;
  const select = LogicalKeyboardKey.select;

  Finder sheetButton(String id) => memoryId(AutomationIds.settingsMemorySheetButton, id);
  Finder sheetChip(String id) => memoryId(AutomationIds.settingsMemorySheetChip, id);

  void expectInView(WidgetTester tester, Finder finder, String what) {
    final rect = tester.getRect(finder);
    expect(rect.top, greaterThanOrEqualTo(band), reason: '$what under the navigation');
    expect(rect.bottom, lessThanOrEqualTo(safeBottom), reason: '$what above the safe area');
  }

  /// Opens the sheet of the first memory of the list.
  Future<void> openFirstFact(WidgetTester tester) async {
    await press(tester, down, 2);
    expect(focusedLabel(), 'memory.list.fact0');
    await press(tester, select);
    await settle(tester);
    expect(find.byType(MemoryFactSheet), findsOneWidget);
    expect(focusedLabel(), 'memory.sheet.field');
  }

  setUpAll(loadAppFontsForGoldens);

  setUp(() {
    h = MemoryScreenHarness();
    speech = FakeSpeech();
  });

  group('Geheugen under the navigation', () {
    testWidgets('a long answer stays in its box: the tile keeps the focus in view, the answer scrolls', (tester) async {
      await open(tester);
      final long = List.filled(
        30,
        'Je kijkt graag naar Scandinavische misdaadseries en documentaires in het weekend.',
      ).join(' ');
      h.hostModel = ScriptedModel([say('BEGIN $long EINDE')]);
      speech.next = 'Vat samen wat je over mijn smaak weet';
      await press(tester, select);
      await settle(tester, 10);

      // The remote is back on the tile, and the tile is on screen.
      expect(focusedLabel(), 'memory.tv.ask');
      expectInView(tester, memoryAction('ask'), 'the tile under the remote');
      final answer = find.textContaining('BEGIN');
      final scroll = tester.state<ScrollableState>(find.ancestor(of: answer, matching: find.byType(Scrollable)).first);
      expect(scroll.position.maxScrollExtent, greaterThan(0));
      expect(scroll.position.viewportDimension, lessThanOrEqualTo(300 * tvSize.height / 1080 + 0.5));

      // Up reaches the answer; Down and Up scroll it to its end and back.
      await press(tester, up);
      expect(focusedLabel(), 'memory.tv.answer');
      expect(scroll.position.pixels, 0);
      await press(tester, down);
      expect(scroll.position.pixels, greaterThan(0));
      expect(focusedLabel(), 'memory.tv.answer');
      for (var i = 0; i < 40 && scroll.position.pixels < scroll.position.maxScrollExtent; i++) {
        await press(tester, down);
      }
      expect(scroll.position.pixels, scroll.position.maxScrollExtent);
      expect(focusedLabel(), 'memory.tv.answer');
      // At the end Down goes on to the tiles.
      await press(tester, down);
      expect(focusedLabel(), 'memory.tv.ask');
      expectInView(tester, memoryAction('ask'), 'the tile after the answer');
      await press(tester, up);
      for (var i = 0; i < 40 && scroll.position.pixels > 0; i++) {
        await press(tester, up);
      }
      expect(scroll.position.pixels, 0);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('a short answer is no stop: Up from the first tile leaves for the navigation', (tester) async {
      await open(tester);
      h.hostModel = ScriptedModel([say('Je houdt niet van horror.')]);
      speech.next = 'Wat weet je over mij';
      await press(tester, select);
      await settle(tester, 10);
      expect(find.text('Je houdt niet van horror.'), findsOneWidget);
      await press(tester, up);
      expect(focusedLabel(), isNot('memory.tv.answer'));
      await close(tester);
    });

    testWidgets('every tile is reached with Down and stands in view when the remote is on it', (tester) async {
      await open(tester);
      // Before any press: the last management tile is on screen already.
      expectInView(tester, memoryAction('clear'), '"Alle herinneringen wissen" at rest');
      for (final key in ['followUp0', 'followUp1', 'followUp2', 'manage', 'use', 'rewrite', 'clear']) {
        await press(tester, down);
        expect(focusedLabel(), 'memory.tv.$key');
        final node = FocusManager.instance.primaryFocus!;
        expect(node.rect.top, greaterThanOrEqualTo(band), reason: key);
        expect(node.rect.bottom, lessThanOrEqualTo(safeBottom), reason: key);
      }
      await close(tester);
    });

    testWidgets('after wiping everything the remote leaves the tile that has nothing left to do', (tester) async {
      await open(tester);
      await press(tester, down, 7);
      expect(focusedLabel(), 'memory.tv.clear');
      await press(tester, select);
      await settle(tester);
      await press(tester, right);
      await press(tester, select);
      await settle(tester, 10);

      expect(h.model.view, MemoryScreenView.empty);
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });
  });

  group('the panel of one memory', () {
    testWidgets('fits the screen: Annuleren, Opslaan and Verwijderen in view without scrolling', (tester) async {
      await open(tester, list: true);
      await openFirstFact(tester);

      for (final id in ['cancel', 'save', 'delete']) {
        final rect = tester.getRect(sheetButton(id));
        expect(rect.top, greaterThan(tvSize.height * 60 / 1080), reason: id);
        expect(rect.bottom, lessThanOrEqualTo(safeBottom), reason: id);
      }
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: memoryId(AutomationIds.settingsMemorySheet), matching: find.byType(Scrollable)).first,
      );
      expect(scroll.position.maxScrollExtent, 0, reason: 'nothing of the panel is under a fold');
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('the remote walks both rows of categories, and every button', (tester) async {
      await open(tester, list: true);
      await openFirstFact(tester);
      // The first memory is a habit: its chip stands in the second row.
      final row1 = tester.getRect(sheetChip('preference')).top;
      final row2 = tester.getRect(sheetChip('habit')).top;
      expect(row2, greaterThan(row1), reason: 'the categories take two rows');
      expect(tester.getRect(sheetChip('other')).top, row2);

      // Down from the text lands on the chosen category.
      await press(tester, down);
      expect(focusedLabel(), 'memory.sheet.chip.habit');
      // Left and Right walk all five in order, across the rows.
      await press(tester, right);
      expect(focusedLabel(), 'memory.sheet.chip.other');
      await press(tester, right);
      expect(focusedLabel(), 'memory.sheet.chip.other');
      for (final id in ['habit', 'household', 'dislike', 'preference']) {
        await press(tester, left);
        expect(focusedLabel(), 'memory.sheet.chip.$id');
      }
      // Down goes one row down, not past it.
      await press(tester, down);
      expect(focusedLabel(), 'memory.sheet.chip.habit');
      await press(tester, up);
      expect(focusedLabel(), 'memory.sheet.chip.preference');
      await press(tester, right, 2);
      expect(focusedLabel(), 'memory.sheet.chip.household');
      await press(tester, down);
      expect(focusedLabel(), anyOf('memory.sheet.chip.habit', 'memory.sheet.chip.other'));
      // Under the last row: the buttons. Nothing changed, so Opslaan is off.
      await press(tester, down);
      expect(holdsFocus(tester, sheetButton('cancel')), isTrue);
      await press(tester, down);
      expect(holdsFocus(tester, sheetButton('delete')), isTrue);
      await press(tester, up);
      expect(holdsFocus(tester, sheetButton('cancel')), isTrue);
      // Up from the buttons: back on the chosen category, then the text.
      await press(tester, up);
      expect(focusedLabel(), 'memory.sheet.chip.habit');
      await press(tester, up);
      expect(focusedLabel(), 'memory.sheet.chip.preference');
      await press(tester, up);
      expect(focusedLabel(), 'memory.sheet.field');

      // Another category chosen: Down from its row now ends on Opslaan.
      await press(tester, down);
      await press(tester, right);
      expect(focusedLabel(), 'memory.sheet.chip.other');
      await press(tester, select);
      await press(tester, down);
      expect(holdsFocus(tester, sheetButton('save')), isTrue);
      await close(tester);
    });

    testWidgets('saving closes the panel at once and the remote is on a tile, while Big P still writes', (
      tester,
    ) async {
      final slow = HeldModel([for (var i = 0; i < 4; i++) say(mockupOverviewReply())], free: 1);
      h.overviewModel = slow;
      await open(tester, list: true);
      await openFirstFact(tester);
      speech.next = 'Kijkt doordeweeks alleen korte films';
      await press(tester, select);
      await settle(tester);
      await press(tester, down, 2);
      expect(holdsFocus(tester, sheetButton('save')), isTrue);
      await press(tester, select);
      await settle(tester, 10);

      expect(slow.release.isCompleted, isFalse);
      expect(find.byType(MemoryFactSheet), findsNothing);
      expect(await tester.runAsync(h.values), contains('Kijkt doordeweeks alleen korte films'));
      // A visible focus: a tile of the list, not the scope of a closed panel.
      expect(focusedLabel(), startsWith('memory.list.'));
      expect(FocusManager.instance.primaryFocus, isNot(isA<FocusScopeNode>()));
      slow.release.complete();
      await settle(tester, 8);
      await close(tester);
    });

    testWidgets('removing the last memory of the list puts the remote on a row that is still there', (tester) async {
      await open(tester, list: true, facts: mockupFacts.sublist(0, 2));
      await press(tester, down, 3);
      expect(focusedLabel(), 'memory.list.fact1');
      await press(tester, select);
      await settle(tester);
      for (var i = 0; i < 6 && !holdsFocus(tester, sheetButton('delete')); i++) {
        await press(tester, down);
      }
      expect(holdsFocus(tester, sheetButton('delete')), isTrue);
      await press(tester, select);
      await settle(tester);
      expect(find.text(t.assistant.memory.screen.sheet.deleteTitle), findsOneWidget);
      await press(tester, right);
      await press(tester, select);
      await settle(tester, 10);

      expect(await tester.runAsync(h.values), hasLength(1));
      expect(find.byType(MemoryFactSheet), findsNothing);
      // The row is gone: the remote stands on the memory that is left.
      expect(focusedLabel(), 'memory.list.fact0');
      await press(tester, down);
      expect(focusedLabel(), 'memory.list.add');
      await close(tester);
    });
  });
}
