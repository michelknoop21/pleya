// "Herinneringen" on TV: the row that opens the system keyboard to search,
// the chip bar, the rows in focus order and the sheet of one memory. Pumped
// under the real page surface at the logical canvas of an Apple TV.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_fact_sheet.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_list_tv.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_tv_layout.dart';
import 'package:pleya/widgets/tv/tv_page_surface.dart';

import 'memory_finders.dart';
import 'memory_screen_support.dart';

/// Read per use: the locale is set inside each test.
TranslationsAssistantMemoryScreenEn get s => t.assistant.memory.screen;

void main() {
  late MemoryScreenHarness h;
  late FakeSpeech speech;

  Future<void> open(WidgetTester tester, {bool seed = true, bool list = false, List<Object>? overview}) async {
    await tester.runAsync(useDutch);
    if (seed) await tester.runAsync(h.seed);
    h.overviewModel = ScriptedModel(overview ?? [for (var i = 0; i < 4; i++) say(mockupOverviewReply())]);
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
  }

  const down = LogicalKeyboardKey.arrowDown;
  const up = LogicalKeyboardKey.arrowUp;
  const right = LogicalKeyboardKey.arrowRight;
  const select = LogicalKeyboardKey.select;
  const menu = LogicalKeyboardKey.escape;

  setUp(() {
    h = MemoryScreenHarness();
    speech = FakeSpeech();
  });

  group('the list on TV', () {
    testWidgets('"Herinneringen beheren" opens the list, and Menu comes back', (tester) async {
      await open(tester);
      await press(tester, down, 4);
      expect(focusedLabel(), 'memory.tv.manage');
      await press(tester, select);
      await settle(tester);

      expect(find.byType(MemoryListTv), findsOneWidget);
      expect(focusedLabel(), 'memory.list.search');

      await press(tester, menu);
      await settle(tester);
      expect(find.byType(MemoryListTv), findsNothing);
      expect(find.byType(MemoryTvLayout), findsOneWidget);
      await close(tester);
    });

    testWidgets('a row "Zoeken" opens the system keyboard, chips filter, rows walk in order', (tester) async {
      h.kidsAges = const [8, 11];
      await open(tester, list: true);

      expect(find.byType(TvPageSurface), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      expect(focusedLabel(), 'memory.list.search');
      expect(find.text(s.list.searchTv), findsOneWidget);

      speech.next = 'gezin';
      await press(tester, select);
      await settle(tester);
      expect(speech.captures.single.action, 'search');
      expect(tester.state<MemoryListScreenState>(find.byType(MemoryListScreen)).shown, hasLength(1));
      expect(find.text(s.list.searchClear), findsOneWidget);
      expect(focusedLabel(), 'memory.list.search');

      // Down: the clear tile, the chip of the chosen category, the first row.
      await press(tester, down);
      expect(focusedLabel(), 'memory.list.searchClear');
      await press(tester, select);
      await settle(tester);
      expect(tester.state<MemoryListScreenState>(find.byType(MemoryListScreen)).shown, hasLength(6));
      expect(focusedLabel(), 'memory.list.search');

      await press(tester, down);
      expect(focusedLabel(), 'chip_all');
      await press(tester, right, 2);
      expect(focusedLabel(), 'chip_dislike');
      await press(tester, select);
      await settle(tester);
      expect(tester.state<MemoryListScreenState>(find.byType(MemoryListScreen)).shown, hasLength(2));

      await press(tester, down);
      expect(focusedLabel(), 'memory.list.fact0');
      await press(tester, down);
      expect(focusedLabel(), 'memory.list.fact1');
      await press(tester, down);
      expect(focusedLabel(), 'memory.list.kidsAges');
      await press(tester, down);
      expect(focusedLabel(), 'memory.list.add');
      await press(tester, up, 3);
      expect(focusedLabel(), 'memory.list.fact0');
      await press(tester, up);
      expect(focusedLabel(), 'chip_dislike');
      await close(tester);
    });

    testWidgets('a memory opens its sheet; the text is edited through the system keyboard', (tester) async {
      await open(tester, list: true);
      await press(tester, down, 2);
      expect(focusedLabel(), 'memory.list.fact0');
      await press(tester, select);
      await settle(tester);

      expect(find.byType(MemoryFactSheet), findsOneWidget);
      expect(find.byType(EditableText), findsNothing);
      expect(focusedLabel(), 'memory.sheet.field');

      speech.next = 'Kijkt doordeweeks alleen korte films';
      await press(tester, select);
      await settle(tester);
      expect(speech.captures.last.initial, 'Kijkt doordeweeks geen films langer dan twee uur');
      expect(find.text('Kijkt doordeweeks alleen korte films'), findsOneWidget);

      // Down past the category chips to the buttons.
      final save = memoryId(AutomationIds.settingsMemorySheetButton, 'save');
      final cancel = memoryId(AutomationIds.settingsMemorySheetButton, 'cancel');
      for (var i = 0; i < 8 && !holdsFocus(tester, save) && !holdsFocus(tester, cancel); i++) {
        await press(tester, down);
      }
      if (holdsFocus(tester, cancel)) await press(tester, right);
      expect(holdsFocus(tester, save), isTrue);
      await press(tester, select);
      await settle(tester, 10);
      expect(find.byType(MemoryFactSheet), findsNothing);
      expect(await tester.runAsync(h.values), contains('Kijkt doordeweeks alleen korte films'));
      await close(tester);
    });

    testWidgets('unreadable facts: an error with a retry tile, never "geen herinneringen"', (tester) async {
      h = MemoryScreenHarness(unreadable: true);
      await open(tester, list: true);

      expect(find.text(s.error.title), findsOneWidget);
      expect(find.text(s.list.none), findsNothing);
      expect(memoryAction('retry'), findsOneWidget);
      expect(memoryAction('add'), findsNothing);
      await close(tester);
    });
  });
}
