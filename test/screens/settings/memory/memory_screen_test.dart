// Instellingen > Big P > Geheugen on a phone (mockup 43 A to J): every state
// of the main screen, the menu, wiping, the field and the follow-ups.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/assistant/assistant_provider.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_overview_view.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';
import 'package:pleya/utils/media_server_http_client.dart' show AbortController;

import 'memory_finders.dart';
import 'memory_screen_support.dart';

/// Holds its reply back until [release] completes.
class _SlowModel extends ScriptedModel {
  _SlowModel(super.script);

  final release = Completer<void>();

  @override
  Future<AssistantReply> chat(
    List<Map<String, Object?>> messages,
    List<Map<String, Object?>> tools, {
    AbortController? abort,
  }) async {
    await release.future;
    return super.chat(messages, tools, abort: abort);
  }
}

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

  setUp(() => h = MemoryScreenHarness());

  group('overview', () {
    testWidgets('shows the overview Big P wrote, in sections, with the follow-ups and the footer', (tester) async {
      h.kidsAges = const [8, 11];
      await open(tester);

      expect(h.model.view, MemoryScreenView.overview);
      expect(find.text(s.title), findsOneWidget);
      expect(find.text(s.status.updated), findsOneWidget);
      for (final title in [s.sections.overview, s.sections.preference, s.sections.dislike, s.sections.household]) {
        expect(find.text(title), findsOneWidget);
      }
      expect(find.text('Je houdt niet van horror. Aan musicals heb je een hekel.'), findsOneWidget);
      // No fact of the category Overig: no such section.
      expect(find.text(s.sections.other), findsNothing);
      // The ages never go to the model: the app points to Kinderprofiel itself.
      expect(find.text('Je kijkt op vrijdagavond met het gezin. ${s.kidsAgesLine}'), findsOneWidget);
      expect(h.overviewModel.sent(0), isNot(contains('11')));

      await tester.drag(find.byType(ListView), const Offset(0, -900));
      await settle(tester);
      expect(find.text(s.deeper), findsOneWidget);
      expect(find.text('Welke misdaadseries heb ik nog niet gezien?'), findsOneWidget);
      expect(find.text('${s.footer(n: 6)} ${s.footerManageMenu}'), findsOneWidget);
      expect(input(), findsOneWidget);
      await close(tester);
    });

    testWidgets('a stored overview is shown without a second model call', (tester) async {
      await open(tester);
      expect(h.overviewModel.calls, 1);

      await tester.pumpWidget(const SizedBox.shrink());
      h.model.dispose();
      final again = MemoryScreenHarness(database: h.db);
      again.overviewModel = ScriptedModel(const []);
      await pumpMemoryApp(tester, AssistantMemoryScreen(model: again.model));

      expect(again.model.view, MemoryScreenView.overview);
      expect(again.overviewModel.calls, 0);
      expect(find.text(s.sections.overview), findsOneWidget);
      await tester.pumpWidget(const SizedBox.shrink());
      again.model.dispose();
      again.servers.dispose();
      h.servers.dispose();
      await tester.runAsync(h.db.close);
    });

    testWidgets('says how many memories the overview covers when not all fitted', (tester) async {
      await tester.runAsync(useDutch);
      await tester.runAsync(() async {
        for (var i = 0; i < 60; i++) {
          await h.service.add(
            value: 'Feit $i ${'houdt van lange zinnen over films en series ' * 5}'.substring(0, 190),
            category: MemoryCategory.preference,
            source: MemorySource.settingsManual,
          );
        }
      });
      h.overviewModel = ScriptedModel([say('{"overview":"Je kijkt veel.","preference":"Je houdt van lange zinnen."}')]);
      await pumpMemoryApp(tester, AssistantMemoryScreen(model: h.model));

      final overview = h.model.overview!;
      expect(overview.basedOn, lessThan(overview.total));
      expect(
        find.text('${s.footerPartial(n: overview.basedOn, m: 60)} ${s.footerManageMenu}', skipOffstage: false),
        findsOneWidget,
      );
      await close(tester);
    });

    testWidgets('shows the loading state while Big P writes (43 B)', (tester) async {
      final slow = _SlowModel([say(mockupOverviewReply())]);
      await tester.runAsync(useDutch);
      await tester.runAsync(h.seed);
      h.overviewModel = slow;
      await pumpMemoryApp(tester, AssistantMemoryScreen(model: h.model));

      expect(h.model.view, MemoryScreenView.writing);
      expect(find.byType(MemoryWritingDots), findsOneWidget);
      expect(find.text(s.status.writing), findsOneWidget);
      expect(find.text(s.sections.overview), findsNothing);

      slow.release.complete();
      await settle(tester, 8);
      expect(find.byType(MemoryWritingDots), findsNothing);
      expect(find.text(s.sections.overview), findsOneWidget);
      await close(tester);
    });
  });

  group('the list as fallback', () {
    Future<void> expectList(WidgetTester tester) async {
      expect(h.model.view, MemoryScreenView.list);
      expect(find.text(s.status.list), findsOneWidget);
      expect(find.text('Houdt niet van horror'), findsOneWidget);
      expect(find.text(t.assistant.memory.categories.dislike), findsOneWidget);
      expect(find.text(s.fallbackNote), findsOneWidget);
      expect(find.text(s.deeper), findsNothing);
    }

    testWidgets('without a model the facts stand per category', (tester) async {
      h.config = null;
      await open(tester, overview: const []);
      await expectList(tester);
      expect(h.overviewModel.calls, 0);
      await close(tester);
    });

    testWidgets('without a connection the facts stand per category', (tester) async {
      await open(tester, overview: [const AssistantModelException(AssistantModelError.unreachable)]);
      await expectList(tester);
      await close(tester);
    });

    testWidgets('after output that failed the format, and no new call until the user asks', (tester) async {
      await open(tester, overview: [say('geen json'), say(mockupOverviewReply())]);
      await expectList(tester);
      expect(h.overviewModel.calls, 1);

      await tester.runAsync(h.model.load);
      await settle(tester);
      expect(h.overviewModel.calls, 1);

      // "Overzicht opnieuw schrijven" from the menu is the one new attempt.
      await tester.tap(memoryAction('menu'));
      await settle(tester);
      await tester.tap(memoryAction('rewrite'));
      await settle(tester, 8);
      expect(h.overviewModel.calls, 2);
      expect(h.model.view, MemoryScreenView.overview);
      await close(tester);
    });
  });

  group('menu (43 C)', () {
    testWidgets('holds the list with its count, the switch with its note, rewriting and wiping', (tester) async {
      await open(tester);
      await tester.tap(memoryAction('menu'));
      await settle(tester);

      expect(find.text(s.menu.manage), findsOneWidget);
      expect(find.descendant(of: memoryAction('manage'), matching: find.text('6')), findsOneWidget);
      expect(find.text(s.menu.use), findsOneWidget);
      expect(find.text(s.menu.useNote), findsOneWidget);
      expect(s.menu.useNote, contains('Big P onthoudt wat je hem vraagt te onthouden'));
      expect(s.menu.useNote, contains('voor het overzicht de herinneringen van dit profiel'));
      expect(find.text(s.menu.rewrite), findsOneWidget);
      expect(find.text(s.menu.clear), findsOneWidget);
      await close(tester);
    });

    testWidgets('"Herinneringen beheren" opens the list', (tester) async {
      await open(tester);
      await tester.tap(memoryAction('menu'));
      await settle(tester);
      await tester.tap(memoryAction('manage'));
      await settle(tester);

      expect(find.byType(MemoryListScreen), findsOneWidget);
      expect(find.text(s.list.title), findsOneWidget);
      await close(tester);
    });

    testWidgets('the switch turns the memory off and the screen says so (43 I)', (tester) async {
      await open(tester);
      await tester.tap(memoryAction('menu'));
      await settle(tester);
      await tester.tap(memoryAction('use'));
      await settle(tester);

      expect(h.enabledStore.on, isFalse);
      // The stored facts stay; nothing is rewritten for the switch.
      expect(await tester.runAsync(h.values), hasLength(6));
      expect(h.overviewModel.calls, 1);
      await tester.tapAt(const Offset(200, 40));
      await settle(tester);
      expect(find.text(s.off.title), findsOneWidget);
      expect(find.text(s.status.off), findsOneWidget);
      await close(tester);
    });
  });

  group('alle herinneringen wissen (43 G)', () {
    Future<void> openDialog(WidgetTester tester) async {
      await tester.tap(memoryAction('menu'));
      await settle(tester);
      await tester.tap(memoryAction('clear'));
      await settle(tester);
    }

    testWidgets('asks first: nothing is wiped by the menu row, and nothing after Annuleren', (tester) async {
      await open(tester);
      await openDialog(tester);

      expect(find.text(s.clearDialog.title), findsOneWidget);
      expect(find.text(s.clearDialog.body), findsOneWidget);
      expect(await tester.runAsync(h.values), hasLength(6));

      await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'cancel'));
      await settle(tester);
      expect(find.text(s.clearDialog.title), findsNothing);
      expect(await tester.runAsync(h.values), hasLength(6));
      expect(h.model.view, MemoryScreenView.overview);
      await close(tester);
    });

    testWidgets('the safe button holds the focus when the dialog opens', (tester) async {
      await open(tester);
      await openDialog(tester);

      final cancel = memoryId(AutomationIds.settingsMemoryDialogButton, 'cancel');
      final confirm = memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm');
      expect(holdsFocus(tester, cancel), isTrue);
      expect(holdsFocus(tester, confirm), isFalse);
      await close(tester);
    });

    testWidgets('Wissen removes every memory and its overview, and leaves the ages alone', (tester) async {
      h.kidsAges = const [8, 11];
      await open(tester);
      await openDialog(tester);
      await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm'));
      await settle(tester, 8);

      expect(await tester.runAsync(h.values), isEmpty);
      expect(await tester.runAsync(h.service.overview), isNull);
      expect(h.kidsAges, [8, 11]);
      expect(find.text(s.empty.title), findsOneWidget);
      expect(find.text(s.status.empty), findsOneWidget);
      await close(tester);
    });

    testWidgets('works with the memory off', (tester) async {
      h.enabledStore.on = false;
      await open(tester, overview: const []);
      expect(find.text(s.off.title), findsOneWidget);

      await openDialog(tester);
      await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm'));
      await settle(tester, 8);

      expect(await tester.runAsync(h.values), isEmpty);
      expect(h.enabledStore.on, isFalse);
      expect(h.overviewModel.calls, 0);
      await close(tester);
    });
  });

  group('states', () {
    testWidgets('off: the card with "Geheugen aanzetten", a dimmed field and no model call (43 I)', (tester) async {
      h.enabledStore.on = false;
      await open(tester, overview: [say(mockupOverviewReply())]);

      expect(h.model.view, MemoryScreenView.off);
      expect(find.text(s.off.body), findsOneWidget);
      expect(h.overviewModel.calls, 0);
      expect(tester.widget<EditableText>(input()).readOnly, isTrue);

      await tester.tap(memoryAction('turnOn'));
      await settle(tester, 8);
      expect(h.enabledStore.on, isTrue);
      expect(h.model.view, MemoryScreenView.overview);
      await close(tester);
    });

    testWidgets('empty: the card that says how to start, with the field open (43 J)', (tester) async {
      await open(tester, seed: false, overview: const []);

      expect(h.model.view, MemoryScreenView.empty);
      expect(find.text(s.empty.title), findsOneWidget);
      expect(find.text(s.empty.body), findsOneWidget);
      expect(find.text(s.status.empty), findsOneWidget);
      expect(h.overviewModel.calls, 0);
      expect(tester.widget<EditableText>(input()).readOnly, isFalse);
      await close(tester);
    });

    testWidgets('children\'s profile: the facts as a list, no overview, no follow-ups and no field', (tester) async {
      h.kids = true;
      await open(tester);

      expect(h.model.view, MemoryScreenView.kids);
      expect(find.text(s.kids.title), findsOneWidget);
      expect(find.text(s.status.kids), findsOneWidget);
      expect(find.text('Houdt niet van horror'), findsOneWidget);
      expect(find.text(s.sections.overview), findsNothing);
      expect(find.text(s.deeper), findsNothing);
      // No way to ask Big P anything here: neither the field nor its button.
      expect(memoryId(AutomationIds.settingsMemoryInput), findsNothing);
      expect(memoryAction('send'), findsNothing);
      expect(h.overviewModel.calls, 0);
      expect(h.hostModel.calls, 0);

      // Looking and wiping stay possible.
      await tester.tap(memoryAction('menu'));
      await settle(tester);
      expect(find.text(s.menu.manage), findsOneWidget);
      expect(find.text(s.menu.rewrite), findsNothing);
      await tester.tap(memoryAction('clear'));
      await settle(tester);
      await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm'));
      await settle(tester, 8);
      expect(await tester.runAsync(h.values), isEmpty);
      await close(tester);
    });

    testWidgets('unreadable facts are an error with a retry, never an empty memory', (tester) async {
      h = MemoryScreenHarness(unreadable: true);
      await open(tester, overview: [say(mockupOverviewReply())]);

      expect(h.model.view, MemoryScreenView.error);
      expect(find.text(s.error.title), findsOneWidget);
      expect(find.text(s.status.error), findsOneWidget);
      expect(find.text(s.empty.title), findsNothing);
      expect(find.text(s.status.empty), findsNothing);
      expect(memoryId(AutomationIds.settingsMemoryInput), findsNothing);
      expect(h.overviewModel.calls, 0);

      (h.service as UnreadableMemoryService).broken = false;
      await tester.tap(memoryAction('retry'));
      await settle(tester, 8);
      expect(h.model.view, MemoryScreenView.overview);
      await close(tester);
    });
  });
}
