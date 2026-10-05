/// Big P summoned with a long Play/Pause press (mockup 38, "Oproepen vanaf
/// elk scherm"): when he may come, what he opens, and how he leaves.
library;

import 'dart:io';
import 'dart:ui' as ui;
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_confirm_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_labels.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/utils/video_player_navigation.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';
import 'package:pleya/widgets/big_p/big_p_balloon.dart';

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

    testWidgets('needsSetup reads again on the press, so a keychain that recovered summons him', (tester) async {
      c
        ..availability = AssistantAvailability.needsSetup
        ..refreshTo = AssistantAvailability.ready;
      await pumpHost(tester);

      await longPress(tester);

      expect(c.refreshes, 1);
      expect(find.byType(TvAssistantScreen), findsNothing);
      expect(bigP(), findsOneWidget);
      expect(c.listenContexts.single, same(screen));
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
      expect(c.conversationClears, 2, reason: 'a new conversation on summon, forgotten on leaving');
    });

    testWidgets('Menu lets the run go at once, not after the slide-out, so an unmount in between cannot keep it', (
      tester,
    ) async {
      await summoned(tester);
      await tester.sendKeyEvent(LogicalKeyboardKey.escape);
      expect(c.aborts, 1, reason: 'aborted by the dismissal itself');
      expect(c.resets, 1, reason: 'the clear-out still waits for the slide-out');
      expect(c.conversationClears, 1, reason: 'memory goes with the clear-out');

      await tester.pumpWidget(const SizedBox());
      expect(c.aborts, 1);
    });

    // Hardware, build 318: Big P left by himself while the answer was read.
    testWidgets('a good result stays with its three follow-ups until Menu', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'De scan van Films loopt.'
        ..emit();
      await tester.pump(const Duration(minutes: 5));
      await settle(tester);
      expect(bigP(), findsOneWidget);
      expect(find.byType(BigPChip), findsNWidgets(3));

      await press(tester, LogicalKeyboardKey.escape);
      expect(bigP(), findsNothing);
      expect(focusedLabel(), 'behind');
    });

    // Hardware, build 318: the panel showed *Mission: Impossible* with its
    // asterisks.
    test('an answer is shown without its Markdown marks', () {
      expect(
        assistantPlainAnswer('## Gevonden\nDe *Mission: Impossible*-reeks, **Top Gun** en `Jack Reacher`. 2 * 3 = 6.'),
        'Gevonden\nDe Mission: Impossible-reeks, Top Gun en Jack Reacher. 2 * 3 = 6.',
      );
      // Not emphasis: a title, sums and a list bullet.
      expect(
        assistantPlainAnswer('* Top Gun (1986)\n- Zie [de lijst](https://example.com/x) voor meer.'),
        '• Top Gun (1986)\n• Zie de lijst voor meer.',
      );
      for (final plain in ['Ik vond M*A*S*H (1970).', '2*3*4 = 24', 'Jaren 1986 - 2022']) {
        expect(assistantPlainAnswer(plain), plain);
      }
      expect(
        assistantPlainAnswer(
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
      expect(assistantWithoutList('1917. Oorlogsfilm.'), '1917. Oorlogsfilm.');
      // Only marks is no answer.
      for (final marks in ['**', '***', '# ', '``']) {
        expect(assistantPlainAnswer(marks), isEmpty);
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

      // A short intro line is still the whole lead.
      c
        ..answer = 'Hier zijn ze:\n1. Top Gun (1986)\n2. Rain Man (1988)'
        ..emit();
      await settle(tester);
      expect(find.text('Hier zijn ze:'), findsOneWidget);
      expect(find.text('1. Top Gun (1986)\n2. Rain Man (1988)'), findsOneWidget);

      // A bare list has no lead.
      c
        ..answer = '• Heat (1995)\n• Ronin (1998)'
        ..emit();
      await settle(tester);
      expect(find.text('• Heat (1995)\n• Ronin (1998)'), findsOneWidget);

      // A sentence may end in a year.
      c
        ..answer = 'Top Gun kwam uit in 1986. Het vervolg kwam pas in 2022.'
        ..emit();
      await settle(tester);
      expect(find.text('Top Gun kwam uit in 1986.'), findsOneWidget);

      c
        ..answer = 'Ik vond films van o.a. Tom Cruise en Brad Pitt. Meer staat op Plex.'
        ..emit();
      await settle(tester);
      expect(find.text('Ik vond films van o.a. Tom Cruise en Brad Pitt.'), findsOneWidget);
    });

    testWidgets('one long sentence is running text, not a headline', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Dat lukte niet.'
        ..emit();
      await settle(tester);
      final headline = tester.widget<Text>(find.byKey(const ValueKey('assistant.answer.body'))).style!.fontSize!;

      c
        ..answer = List.filled(12, 'alle films van de reeks staan op je server').join(', ')
        ..emit();
      await settle(tester);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('assistant.answer.body'))).style!.fontSize,
        lessThan(headline),
      );
    });

    // A ranking shows a few of its titles and none of them can be chosen
    // here: the answer keeps its list, the follow-ups stand in view above
    // the buttons, and the list scrolls on Up and Down by itself.
    testWidgets('a result without choices keeps the answer list, shows the follow-ups and can be scrolled', (
      tester,
    ) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Meest bekeken deze week:\n1. The Block\n2. House\n3. Heat'
        ..displays = [
          AssistantWatchStats(
            serverName: 'Pleya',
            days: 7,
            users: const [(name: 'Gideuh', plays: 36, seconds: 0), (name: 'Jan', plays: 6, seconds: 0)],
            titles: [
              for (final title in ['The Block', 'House', 'Heat', 'Ronin', 'Sintel'])
                (title: title, plays: 9, viewers: const ['Jan'], show: false, target: null),
            ],
          ),
        ]
        ..emit();
      await settle(tester);

      expect(find.textContaining('1. The Block'), findsOneWidget, reason: 'the cards do not replace this list');
      final panel = tester.getRect(find.byType(BigPBalloon));
      for (final chip in tester.widgetList(find.byType(BigPChip))) {
        final rect = tester.getRect(find.byWidget(chip));
        expect(rect.bottom, lessThanOrEqualTo(panel.bottom), reason: 'follow-up in view');
        expect(rect.top, greaterThanOrEqualTo(panel.top));
      }

      // Up from Ask: the follow-ups, then the list itself, which scrolls.
      for (var i = 0; i < 6 && focusedLabel() != 'assistant.results'; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
      expect(focusedLabel(), 'assistant.results');
      final top = tester.getRect(find.text('The Block')).top;
      await press(tester, LogicalKeyboardKey.arrowDown);
      expect(tester.getRect(find.text('The Block')).top, lessThan(top), reason: 'Down scrolls the list');
      for (var i = 0; i < 20 && focusedLabel() == 'assistant.results'; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedLabel(), isNot('assistant.results'), reason: 'at its end the key moves the focus on');
    });

    testWidgets('Vraag Big P, Nieuw and Klaar stay on one row in the 760 pt panel, short and long answer', (
      tester,
    ) async {
      await summoned(tester);
      for (final (name, answer) in [
        ('short', 'De scan van Films loopt.'),
        ('long', List.filled(40, 'Ik heb veel films met Tom Cruise gevonden.').join(' ')),
      ]) {
        c
          ..state = AssistantSurfaceState.result
          ..prompt = 'Hoeveel films staan er?'
          ..answer = answer
          ..emit();
        await settle(tester);
        final ask = tester.getRect(find.byWidgetPredicate((w) => w is BigPButton && w.automationInstance == 'ask'));
        final fresh = tester.getRect(
          find.byWidgetPredicate((w) => w is BigPButton && w.automationInstance == 'newConversation'),
        );
        final done = tester.getRect(find.byWidgetPredicate((w) => w is BigPButton && w.automationInstance == 'done'));
        expect(fresh.center.dy, closeTo(ask.center.dy, 1), reason: '$name: Nieuw on the row of Vraag Big P');
        expect(done.center.dy, closeTo(ask.center.dy, 1), reason: '$name: Klaar on the row of Vraag Big P');
        expect(ask.right, lessThan(fresh.left));
        expect(fresh.right, lessThan(done.left));
        final balloon = tester.getRect(find.byType(BigPBalloon));
        expect(done.right, lessThanOrEqualTo(balloon.right));
        final dir = Platform.environment['NEWCONV_SHOT_DIR'];
        if (dir != null) {
          await tester.runAsync(() async {
            final ro = tester.renderObject<RenderRepaintBoundary>(find.byType(RepaintBoundary).first);
            final image = await ro.toImage();
            final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
            File('$dir/new-conversation-tv-summon-760-$name.png')
              ..createSync(recursive: true)
              ..writeAsBytesSync(bytes!.buffer.asUint8List());
          });
        }
      }
    });

    testWidgets('a short answer keeps the panel short', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'De scan van Films loopt.'
        ..emit();
      await settle(tester);
      final short = tester.getRect(find.byType(BigPBalloon)).height;

      c
        ..answer = List.filled(40, 'Ik heb veel films met Tom Cruise gevonden.').join(' ')
        ..emit();
      await settle(tester);
      // The three follow-ups stand under both, each up to two lines.
      expect(short, lessThan(tester.getRect(find.byType(BigPBalloon)).height * 0.75));
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

      final panel = tester.getRect(find.byType(BigPBalloon));
      final top = tester.getRect(find.byKey(const ValueKey('assistant.answer.body'))).top;
      expect(top, inInclusiveRange(panel.top, panel.bottom), reason: 'the first line is in the panel');
      expect(focusedLabel(), 'assistant.ask');

      // Up, past the follow-ups, takes the answer; Down and Up scroll it.
      for (var i = 0; i < 4 && focusedLabel() != 'assistant.answer'; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
      }
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

      // At its last line Down gives the remote back to what stands under it.
      for (var i = 0; i < 60 && focusedLabel() == 'assistant.answer'; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedLabel(), isNot('assistant.answer'));
      for (var i = 0; i < 4 && focusedLabel() != 'assistant.ask'; i++) {
        await press(tester, LogicalKeyboardKey.arrowDown);
      }
      expect(focusedLabel(), 'assistant.ask');
    });

    testWidgets('a short answer takes no focus: Up stops at the follow-ups', (tester) async {
      await summoned(tester);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Dat lukte niet.'
        ..emit();
      await settle(tester);

      for (var i = 0; i < 4; i++) {
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), isNot('assistant.answer'));
      }
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
      expect(find.byType(BigPConfirmCard), findsOneWidget);
      expect(focusedLabel(), 'assistant.confirm.cancel');
      expect(tester.widget<BigPAvatar>(bigP()).mood, BigPMood.attentive);

      await press(tester, LogicalKeyboardKey.escape);

      expect(c.cancelledPending, 1);
      expect(find.byType(BigPConfirmCard), findsNothing);
      expect(bigP(), findsOneWidget);
    });
  });
}
