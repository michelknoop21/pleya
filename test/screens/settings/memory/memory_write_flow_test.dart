// What a write does to the screens around it: wiping while a card waits,
// saving while Big P still writes the overview, a refused write, and the
// layouts that have to hold with a keyboard, a large text and the light
// theme.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_memory.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/settings/memory/memory_fact_sheet.dart';
import 'package:pleya/screens/settings/memory/memory_list_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen.dart';
import 'package:pleya/screens/settings/memory/memory_screen_model.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_memory_card.dart';

import '../../../test_helpers/golden.dart';
import 'memory_finders.dart';
import 'memory_screen_support.dart';

/// Read per use: the locale is set inside each test.
TranslationsAssistantMemoryScreenEn get s => t.assistant.memory.screen;

void main() {
  late MemoryScreenHarness h;

  Future<void> open(
    WidgetTester tester, {
    bool list = false,
    Size size = phoneSize,
    double textScale = 1,
    bool light = false,
  }) async {
    await tester.runAsync(useDutch);
    await tester.runAsync(h.seed);
    if (h.overviewModel.calls == 0 && h.overviewModel is! HeldModel) {
      h.overviewModel = ScriptedModel([for (var i = 0; i < 6; i++) say(mockupOverviewReply())]);
    }
    await pumpMemoryApp(
      tester,
      list ? MemoryListScreen(model: h.model) : AssistantMemoryScreen(model: h.model),
      size: size,
      textScale: textScale,
      light: light,
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

  Finder input() =>
      find.descendant(of: memoryId(AutomationIds.settingsMemoryInput), matching: find.byType(EditableText));
  Finder fact(int i) => memoryId(AutomationIds.settingsMemoryFact, '$i');
  Finder sheetButton(String id) => memoryId(AutomationIds.settingsMemorySheetButton, id);
  Finder dialogButton(String id) => memoryId(AutomationIds.settingsMemoryDialogButton, id);
  Finder sheetField() =>
      find.descendant(of: memoryId(AutomationIds.settingsMemorySheetField), matching: find.byType(EditableText));

  /// Types a sentence that contradicts the Friday memory: the card "Vervangen?".
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
    await tester.enterText(input(), 'We kijken tegenwoordig op zaterdag met het gezin');
    await tester.pump();
    await tester.tap(memoryAction('send'));
    await settle(tester, 10);
  }

  Future<void> openAdd(WidgetTester tester) async {
    await tester.dragUntilVisible(memoryAction('add'), find.byType(ListView).first, const Offset(0, -120));
    await tapOn(tester, memoryAction('add'));
    await settle(tester);
  }

  // The app's own fonts: whether a label fits its button is measured, and
  // the test font is about twice as wide.
  setUpAll(loadAppFontsForGoldens);

  setUp(() => h = MemoryScreenHarness());

  testWidgets('wiping everything while a card waits takes the card along and opens the field', (tester) async {
    await open(tester);
    await askReplace(tester);
    expect(find.byType(BigPMemoryCard), findsOneWidget);
    expect(tester.widget<EditableText>(input()).readOnly, isTrue);

    await tester.tap(memoryAction('menu'));
    await settle(tester);
    await tester.tap(memoryAction('clear'));
    await settle(tester);
    await tester.tap(memoryId(AutomationIds.settingsMemoryDialogButton, 'confirm'));
    await settle(tester, 8);

    expect(h.model.view, MemoryScreenView.empty);
    // The fact the card pointed at is gone: no card, no waiting, a field to type in.
    expect(h.host.proposal, isNull);
    expect(h.model.status, MemoryScreenStatus.empty);
    expect(find.byType(BigPMemoryCard), findsNothing);
    expect(tester.widget<EditableText>(input()).readOnly, isFalse);
    await close(tester);
  });

  testWidgets('saving closes the sheet at once; the overview is written behind the list', (tester) async {
    // The overview of the opening is written; the one after the change hangs.
    final slow = HeldModel([for (var i = 0; i < 4; i++) say(mockupOverviewReply())], free: 1);
    h.overviewModel = slow;
    await open(tester, list: true);
    await openAdd(tester);
    await tester.enterText(sheetField(), 'Kijkt graag westerns');
    await tester.pump();
    await tapOn(tester, sheetButton('save'));
    await settle(tester, 8);

    // The model has not answered: the sheet is gone and the list shows the fact.
    expect(slow.release.isCompleted, isFalse);
    expect(slow.started, 2);
    expect(find.byType(MemoryFactSheet), findsNothing);
    expect(find.text('Kijkt graag westerns'), findsOneWidget);
    expect(h.model.count, 7);
    expect(h.model.view, MemoryScreenView.writing);

    slow.release.complete();
    await settle(tester, 8);
    expect(h.model.view, MemoryScreenView.overview);
    await close(tester);
  });

  testWidgets('removing closes the sheet at once as well', (tester) async {
    // The overview of the opening is written; the one after the change hangs.
    final slow = HeldModel([for (var i = 0; i < 4; i++) say(mockupOverviewReply())], free: 1);
    h.overviewModel = slow;
    await open(tester, list: true);
    await tapOn(tester, fact(0));
    await settle(tester);
    await tapOn(tester, sheetButton('delete'));
    await settle(tester);
    await tester.tap(dialogButton('confirm'));
    await settle(tester, 8);

    expect(slow.release.isCompleted, isFalse);
    expect(find.byType(MemoryFactSheet), findsNothing);
    expect(h.model.count, 5);
    slow.release.complete();
    await settle(tester, 8);
    await close(tester);
  });

  testWidgets('a write that finds the memory gone reads the list again', (tester) async {
    await open(tester, list: true);
    expect(h.model.count, 6);
    // Wiped behind the back of this screen, as a second memory screen does.
    await tester.runAsync(h.service.clearAll);
    final stale = h.model.facts!.first;

    final result = await tester.runAsync(() => h.model.delete(stale));
    await settle(tester);
    expect(result!.code, MemoryCode.notFound);
    expect(h.model.count, 0);
    expect(fact(0), findsNothing);
    await close(tester);
  });

  testWidgets('another profile active: no write goes through and no ages are shown', (tester) async {
    h.kidsAges = const [8, 11];
    await open(tester, list: true);
    expect(h.model.kidsAges, [8, 11]);
    final first = h.model.facts!.first;

    h.active = 'profile-b';
    final update = await tester.runAsync(() => h.model.update(first, value: 'Iets anders', category: first.category));
    final delete = await tester.runAsync(() => h.model.delete(first));
    final clear = await tester.runAsync(h.model.clearAll);
    expect([update!.code, delete!.code, clear!.code], everyElement(MemoryCode.profileGone));
    expect(await tester.runAsync(h.values), hasLength(6));

    // The ages belong to the profile that is active now, not to this memory.
    await tester.runAsync(h.model.load);
    await settle(tester);
    expect(h.model.kidsAges, isEmpty);
    await close(tester);
  });

  testWidgets('iPhone SE, keyboard open, large text and a long answer: the page does not overflow', (tester) async {
    await open(tester, size: phoneSeSize, textScale: 2);
    h.hostModel = ScriptedModel([
      say(List.filled(6, 'Je kijkt graag naar Scandinavische misdaadseries en documentaires.').join(' ')),
    ]);
    await tester.enterText(input(), 'Vat samen wat je over mijn smaak weet');
    await tester.pump();
    await tester.tap(memoryAction('send'));
    await settle(tester, 10);
    tester.view.viewInsets = const FakeViewPadding(bottom: 260 * 2);
    addTearDown(tester.view.resetViewInsets);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('iPhone SE with the keyboard open: Opslaan and Annuleren stand above the keyboard', (tester) async {
    const keyboard = 260.0;
    await open(tester, list: true, size: phoneSeSize);
    await openAdd(tester);
    tester.view.viewInsets = const FakeViewPadding(bottom: keyboard * 2);
    addTearDown(tester.view.resetViewInsets);
    await settle(tester);
    await tester.enterText(sheetField(), 'Kijkt graag westerns');
    await settle(tester);

    expect(tester.takeException(), isNull);
    final edge = phoneSeSize.height - keyboard;
    for (final id in ['cancel', 'save']) {
      final rect = tester.getRect(sheetButton(id));
      expect(rect.bottom, lessThanOrEqualTo(edge), reason: id);
      expect(rect.top, greaterThan(0), reason: id);
    }
    // And they work from there.
    await tester.tap(sheetButton('save'));
    await settle(tester, 8);
    expect(await tester.runAsync(h.values), contains('Kijkt graag westerns'));
    await close(tester);
  });

  testWidgets('text at 2.0: the buttons of the dialog stand under each other, each label on one line', (tester) async {
    await open(tester, textScale: 2);
    await tester.tap(memoryAction('menu'));
    await settle(tester);
    await tapOn(tester, memoryAction('clear'));
    await settle(tester);

    final cancel = tester.getRect(dialogButton('cancel'));
    final confirm = tester.getRect(dialogButton('confirm'));
    expect(confirm.top, greaterThanOrEqualTo(cancel.bottom - 1), reason: 'Annuleren stands above the destructive one');
    for (final label in [t.common.cancel, s.clearDialog.confirm]) {
      final text = find.descendant(of: find.byType(Dialog), matching: find.text(label));
      final paragraph = tester.renderObject<RenderParagraph>(text);
      final lines = paragraph.getBoxesForSelection(TextSelection(baseOffset: 0, extentOffset: label.length));
      expect(lines.map((box) => box.top.round()).toSet(), hasLength(1), reason: '"$label" on one line');
    }
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('text at 2.0: the card "Vervangen?" shows the whole new value, with both buttons on screen', (
    tester,
  ) async {
    await open(tester, textScale: 2);
    await askReplace(tester);

    final card = find.byType(BigPMemoryCard);
    final fresh = tester.getRect(
      find.descendant(of: card, matching: find.text('Kijkt op zaterdagavond met het gezin')),
    );
    final rows = tester.getRect(find.descendant(of: card, matching: find.byType(Scrollable)).first);
    expect(fresh.top, greaterThanOrEqualTo(rows.top), reason: 'the new value is not cut off above');
    expect(fresh.bottom, lessThanOrEqualTo(rows.bottom), reason: 'the new value is not cut off below');
    for (final id in ['accept', 'decline']) {
      final button = tester.getRect(memoryId(AutomationIds.assistantMemoryButton, id));
      expect(button.top, greaterThan(0), reason: id);
      expect(button.bottom, lessThanOrEqualTo(tester.getRect(input()).top), reason: '$id above the field');
    }
    expect(tester.getRect(input()).bottom, lessThanOrEqualTo(phoneSize.height));
    expect(tester.takeException(), isNull);
    await close(tester);
  });

  testWidgets('light theme: the button "Vervangen" and the box of the card stand out from the card', (tester) async {
    await open(tester, light: true);
    await askReplace(tester);
    final card = tester.widget<BigPMemoryCard>(find.byType(BigPMemoryCard));
    expect(card.themed, isTrue);

    final tk = tokens(tester.element(find.byType(BigPMemoryCard)));
    final surface = tk.surfaceElevated;
    double contrast(Color fill) {
      final a = Color.alphaBlend(fill, surface).computeLuminance();
      final b = surface.computeLuminance();
      return (a > b ? a + 0.05 : b + 0.05) / (a > b ? b + 0.05 : a + 0.05);
    }

    // The innermost filled box under the button is the button itself.
    final fill = find
        .descendant(
          of: memoryId(AutomationIds.assistantMemoryButton, 'accept'),
          matching: find.byType(AnimatedContainer),
        )
        .evaluate()
        .map((e) => (e.widget as AnimatedContainer).decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null)
        .last
        .color!;
    expect(contrast(fill), greaterThan(1.25), reason: 'the resting button against the card');
    final box = find
        .descendant(of: find.byType(BigPMemoryCard), matching: find.byType(DecoratedBox))
        .evaluate()
        .map((e) => (e.widget as DecoratedBox).decoration)
        .whereType<BoxDecoration>()
        .where((d) => d.color != null && d.borderRadius != null)
        .first;
    expect(contrast(box.color!), greaterThan(1.1), reason: 'the box "Verdwijnt / Nieuw" against the card');
    await close(tester);
  });

  testWidgets('a tablet just above the tablet width keeps a field wide enough to type in', (tester) async {
    await open(tester, size: const Size(744, 1133));
    expect(tester.getSize(memoryId(AutomationIds.settingsMemoryInput)).width, greaterThan(260));
    expect(tester.takeException(), isNull);
    await close(tester);
  });
}
