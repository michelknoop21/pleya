/// "Nieuw gesprek" on TV (mockup 40 A): a focusable pill in the follow-up
/// row. Reached with the remote through the real TvAssistantScreen, inside
/// the title-safe band, no overflow, and a press clears the conversation.
///
/// Shots (screen, size, file) go to NEWCONV_SHOT_DIR when it is set.
library;

import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';

import '../../../test_helpers/golden.dart';
import 'tv_assistant_test_support.dart';

final _shotDir = Platform.environment['NEWCONV_SHOT_DIR'];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_new_conversation_entry');
  late FakeAssistantController c;
  final boundary = GlobalKey();

  setUpAll(() async {
    await loadAppFontsForGoldens();
    await LocaleSettings.setLocale(AppLocale.nl);
  });

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
    // The same three follow-ups on every run, so the wrap is the same.
    BigPSuggestions.install(c, BigPSuggestions(random: Random(1)));
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    c.dispose();
  });

  Finder pill() => find.byWidgetPredicate(
    (w) =>
        w is BigPButton && w.automationId == AutomationIds.assistantButton && w.automationInstance == 'newConversation',
  );

  bool onPill() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BigPButton>()?.automationInstance ==
      'newConversation';

  Future<void> pumpAnswer(WidgetTester tester, {Size? logical, double dpr = 1}) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      RepaintBoundary(
        key: boundary,
        child: TvAssistantScreen(
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
        ),
      ),
    );
    if (logical != null) {
      tester.view.physicalSize = logical * dpr;
      tester.view.devicePixelRatio = dpr;
    }
    c
      ..prompt = 'Hoeveel films staan er?'
      ..answer = 'Op Zolder staan 1.284 films.'
      ..state = AssistantSurfaceState.result
      ..emit();
    await settle(tester);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  Future<void> shot(WidgetTester tester, String name) async {
    final dir = _shotDir;
    if (dir == null) return;
    await tester.runAsync(() async {
      final ro = boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await ro.toImage(pixelRatio: 1);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      File('$dir/$name.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
    });
  }

  testWidgets('not in the greeting, after an answer in the button row', (tester) async {
    await pumpAnswer(tester);
    expect(pill(), findsOneWidget);
    c
      ..state = AssistantSurfaceState.idle
      ..prompt = null
      ..answer = ''
      ..emit();
    await settle(tester);
    expect(pill(), findsNothing);
  });

  testWidgets('the remote reaches it from the field with Up and back with Down, then Select starts over', (
    tester,
  ) async {
    await pumpAnswer(tester);
    expect(focusedLabel(), 'assistant.ask');

    // Beside "Vraag Big P", in the button row: one Right from the field.
    Future<int> walkToPill() async {
      await press(tester, LogicalKeyboardKey.arrowRight);
      return 1;
    }

    final up = await walkToPill();
    expect(onPill(), isTrue, reason: 'reached with the D-pad within $up steps');
    await shot(tester, 'new-conversation-tv-1920x1080-1-focus');

    // And the way back to the field.
    await press(tester, LogicalKeyboardKey.arrowLeft);
    expect(onPill(), isFalse);
    expect(focusedLabel(), 'assistant.ask');

    await walkToPill();
    expect(onPill(), isTrue);
    await press(tester, LogicalKeyboardKey.select);
    expect(c.newConversations, 1);
    expect(c.submitted, isEmpty);
    expect(c.state, AssistantSurfaceState.idle);
    expect(pill(), findsNothing);
    expect(focusedLabel(), 'assistant.ask', reason: 'the remote never loses its place');
    await shot(tester, 'new-conversation-tv-1920x1080-2-greeting');
  });

  for (final (name, logical, dpr) in [
    ('1920x1080 at DPR 1', const Size(1920, 1080), 1.0),
    ('1920x1080 logical at DPR 2 (4K)', const Size(1920, 1080), 2.0),
    ('960x540 logical at DPR 2 (1080p panel)', const Size(960, 540), 2.0),
  ]) {
    testWidgets('inside the title-safe band, whole and without overflow: $name', (tester) async {
      await pumpAnswer(tester, logical: logical, dpr: dpr);
      await settle(tester);
      expect(tester.takeException(), isNull);
      final rect = tester.getRect(pill());
      final safe = Rect.fromLTRB(
        logical.width * 0.05,
        logical.height * 0.05,
        logical.width * 0.95,
        logical.height * 0.95,
      );
      expect(safe.contains(rect.topLeft) && safe.contains(rect.bottomRight), isTrue, reason: '$rect in $safe');
      for (final chip
          in find
              .byWidgetPredicate((w) => w is BigPChip && w.automationId == AutomationIds.assistantFollowUp)
              .evaluate()) {
        expect(rect.overlaps(tester.getRect(find.byWidget(chip.widget))), isFalse);
      }
      final text = find.descendant(of: pill(), matching: find.byType(RichText)).evaluate();
      for (final e in text) {
        final ro = e.renderObject;
        if (ro is RenderParagraph) expect(ro.didExceedMaxLines, isFalse);
      }
    });
  }
}
