// Geheugen on TV (43 M) and its list: the two columns, the focus order of
// the tiles, text through the system keyboard, the card and the dialogs with
// the remote on the safe button, and Menu. Pumped under the real page
// surface at the logical canvas of an Apple TV.
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';
import 'package:pleya/screens/settings/memory/memory_tv_layout.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_memory_card.dart';
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
  const left = LogicalKeyboardKey.arrowLeft;
  const right = LogicalKeyboardKey.arrowRight;
  const select = LogicalKeyboardKey.select;
  const menu = LogicalKeyboardKey.escape;

  setUp(() {
    h = MemoryScreenHarness();
    speech = FakeSpeech();
  });

  group('layout (43 M)', () {
    testWidgets('the overview on the left, the tiles on the right, all of them on screen', (tester) async {
      await open(tester);

      expect(find.byType(MemoryTvLayout), findsOneWidget);
      expect(find.byType(TvPageSurface), findsOneWidget);
      expect(find.text(s.title), findsOneWidget);
      expect(find.text(s.status.updated), findsOneWidget);
      final text = tester.getRect(find.text(s.sections.overview));
      for (final tile in ['ask', 'manage', 'use', 'rewrite', 'clear']) {
        final rect = tester.getRect(memoryAction(tile));
        expect(rect.left, greaterThan(text.right), reason: tile);
        expect(rect.bottom, lessThanOrEqualTo(tvSize.height), reason: tile);
      }
      // "Overzicht opnieuw schrijven" is the fourth management tile.
      expect(tester.getRect(memoryAction('rewrite')).top, greaterThan(tester.getRect(memoryAction('use')).bottom - 1));
      expect(
        tester.getRect(memoryAction('clear')).top,
        greaterThan(tester.getRect(memoryAction('rewrite')).bottom - 1),
      );
      expect(find.text(s.askTvHint), findsOneWidget);
      expect(find.text(s.deeper), findsOneWidget);
      expect(find.text(s.menu.management), findsOneWidget);
      expect(find.text(s.menu.useOn), findsOneWidget);
      // No text field on TV: text comes from the system keyboard.
      expect(find.byType(EditableText), findsNothing);
      expect(tester.takeException(), isNull);
      await close(tester);
    });

    testWidgets('the reading text is tvOS body size and the smallest text 23 pt', (tester) async {
      await open(tester);
      const pt = 584 / 1080;

      final body = tester.widget<Text>(find.text('Je houdt niet van horror. Aan musicals heb je een hekel.'));
      expect(body.style!.fontSize, closeTo(29 * pt, 0.01));
      final hint = tester.widget<Text>(find.text(s.askTvHint));
      expect(hint.style!.fontSize, closeTo(23 * pt, 0.01));
      final status = tester.widget<Text>(find.text(s.status.updated));
      expect(status.style!.fontSize, closeTo(23 * pt, 0.01));
      await close(tester);
    });
  });

  group('focus', () {
    testWidgets('opens on "Vraag of werk bij" and walks the tiles top to bottom and back', (tester) async {
      await open(tester);
      expect(focusedLabel(), 'memory.tv.ask');

      const order = ['followUp0', 'followUp1', 'followUp2', 'manage', 'use', 'rewrite', 'clear'];
      for (final key in order) {
        await press(tester, down);
        expect(focusedLabel(), 'memory.tv.$key');
      }
      // The last tile is the end: Down and Right leave the focus there.
      await press(tester, down);
      await press(tester, right);
      expect(focusedLabel(), 'memory.tv.clear');
      // The text of 43 M is longer than the screen: Left reads it, Right
      // comes back to the tile the remote left.
      await press(tester, left);
      expect(focusedLabel(), 'memory.tv.read');
      await press(tester, right);
      expect(focusedLabel(), 'memory.tv.clear');

      for (final key in order.reversed.skip(1)) {
        await press(tester, up);
        expect(focusedLabel(), 'memory.tv.$key');
      }
      await press(tester, up);
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });

    testWidgets('a text longer than the screen is a stop that Up and Down scroll', (tester) async {
      final long = 'Je kijkt graag. ' * 30;
      await open(
        tester,
        overview: [
          say('{"overview":"$long","preference":"$long","dislike":"$long","household":"$long","habit":"$long"}'),
        ],
      );
      expect(focusedLabel(), 'memory.tv.ask');

      await press(tester, left);
      expect(focusedLabel(), 'memory.tv.read');
      final scroll = tester.state<ScrollableState>(
        find.descendant(of: memoryId(AutomationIds.settingsMemoryOverview), matching: find.byType(Scrollable)),
      );
      expect(scroll.position.pixels, 0);
      await press(tester, down);
      await tester.pump(const Duration(milliseconds: 400));
      expect(scroll.position.pixels, greaterThan(0));
      expect(focusedLabel(), 'memory.tv.read');

      await press(tester, right);
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });

    testWidgets('a text that fits is no stop: Left stays on the tile', (tester) async {
      await open(
        tester,
        overview: [
          say('{"overview":"Kort.","preference":"Kort.","dislike":"Kort.","household":"Kort.","habit":"Kort."}'),
        ],
      );
      await press(tester, left);
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });
  });

  group('vraag of werk bij', () {
    testWidgets('Select opens the system keyboard and asks what came back as typed', (tester) async {
      await open(tester);
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {'value': 'Kijkt graag thrillers', 'category': 'preference'}),
        say('Genoteerd.'),
      ]);
      speech.next = 'Onthoud dat ik graag thrillers kijk';
      await press(tester, select);
      await settle(tester, 10);

      expect(speech.captures.single.prompt, s.ask);
      expect(speech.captures.single.action, 'send');
      expect(h.host.asked, [(text: 'Onthoud dat ik graag thrillers kijk', typed: true)]);
      expect(await tester.runAsync(h.values), contains('Ik graag thrillers kijk'));
      expect(find.textContaining('Ik graag thrillers kijk'), findsOneWidget);
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });

    testWidgets('backing out of the keyboard asks nothing and keeps the focus', (tester) async {
      await open(tester);
      await press(tester, select);
      await settle(tester);

      expect(speech.captures, hasLength(1));
      expect(h.host.asked, isEmpty);
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });

    testWidgets('a follow-up tile asks as a follow-up, never as typed', (tester) async {
      await open(tester);
      h.hostModel = ScriptedModel([callTool('recall_memory'), say('Je houdt niet van horror.')]);
      await press(tester, down, 2);
      await press(tester, select);
      await settle(tester, 10);

      expect(h.host.asked, [(text: 'Welke misdaadseries heb ik nog niet gezien?', typed: false)]);
      expect(speech.captures, isEmpty);
      await close(tester);
    });
  });

  group('the card', () {
    Future<void> askReplace(WidgetTester tester) async {
      final friday = (await tester.runAsync(h.service.list))!.firstWhere((f) => f.value.contains('vrijdagavond'));
      h.hostModel = ScriptedModel([
        callTool('remember_fact', {
          'value': 'Kijkt op zaterdagavond met het gezin',
          'category': 'household',
          'replaces': friday.ref,
        }),
        say('Dat pas ik aan als je het goed vindt.'),
      ]);
      speech.next = 'We kijken tegenwoordig op zaterdag met het gezin';
      await press(tester, select);
      await settle(tester, 10);
    }

    testWidgets('takes the place of the tiles with the remote on the safe button', (tester) async {
      await open(tester);
      await askReplace(tester);

      expect(find.byType(BigPMemoryCard), findsOneWidget);
      expect(focusedLabel(), 'memory.card.decline');
      expect(find.text(s.status.waiting), findsOneWidget);
      for (final tile in ['ask', 'manage', 'use', 'rewrite', 'clear']) {
        expect(memoryAction(tile), findsNothing, reason: tile);
      }
      final card = tester.getRect(find.byType(BigPMemoryCard));
      expect(card.left, greaterThan(tester.getRect(find.text(s.sections.overview)).right));
      expect(card.bottom, lessThanOrEqualTo(tvSize.height));

      // Select where the remote stands is the no.
      await press(tester, select);
      await settle(tester);
      expect(find.byType(BigPMemoryCard), findsNothing);
      expect(await tester.runAsync(h.values), contains('Kijkt op vrijdagavond met het gezin'));
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });

    testWidgets('Menu is the no and leaves the screen open', (tester) async {
      await open(tester);
      await askReplace(tester);
      await press(tester, menu);
      await settle(tester);

      expect(find.byType(BigPMemoryCard), findsNothing);
      expect(find.byType(MemoryTvLayout), findsOneWidget);
      expect(await tester.runAsync(h.values), contains('Kijkt op vrijdagavond met het gezin'));
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });

    testWidgets('Left and Select is the yes', (tester) async {
      await open(tester);
      await askReplace(tester);
      await press(tester, left);
      await press(tester, select);
      await settle(tester, 10);

      final values = await tester.runAsync(h.values);
      expect(values, contains('Kijkt op zaterdagavond met het gezin'));
      expect(values, isNot(contains('Kijkt op vrijdagavond met het gezin')));
      expect(focusedLabel(), 'memory.tv.ask');
      await close(tester);
    });
  });

  group('alle herinneringen wissen', () {
    testWidgets('the dialog opens with the remote on Annuleren, and Select there wipes nothing', (tester) async {
      await open(tester);
      await press(tester, down, 7);
      expect(focusedLabel(), 'memory.tv.clear');
      await press(tester, select);
      await settle(tester);

      expect(find.text(s.clearDialog.title), findsOneWidget);
      final cancel = memoryId(AutomationIds.settingsMemoryDialogButton, 'cancel');
      expect(holdsFocus(tester, cancel), isTrue);
      expect(holdsFocus(tester, memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm')), isFalse);

      await press(tester, select);
      await settle(tester);
      expect(find.text(s.clearDialog.title), findsNothing);
      expect(await tester.runAsync(h.values), hasLength(6));
      await close(tester);
    });

    testWidgets('Menu closes the dialog as a no', (tester) async {
      await open(tester);
      await press(tester, down, 7);
      await press(tester, select);
      await settle(tester);
      await press(tester, menu);
      await settle(tester);

      expect(find.text(s.clearDialog.title), findsNothing);
      expect(find.byType(MemoryTvLayout), findsOneWidget);
      expect(await tester.runAsync(h.values), hasLength(6));
      await close(tester);
    });

    testWidgets('Right and Select wipes, and the screen says the memory is empty', (tester) async {
      await open(tester);
      await press(tester, down, 7);
      await press(tester, select);
      await settle(tester);
      await press(tester, right);
      expect(holdsFocus(tester, memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm')), isTrue);
      await press(tester, select);
      await settle(tester, 10);

      expect(await tester.runAsync(h.values), isEmpty);
      expect(find.text(s.empty.title), findsOneWidget);
      expect(find.text(s.status.empty), findsOneWidget);
      await close(tester);
    });
  });

  group('states', () {
    testWidgets('children\'s profile: the facts to read, no tile to ask and no follow-ups', (tester) async {
      h.kids = true;
      await open(tester);

      expect(h.model.view, MemoryScreenView.kids);
      expect(find.text(s.kids.title), findsOneWidget);
      expect(find.text('Houdt niet van horror'), findsOneWidget);
      expect(memoryAction('ask'), findsNothing);
      expect(memoryId(AutomationIds.settingsMemoryFollowUp, '0'), findsNothing);
      expect(memoryAction('rewrite'), findsNothing);
      expect(memoryAction('manage'), findsOneWidget);
      expect(memoryAction('clear'), findsOneWidget);
      expect(focusedLabel(), 'memory.tv.manage');
      expect(h.overviewModel.calls, 0);
      await close(tester);
    });

    testWidgets('off: the tile to ask does nothing, the switch tile turns the memory on', (tester) async {
      h.enabledStore.on = false;
      await open(tester);

      expect(find.text(s.off.title), findsOneWidget);
      expect(find.text(s.menu.useOff), findsOneWidget);
      await press(tester, select);
      await settle(tester);
      expect(speech.captures, isEmpty);

      await press(tester, down, 2);
      expect(focusedLabel(), 'memory.tv.use');
      await press(tester, select);
      await settle(tester, 10);
      expect(h.enabledStore.on, isTrue);
      expect(find.text(s.menu.useOn), findsOneWidget);
      expect(h.model.view, MemoryScreenView.overview);
      await close(tester);
    });

    testWidgets('unreadable facts: an error and a retry tile, never an empty memory', (tester) async {
      h = MemoryScreenHarness(unreadable: true);
      await open(tester);

      expect(find.text(s.error.title), findsOneWidget);
      expect(find.text(s.empty.title), findsNothing);
      expect(memoryAction('ask'), findsNothing);
      expect(memoryAction('retry'), findsOneWidget);
      await close(tester);
    });
  });
}
