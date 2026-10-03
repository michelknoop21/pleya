/// Big P summoned with a long Play/Pause press (mockup 38, "Oproepen vanaf
/// elk scherm"): when he may come, what he opens, and how he leaves.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_confirm_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_labels.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_widgets.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';

import 'tv_assistant_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_summon_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  const screen = AssistantScreenContext(serverId: 'zolder', libraryId: '1');
  late FakeAssistantController c;
  late StreamController<void> presses;
  late List<Map<Object?, Object?>> edits;
  late FocusNode behind;

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
    presses = StreamController<void>.broadcast();
    edits = [];
    behind = FocusNode(debugLabel: 'behind');
    messenger.setMockMethodCallHandler(channel, (call) async {
      edits.add(call.arguments as Map<Object?, Object?>);
      return <String, dynamic>{'text': 'Scan deze bibliotheek opnieuw', 'submitted': true};
    });
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
    unawaited(presses.close());
    behind.dispose();
    c.dispose();
  });

  Future<void> pumpHost(WidgetTester tester, {Widget? beside}) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    await pumpTvFrame(
      tester,
      c,
      TvAssistantSummonHost(
        longPresses: presses.stream,
        speech: SpeechSearchService(textEntry: entry),
        textEntry: entry,
        screenContext: () => screen,
        child: Stack(
          children: [
            if (beside != null) beside,
            Align(
              alignment: Alignment.topLeft,
              child: Focus(focusNode: behind, child: const SizedBox(width: 200, height: 200)),
            ),
          ],
        ),
      ),
    );
    behind.requestFocus();
    await settle(tester);
  }

  Future<void> longPress(WidgetTester tester) async {
    presses.add(null);
    await settle(tester);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  Finder bigP() => find.byType(BigPAvatar);

  /// Summoned and asked: the keyboard sent the question, Big P works.
  Future<void> summoned(WidgetTester tester) async {
    await pumpHost(tester);
    await longPress(tester);
  }

  group('when he may come', () {
    testWidgets('a long press opens the system keyboard with a send key and this screen as context', (tester) async {
      await summoned(tester);

      expect(bigP(), findsOneWidget);
      expect(edits.single['action'], 'send');
      expect(c.listenContexts.single, same(screen));
      expect(c.submitted, ['Scan deze bibliotheek opnieuw']);
    });

    testWidgets('never during playback', (tester) async {
      await pumpHost(tester);
      unawaited(
        Navigator.of(tester.element(find.byType(TvAssistantSummonHost))).push(
          MaterialPageRoute<void>(
            settings: const RouteSettings(name: kVideoPlayerRouteName),
            builder: (_) => const SizedBox(),
          ),
        ),
      );
      await settle(tester);

      await longPress(tester);

      expect(edits, isEmpty);
      expect(c.listenContexts, isEmpty);
    });

    testWidgets('never over his own full surface, which would reset its conversation', (tester) async {
      await pumpHost(
        tester,
        beside: TvAssistantScreen(textEntry: AppleTvNativeTextEntry(channel: channel)),
      );

      await longPress(tester);

      expect(edits, isEmpty);
      expect(c.listenContexts, isEmpty);
    });

    testWidgets('a surface left behind offstage does not keep him away', (tester) async {
      await pumpHost(
        tester,
        beside: TickerMode(
          enabled: false,
          child: Offstage(
            child: TvAssistantScreen(textEntry: AppleTvNativeTextEntry(channel: channel)),
          ),
        ),
      );

      await longPress(tester);

      expect(c.listenContexts.single, same(screen));
    });

    testWidgets('never while the system keyboard is up', (tester) async {
      await pumpHost(tester);
      NativeInputSession.begin();

      await longPress(tester);

      expect(edits, isEmpty);
      expect(bigP(), findsNothing);
    });

    testWidgets('never where the controller hides him', (tester) async {
      c.availability = AssistantAvailability.hidden;
      await pumpHost(tester);

      await longPress(tester);

      expect(c.refreshes, 1, reason: 'the press is the first time availability is read');
      expect(edits, isEmpty);
      expect(bigP(), findsNothing);
    });

    testWidgets('locked opens the full surface with its gate instead', (tester) async {
      c.availability = AssistantAvailability.locked;
      await pumpHost(tester);

      await longPress(tester);

      expect(find.byType(TvAssistantScreen), findsOneWidget);
      expect(edits, isEmpty);
    });
  });

  group('how he leaves', () {
    testWidgets('Menu dismisses, lets the run go and puts the remote back', (tester) async {
      await summoned(tester);
      expect(focusedLabel(), 'assistant.cancel');

      // Trapped: the remote cannot wander off to the screen behind.
      for (final key in [LogicalKeyboardKey.arrowUp, LogicalKeyboardKey.arrowLeft, LogicalKeyboardKey.arrowDown]) {
        await press(tester, key);
        expect(focusedLabel(), isNot('behind'));
      }

      await press(tester, LogicalKeyboardKey.escape);

      expect(bigP(), findsNothing);
      expect(focusedLabel(), 'behind');
      expect(c.resets, 2, reason: 'one fresh start on summon, one on leaving');
    });

    testWidgets('Menu lets the run go at once, not after the slide-out, so an unmount in between cannot keep it', (
      tester,
    ) async {
      await summoned(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(c.aborts, 1, reason: 'aborted by the dismissal itself');
      expect(c.resets, 1, reason: 'the clear-out still waits for the slide-out');

      await tester.pumpWidget(const SizedBox());
      expect(c.aborts, 1);
    });

    // Hardware, build 318: Big P left by himself while the answer was read.
    testWidgets('a good result stays until Menu', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'De scan van Films loopt.'
        ..emit();
      await tester.pump(const Duration(minutes: 5));
      await settle(tester);
      expect(bigP(), findsOneWidget);

      await press(tester, LogicalKeyboardKey.escape);
      expect(bigP(), findsNothing);
      expect(focusedLabel(), 'behind');
    });

    // Hardware, build 318: the panel showed *Mission: Impossible* with its
    // asterisks.
    test('an answer is shown without its Markdown marks', () {
      expect(
        assistantPlainText('## Gevonden\nDe *Mission: Impossible*-reeks, **Top Gun** en `Jack Reacher`. 2 * 3 = 6.'),
        'Gevonden\nDe Mission: Impossible-reeks, Top Gun en Jack Reacher. 2 * 3 = 6.',
      );
      // Not emphasis: a title, sums and a list bullet.
      expect(
        assistantPlainText('* Top Gun (1986)\n- Zie [de lijst](https://example.com/x) voor meer.'),
        '• Top Gun (1986)\n• Zie de lijst voor meer.',
      );
      for (final plain in ['Ik vond M*A*S*H (1970).', '2*3*4 = 24', 'Jaren 1986 - 2022']) {
        expect(assistantPlainText(plain), plain);
      }
      expect(
        assistantPlainText(
          '***Top Gun*** en _Rain Man_ of __Heat__, snake_case_naam, ![poster](https://example.com/p.png)',
        ),
        'Top Gun en Rain Man of Heat, snake_case_naam, poster',
      );
      // Above cards the list lines go: the cards are the list.
      expect(
        assistantWithoutList(
          'Gevonden op je server:\n1. Top Gun (1986)\n• Rain Man (1988)\nTwee staan alleen op Zolder.',
        ),
        'Gevonden op je server:\nTwee staan alleen op Zolder.',
      );
      // Only marks is no answer.
      for (final marks in ['**', '***', '# ', '``']) {
        expect(assistantPlainText(marks), isEmpty);
      }
    });

    testWidgets('an abbreviation or a list number does not become the headline', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Mr. Robot staat op Plex en op Jellyfin. Het eerste seizoen is compleet.'
        ..emit();
      await settle(tester);

      expect(find.text('Mr. Robot staat op Plex en op Jellyfin.'), findsOneWidget);
      expect(find.text('Het eerste seizoen is compleet.'), findsOneWidget);
    });

    testWidgets('a list under an intro line leaves its number in the list', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Ik heb deze films gevonden:\n1. Top Gun (1986)\n2. Rain Man (1988)'
        ..emit();
      await settle(tester);
      expect(find.text('Ik heb deze films gevonden:'), findsOneWidget);
      expect(find.text('1. Top Gun (1986)\n2. Rain Man (1988)'), findsOneWidget);

      c
        ..answer = 'Ik vond films van o.a. Tom Cruise en Brad Pitt. Meer staat op Plex.'
        ..emit();
      await settle(tester);
      expect(find.text('Ik vond films van o.a. Tom Cruise en Brad Pitt.'), findsOneWidget);
    });

    testWidgets('a short answer keeps the panel short', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'De scan van Films loopt.'
        ..emit();
      await settle(tester);
      final short = tester.getRect(find.byType(TvAssistantGlassPanel)).height;

      c
        ..answer = List.filled(40, 'Ik heb veel films met Tom Cruise gevonden.').join(' ')
        ..emit();
      await settle(tester);
      expect(short, lessThan(tester.getRect(find.byType(TvAssistantGlassPanel)).height / 2));
    });

    // Hardware, build 318: a long answer opened at its last lines, could not
    // be scrolled and left after 4 s.
    testWidgets('a long answer opens at its first line and scrolls on Up and Down', (tester) async {
      await summoned(tester);
      final answer = List.filled(40, 'Ik heb veel films met Tom Cruise gevonden.').join(' ');
      c
        ..state = AssistantSurfaceState.result
        ..answer = answer
        ..emit();
      await settle(tester);

      final panel = tester.getRect(find.byType(TvAssistantGlassPanel));
      final top = tester.getRect(find.byKey(const ValueKey('assistant.answer.body'))).top;
      expect(top, inInclusiveRange(panel.top, panel.bottom), reason: 'the first line is in the panel');
      expect(focusedLabel(), 'assistant.ask');

      // Up takes the answer; Down and Up scroll it.
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'assistant.answer');
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(
        tester.getRect(find.byKey(const ValueKey('assistant.answer.body'))).top,
        lessThan(top),
        reason: 'Down scrolls the answer',
      );
      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(tester.getRect(find.byKey(const ValueKey('assistant.answer.body'))).top, top, reason: 'Up scrolls back');
      expect(focusedLabel(), 'assistant.answer');

      // At its last line Down gives the remote back to the buttons.
      for (var i = 0; i < 60 && focusedLabel() == 'assistant.answer'; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedLabel(), 'assistant.ask');
    });

    testWidgets('a short answer takes no focus: Up from the button stays on the button', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Dat lukte niet.'
        ..emit();
      await settle(tester);

      await press(tester, LogicalKeyboardKey.arrowUp);
      expect(focusedLabel(), 'assistant.ask');
    });

    testWidgets('an error stays until Menu', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..resultIsError = true
        ..emit();
      await tester.pump(const Duration(seconds: 10));
      await settle(tester);
      expect(bigP(), findsOneWidget);
      expect(tester.widget<BigPAvatar>(bigP()).mood, BigPMood.error);

      await press(tester, LogicalKeyboardKey.escape);
      expect(bigP(), findsNothing);
    });

    testWidgets('a sensitive action raises the Pleya card; Menu cancels it and Big P stays', (tester) async {
      await summoned(tester);
      c
        ..pending = AssistantPendingAction(
          kind: AssistantActionKind.scanLibrary,
          serverId: ServerId('zolder'),
          serverName: 'Zolder',
          subject: 'Films',
          execute: ({password}) async => const {},
        )
        ..emit();
      await settle(tester);
      expect(find.byType(TvAssistantConfirmCard), findsOneWidget);
      expect(focusedLabel(), 'assistant.confirm.cancel');
      expect(tester.widget<BigPAvatar>(bigP()).mood, BigPMood.attentive);

      await press(tester, LogicalKeyboardKey.escape);

      expect(c.cancelledPending, 1);
      expect(find.byType(TvAssistantConfirmCard), findsNothing);
      expect(bigP(), findsOneWidget);
    });
  });
}
