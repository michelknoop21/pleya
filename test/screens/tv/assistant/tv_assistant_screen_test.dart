/// Big P's TV surface (mockup 38, DEC-142) against a hand-driven controller:
/// the four stands, the gates, the native text entry with a send key, the
/// option cards and the Pleya confirmation card.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/navigation/tv/tv_nested_surface.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_confirm_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_match_card.dart';
import 'package:pleya/screens/settings/assistant_settings_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_suggestions.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/big_p/big_p_avatar.dart';

import 'tv_assistant_test_support.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeAssistantController c;
  late List<Map<Object?, Object?>> edits;

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
    edits = [];
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
    c.dispose();
  });

  /// The native keyboard answers [text], submitted or not.
  void keyboardAnswers(String text, {bool submitted = true}) {
    messenger.setMockMethodCallHandler(channel, (call) async {
      edits.add(call.arguments as Map<Object?, Object?>);
      return <String, dynamic>{'text': text, 'submitted': submitted};
    });
  }

  Future<void> pumpSurface(WidgetTester tester, {void Function()? onDismiss}) async {
    final entry = AppleTvNativeTextEntry(channel: channel);
    Widget surface = TvAssistantScreen(
      speech: SpeechSearchService(textEntry: entry),
      textEntry: entry,
    );
    if (onDismiss != null) {
      surface = TvNestedRouteScope(dismiss: ([_]) => onDismiss(), markResult: (_) {}, child: surface);
    }
    await pumpTvFrame(tester, c, surface);
  }

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  BigPAvatar avatar(WidgetTester tester) => tester.widget<BigPAvatar>(find.byType(BigPAvatar));

  testWidgets('leaving the surface lets a running ask go, as the summoned panel does', (tester) async {
    await pumpSurface(tester);
    final before = c.aborts;
    await tester.pumpWidget(const SizedBox());

    expect(c.aborts, before + 1);
  });

  testWidgets('technical entry failure stays visible and retry sends exactly one question', (tester) async {
    var attempts = 0;
    messenger.setMockMethodCallHandler(channel, (call) async {
      attempts++;
      if (attempts == 1) throw PlatformException(code: 'TEMPORARY');
      return <String, dynamic>{'text': 'Probeer opnieuw', 'submitted': true};
    });
    await pumpSurface(tester);
    await press(tester, LogicalKeyboardKey.select);
    expect(find.text(t.assistant.listening.failed), findsOneWidget);
    expect(c.submitted, isEmpty);
    expect(focusedLabel(), 'assistant.ask');
    await press(tester, LogicalKeyboardKey.select);
    expect(attempts, 2);
    expect(c.submitted, ['Probeer opnieuw']);
    expect(find.text(t.assistant.listening.failed), findsNothing);
  });

  group('gates', () {
    testWidgets('locked shows 38 B with one way back and no ask button', (tester) async {
      c.availability = AssistantAvailability.locked;
      await pumpSurface(tester);

      expect(find.text(t.assistant.locked.title), findsOneWidget);
      expect(find.text(t.assistant.locked.back), findsOneWidget);
      expect(find.text(t.assistant.idle.ask), findsNothing);
      expect(focusedLabel(), 'assistant.gate');
    });

    testWidgets('needsSetup shows 38 C1 with "Big P instellen" focused', (tester) async {
      c.availability = AssistantAvailability.needsSetup;
      await pumpSurface(tester);

      expect(find.text(t.assistant.setup.title), findsOneWidget);
      expect(find.text(t.assistant.setup.action), findsOneWidget);
      expect(focusedLabel(), 'assistant.gate');
    });
  });

  group('set-up gate', () {
    testWidgets('closing the setup reads availability again', (tester) async {
      c.availability = AssistantAvailability.needsSetup;
      await pumpSurface(tester);
      final before = c.refreshes;

      await press(tester, LogicalKeyboardKey.select);
      expect(find.byType(AssistantSettingsScreen), findsOneWidget);
      expect(c.refreshes, before);

      c.refreshTo = AssistantAvailability.ready;
      Navigator.of(tester.element(find.byType(AssistantSettingsScreen))).pop();
      await settle(tester);

      expect(find.byType(AssistantSettingsScreen), findsNothing);
      expect(c.refreshes, before + 1);
      expect(c.availability, AssistantAvailability.ready);
    });
  });

  group('rust and luisteren', () {
    testWidgets('opens on "Vraag Big P" with three example questions, and starts clean', (tester) async {
      await pumpSurface(tester);

      expect(focusedLabel(), 'assistant.ask');
      final shown = BigPSuggestions.of(c).examples(t.assistant.idle.examples);
      expect(shown, hasLength(3));
      expect(t.assistant.idle.examples.expand((kind) => kind), containsAll(shown));
      for (final example in shown) {
        expect(find.text(example), findsOneWidget);
      }
      expect(c.resets, 1);
      expect(c.conversationClears, 1, reason: 'a new visit is a new conversation');
      expect(avatar(tester).mood, BigPMood.idle);
    });

    testWidgets('Vraag Big P opens the native keyboard with a send key and submits what was sent', (tester) async {
      keyboardAnswers('scan films');
      await pumpSurface(tester);

      await press(tester, LogicalKeyboardKey.select);

      expect(edits.single['action'], 'send');
      expect(c.submitted, ['scan films']);
    });

    testWidgets('a follow-up under a result asks it at once', (tester) async {
      await pumpSurface(tester);
      c
        ..prompt = 'wie keek het meest'
        ..state = AssistantSurfaceState.result
        ..displays = [const AssistantWatchStats(serverName: 'Zolder', days: 7)]
        ..emit();
      await settle(tester);

      final question = t.assistant.followUp.watchNow;
      expect(find.text(question), findsOneWidget);
      expect(find.text(t.assistant.followUp.watchMonth), findsOneWidget);
      tester.widget<BigPChip>(find.widgetWithText(BigPChip, question)).onSelect();
      await settle(tester);

      expect(c.submitted, [question]);
      expect(c.conversationClears, 1, reason: 'asking keeps the conversation going');
    });

    testWidgets('backing out of the keyboard asks nothing', (tester) async {
      keyboardAnswers('half a question', submitted: false);
      await pumpSurface(tester);

      await press(tester, LogicalKeyboardKey.select);

      expect(edits, hasLength(1));
      expect(c.submitted, isEmpty);
      expect(c.cancelledListening, 1);
    });

    testWidgets('choosing an example submits it at once', (tester) async {
      await pumpSurface(tester);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.submitted, [BigPSuggestions.of(c).examples(t.assistant.idle.examples).first]);
      expect(edits, isEmpty, reason: 'an example needs no keyboard');
    });
  });

  testWidgets('werken shows the live steps from tool and server names, with Annuleren focused', (tester) async {
    await pumpSurface(tester);
    c
      ..prompt = 'Scan Films op Zolder'
      ..state = AssistantSurfaceState.working
      ..steps = const [
        AssistantStep(index: 0, tool: 'list_libraries', serverName: 'Zolder', phase: AssistantStepPhase.done),
        AssistantStep(index: 1, tool: 'scan_library', serverName: 'Zolder', phase: AssistantStepPhase.started),
      ]
      ..emit();
    await settle(tester);

    expect(
      find.text(t.assistant.steps.withServer(server: 'Zolder', step: t.assistant.steps.listLibraries)),
      findsOneWidget,
    );
    expect(
      find.text(t.assistant.steps.withServer(server: 'Zolder', step: t.assistant.steps.scanLibrary)),
      findsOneWidget,
    );
    expect(avatar(tester).mood, BigPMood.working);
    expect(avatar(tester).pointAt, isNotNull);
    expect(focusedLabel(), 'assistant.cancel');
  });

  testWidgets('werken with streamed results shows them and says Big P is still checking', (tester) async {
    await pumpSurface(tester);
    c
      ..prompt = 'Wie keek er?'
      ..state = AssistantSurfaceState.working
      ..displays = [const AssistantWatchStats(serverName: 'Zolder')]
      ..stillChecking = true
      ..emit();
    await settle(tester);

    expect(find.text(t.assistant.working.stillChecking), findsOneWidget);
    expect(find.text(t.assistant.working.status), findsNothing);
    expect(find.text(t.assistant.displays.watchTitle), findsOneWidget);
    expect(find.text(t.assistant.result.done), findsNothing, reason: 'not presented as finished');
    expect(focusedLabel(), 'assistant.cancel');
  });

  group('resultaat', () {
    testWidgets('success: Big P cheers; Pleya lists what it did', (tester) async {
      await pumpSurface(tester);
      c
        ..prompt = 'Scan Films'
        ..state = AssistantSurfaceState.result
        ..answer = 'Ik heb de scan gestart.'
        ..actions = const [
          AssistantActionRecord(kind: AssistantActionKind.scanLibrary, serverName: 'Zolder', subject: 'Films'),
        ]
        ..emit();
      await settle(tester);

      expect(avatar(tester).mood, BigPMood.success);
      expect(find.text('${t.assistant.actions.scanLibrary} · Films · Zolder'), findsOneWidget);
      expect(focusedLabel(), 'assistant.ask');

      // No voice on this controller: the mouth stays shut, the text is on screen.
      await tester.pump(const Duration(milliseconds: 1500));
      expect(avatar(tester).talkingText, isNull);
    });

    testWidgets('a search that found nothing draws no empty cards', (tester) async {
      await pumpSurface(tester);
      c
        ..prompt = 'Zoek een film over de ruimte'
        ..state = AssistantSurfaceState.result
        ..answer = 'Geen resultaten gevonden.'
        ..displays = [
          const AssistantMediaGrid([]),
          AssistantRequestOptions(AssistantToolContext(servers: MultiServerManager()), const []),
        ]
        ..emit();
      await settle(tester);

      expect(find.byType(BigPCard), findsNothing);
    });

    testWidgets('error: worried Big P and a Pleya card that says nothing changed', (tester) async {
      await pumpSurface(tester);
      c
        ..prompt = 'Scan Films'
        ..state = AssistantSurfaceState.result
        ..resultIsError = true
        ..lastEnd = AssistantRunEnd.stepLimit
        ..emit();
      await settle(tester);

      expect(avatar(tester).mood, BigPMood.error);
      // Set as a lead sentence and what follows (mockup 38 J).
      for (final sentence in t.assistant.ends.stepLimit.split(RegExp(r'(?<=\.)\s'))) {
        expect(find.text(sentence), findsOneWidget);
      }
      expect(find.textContaining(t.assistant.result.notDoneBy), findsOneWidget);
      expect(find.text(t.assistant.ends.nothingChanged), findsOneWidget);
    });

    testWidgets('Klaar ends the conversation and leaves the surface', (tester) async {
      var dismissed = 0;
      await pumpSurface(tester, onDismiss: () => dismissed++);
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Klaar.'
        ..emit();
      await settle(tester);

      await press(tester, LogicalKeyboardKey.arrowRight); // Nieuw gesprek
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);

      expect(dismissed, 1);
      expect(c.resets, 2, reason: 'once on open, once for Klaar');
      expect(c.conversationClears, 2, reason: 'Klaar ends the conversation');
    });

    testWidgets('an option card takes the focus and hands the pick to the controller', (tester) async {
      await pumpSurface(tester);
      const option = AssistantRequestOption(
        seerrId: 'movie:286217',
        title: 'The Martian',
        year: 2015,
        kind: 'movie',
        posterUrl: '',
        overview: 'Astronaut Mark Watney',
        status: 'not_requested',
      );
      c
        ..state = AssistantSurfaceState.result
        ..answer = 'Ik vond deze film.'
        ..displays = [
          AssistantRequestOptions(AssistantToolContext(servers: MultiServerManager()), const [option]),
        ]
        ..emit();
      await settle(tester);

      expect(focusedLabel(), 'assistant.option');
      expect(find.text(t.assistant.option.notRequested), findsOneWidget);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.picked.single.seerrId, 'movie:286217');
    });
  });

  group('the confirmation card', () {
    AssistantPendingAction createSam({AssistantPasswordMode password = AssistantPasswordMode.required}) =>
        AssistantPendingAction(
          kind: AssistantActionKind.createUser,
          serverId: ServerId('zolder'),
          serverName: 'Zolder',
          subject: 'Sam',
          libraryNames: const ['Kids'],
          password: password,
          execute: ({password}) async => const {},
        );

    Future<void> raise(WidgetTester tester, AssistantPendingAction action) async {
      await pumpSurface(tester);
      c
        ..prompt = 'Maak Sam aan'
        ..answer = 'MODEL TEXT'
        ..state = AssistantSurfaceState.working
        ..pending = action
        ..emit();
      await settle(tester);
    }

    testWidgets('is built from the pending action only, opens on Annuleren, Big P attentive', (tester) async {
      await raise(tester, createSam());

      final card = find.byType(BigPConfirmCard);
      expect(card, findsOneWidget);
      for (final text in ['Sam', 'Zolder', 'Kids', t.assistant.confirm.no, t.assistant.confirm.passwordPlaceholder]) {
        expect(
          find.descendant(of: card, matching: find.text(text)),
          findsOneWidget,
          reason: text,
        );
      }
      expect(find.descendant(of: card, matching: find.textContaining('MODEL TEXT')), findsNothing);
      expect(focusedLabel(), 'assistant.confirm.cancel');
      expect(avatar(tester).mood, BigPMood.attentive);
    });

    testWidgets('a home row card has no empty Server line (BIGP-UI2)', (tester) async {
      await raise(
        tester,
        AssistantPendingAction(
          kind: AssistantActionKind.createHomeRow,
          serverId: ServerId('zolder'),
          serverName: '',
          subject: 'Sci-fi avond',
          execute: ({password}) async => const {},
        ),
      );

      final card = find.byType(BigPConfirmCard);
      expect(find.descendant(of: card, matching: find.text('Sci-fi avond')), findsOneWidget);
      expect(find.descendant(of: card, matching: find.text(t.assistant.confirm.server)), findsNothing);
    });

    testWidgets('a home row preview stays text: nothing to focus between the card and its buttons', (tester) async {
      await raise(
        tester,
        AssistantPendingAction(
          kind: AssistantActionKind.createHomeRow,
          serverId: ServerId('zolder'),
          serverName: '',
          subject: 'Sci-fi avond',
          preview: AssistantMediaGrid([
            (
              item: MediaItem(
                id: '1',
                backend: MediaBackend.plex,
                kind: MediaKind.movie,
                title: 'Arrival',
                year: 2016,
                serverId: 'zolder',
              ),
              group: null,
            ),
          ]),
          execute: ({password}) async => const {},
        ),
      );

      final card = find.byType(BigPConfirmCard);
      expect(find.descendant(of: card, matching: find.text('Arrival (2016)')), findsOneWidget);
      expect(find.byType(BigPMatchCard), findsNothing);
    });

    testWidgets('a required password gates Aanmaken; the password goes to confirmPending only', (tester) async {
      await raise(tester, createSam());

      // Aanmaken without a password does nothing.
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);
      expect(c.confirmedPasswords, isEmpty);

      keyboardAnswers('geheim');
      Focus.of(tester.element(find.text(t.assistant.confirm.passwordPlaceholder))).requestFocus();
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);
      expect(edits.single['obscure'], isTrue);

      await press(tester, LogicalKeyboardKey.arrowDown);
      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.confirmedPasswords, ['geheim']);
      expect(c.cancelledPending, 0);
      expect(find.byType(BigPConfirmCard), findsNothing);
    });

    testWidgets('off Apple TV the password dialog is masked too', (tester) async {
      await raise(tester, createSam());
      TvDetectionService.debugSetAppleTVOverride(false);

      Focus.of(tester.element(find.text(t.assistant.confirm.passwordPlaceholder))).requestFocus();
      await settle(tester);
      await press(tester, LogicalKeyboardKey.select);

      final field = tester.widget<EditableText>(find.byType(EditableText).last);
      expect(field.obscureText, isTrue);
      expect(edits, isEmpty, reason: 'not the Apple TV keyboard');
    });

    testWidgets('without a password field Aanmaken works at once (38 I)', (tester) async {
      await raise(tester, createSam(password: AssistantPasswordMode.none));

      await press(tester, LogicalKeyboardKey.arrowRight);
      await press(tester, LogicalKeyboardKey.select);

      expect(c.confirmedPasswords, [null]);
    });

    testWidgets('Annuleren cancels', (tester) async {
      await raise(tester, createSam());

      await press(tester, LogicalKeyboardKey.select);

      expect(c.cancelledPending, 1);
      expect(c.confirmedPasswords, isEmpty);
    });

    testWidgets('Menu cancels', (tester) async {
      await raise(tester, createSam());

      await press(tester, LogicalKeyboardKey.escape);

      expect(c.cancelledPending, 1);
      expect(find.byType(BigPConfirmCard), findsNothing);
    });

    testWidgets('a card that timed out under the viewer goes away without an answer', (tester) async {
      await raise(tester, createSam());

      c
        ..pending = null
        ..emit();
      await settle(tester);

      expect(find.byType(BigPConfirmCard), findsNothing);
      expect(c.cancelledPending, 0);
      expect(c.confirmedPasswords, isEmpty);
    });
  });
}
