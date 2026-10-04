/// T8 on TV: the ages card rises over Big P's answer, opens on the first
/// age, is walked with the D-pad, and Menu closes it as it closes the
/// confirmation card. The age notice stays in view above title cards.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_kids_ages_card.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';

import '../../big_p/big_p_mobile_fixtures.dart';
import 'tv_assistant_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_kids_entry');
  late FakeAssistantController c;

  setUpAll(() async => LocaleSettings.setLocale(AppLocale.nl));

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    NativeInputSession.debugReset();
    c.dispose();
  });

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  /// The surface, then the answer that asks for the ages.
  Future<void> raise(WidgetTester tester) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantScreen(
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
      ),
    );
    answerKidsAges(c);
    c.emit();
    await settle(tester);
  }

  testWidgets('opens on the first age, Big P attentive', (tester) async {
    await raise(tester);
    expect(find.byType(BigPKidsAgesCard), findsOneWidget);
    expect(find.text(t.assistant.kids.title), findsOneWidget);
    expect(focusedLabel(), 'assistant.kids.first');
    expect(tester.widget<BigPAvatar>(find.byType(BigPAvatar)).mood, BigPMood.attentive);
  });

  testWidgets('D-pad: two ages chosen, then down to Bewaar, which saves them', (tester) async {
    await raise(tester);
    await press(tester, LogicalKeyboardKey.arrowRight); // 1
    await press(tester, LogicalKeyboardKey.arrowRight); // 2
    await press(tester, LogicalKeyboardKey.select);
    await press(tester, LogicalKeyboardKey.arrowRight); // 3
    await press(tester, LogicalKeyboardKey.arrowRight); // 4
    await press(tester, LogicalKeyboardKey.arrowRight); // 5
    await press(tester, LogicalKeyboardKey.select);

    // Down out of the chips until the focus is on Bewaar.
    for (var i = 0; i < 4 && !_onSave(); i++) {
      await press(tester, LogicalKeyboardKey.arrowDown);
    }
    if (!_onSave()) await press(tester, LogicalKeyboardKey.arrowRight);
    expect(_onSave(), isTrue, reason: 'Bewaar is reachable with the D-pad');
    await press(tester, LogicalKeyboardKey.select);

    expect(c.savedAges, [
      [2, 5],
    ]);
    expect(find.byType(BigPKidsAgesCard), findsNothing);
  });

  testWidgets('Bewaar does nothing while no age is chosen', (tester) async {
    await raise(tester);
    await tester.tap(find.text(t.assistant.kids.save));
    await settle(tester);
    expect(c.savedAges, isEmpty);
    expect(find.byType(BigPKidsAgesCard), findsOneWidget);
  });

  testWidgets('no way around the filter: Bewaar is the only button, no Zonder filter', (tester) async {
    await raise(tester);
    final card = find.byType(BigPKidsAgesCard);
    expect(find.descendant(of: card, matching: find.byType(BigPButton)), findsOneWidget);
    expect(find.text('Zonder filter'), findsNothing);
  });

  testWidgets('Menu closes the card; the answer stays and the card does not come back', (tester) async {
    await raise(tester);
    await press(tester, LogicalKeyboardKey.escape);

    expect(find.byType(BigPKidsAgesCard), findsNothing);
    expect(c.kidsDismissals, 1);
    expect(c.savedAges, isEmpty);
    expect(find.textContaining('Daarvoor moet Pleya'), findsOneWidget);
    c.emit();
    await settle(tester);
    expect(find.byType(BigPKidsAgesCard), findsNothing);
  });

  testWidgets('the summoned Big P raises the same card', (tester) async {
    final presses = StreamController<void>.broadcast();
    addTearDown(presses.close);
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantSummonHost(
        longPresses: presses.stream,
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
        screenContext: () => null,
        child: const SizedBox.expand(),
      ),
    );
    presses.add(null);
    await settle(tester);
    answerKidsAges(c);
    c.emit();
    await settle(tester);
    expect(find.byType(BigPKidsAgesCard), findsOneWidget);
    expect(focusedLabel(), 'assistant.kids.first');
  });

  testWidgets('above title cards the age notice stays in view under the lead', (tester) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantScreen(
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
      ),
    );
    answerFactsTitles(c);
    // Two tasks: the notice belongs to the first, so the joined answer does
    // not end with it.
    c
      ..answer = '${c.answer}\n\n${t.assistant.kids.filterNotice}\nDe scan is gestart.'
      ..ageFilterNotice = true
      ..emit();
    await settle(tester);
    expect(find.text(t.assistant.kids.filterNotice), findsOneWidget);
  });
}

bool _onSave() {
  final focused = FocusManager.instance.primaryFocus?.context;
  if (focused == null) return false;
  var found = false;
  // The save button's text sits under the focused wrapper.
  void walk(Element e) {
    if (found) return;
    final w = e.widget;
    if (w is Text && w.data == t.assistant.kids.save) found = true;
    e.visitChildren(walk);
  }

  (focused as Element).visitChildren(walk);
  return found;
}
