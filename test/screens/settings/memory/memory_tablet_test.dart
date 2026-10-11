// Geheugen on an iPad (43 L): two columns, the management controls beside
// the text instead of behind a menu button.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_layouts.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';

import 'memory_finders.dart';
import 'memory_screen_support.dart';

/// Read per use: the locale is set inside each test.
TranslationsAssistantMemoryScreenEn get s => t.assistant.memory.screen;

void main() {
  late MemoryScreenHarness h;

  Future<void> open(WidgetTester tester, {Size size = tabletSize}) async {
    await tester.runAsync(useDutch);
    await tester.runAsync(h.seed);
    h.overviewModel = ScriptedModel([say(mockupOverviewReply()), say(mockupOverviewReply())]);
    await pumpMemoryApp(tester, AssistantMemoryScreen(model: h.model), size: size);
  }

  Future<void> close(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.runAsync(h.dispose);
  }

  setUp(() => h = MemoryScreenHarness());

  testWidgets('the overview and the field on the left, the four controls and Duik dieper on the right', (tester) async {
    await open(tester);

    expect(find.byType(MemoryTabletLayout), findsOneWidget);
    expect(memoryAction('menu'), findsNothing);
    final overview = tester.getRect(find.text(s.sections.overview));
    final input = tester.getRect(memoryId(AutomationIds.settingsMemoryInput));
    for (final action in ['manage', 'use', 'rewrite', 'clear']) {
      final rect = tester.getRect(memoryAction(action));
      expect(rect.left, greaterThan(overview.right), reason: action);
      expect(rect.left, greaterThan(input.right), reason: action);
    }
    expect(tester.getRect(memoryAction('use')).top, greaterThan(tester.getRect(memoryAction('manage')).bottom));
    expect(tester.getRect(memoryAction('rewrite')).top, greaterThan(tester.getRect(memoryAction('use')).bottom));
    expect(tester.getRect(memoryAction('clear')).top, greaterThan(tester.getRect(memoryAction('rewrite')).bottom));
    // The follow-ups stand in the right column, under the controls.
    final followUp = tester.getRect(memoryId(AutomationIds.settingsMemoryFollowUp, '0'));
    expect(followUp.left, greaterThan(overview.right));
    expect(followUp.top, greaterThan(tester.getRect(memoryAction('clear')).bottom));
    expect(find.text('${s.footer(n: 6)} ${s.footerManageList}'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('the controls work in place: the list opens, wiping asks first', (tester) async {
    await open(tester);
    await tester.tap(memoryAction('clear'));
    await settle(tester);
    expect(find.text(s.clearDialog.title), findsOneWidget);
    await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'cancel'));
    await settle(tester);
    expect(await tester.runAsync(h.values), hasLength(6));

    await tester.tap(memoryAction('manage'));
    await settle(tester);
    expect(find.byType(MemoryListScreen), findsOneWidget);
    await close(tester);
  });

  testWidgets('an iPad held upright keeps both columns without overflow', (tester) async {
    await open(tester, size: const Size(820, 1180));

    expect(find.byType(MemoryTabletLayout), findsOneWidget);
    expect(tester.takeException(), isNull);
    expect(tester.getRect(memoryAction('manage')).right, lessThanOrEqualTo(820));
    await close(tester);
  });

  testWidgets('below the tablet width the phone layout with its menu button', (tester) async {
    await open(tester, size: const Size(699, 900));

    expect(find.byType(MemoryPhoneLayout), findsOneWidget);
    expect(memoryAction('menu'), findsOneWidget);
    await close(tester);
  });
}
