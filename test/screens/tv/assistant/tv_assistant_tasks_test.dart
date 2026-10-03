/// Several commands in one question: one card per task in the shared
/// conversation, the same on Big P's surface and in the summoned panel. Every
/// case runs on both.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_controller.dart';
import 'package:pleya/assistant/assistant_run.dart';
import 'package:pleya/assistant/assistant_tool_context.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_confirm_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_option_card.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_results.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_widgets.dart';
import 'package:pleya/services/apple_tv_native_text_entry.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/speech_search_service.dart';
import 'package:pleya/utils/native_input_session.dart';
import 'package:pleya/utils/platform_detector.dart';

import 'tv_assistant_test_support.dart';

const _question = 'Scan mijn films, vernieuw de metadata van Series en maak een gebruiker aan voor Guido';

AssistantRequestOption _option(String title) => AssistantRequestOption(
  seerrId: 'movie:$title',
  title: title,
  year: 2021,
  kind: 'movie',
  posterUrl: '',
  overview: '',
  status: 'not_requested',
);

AssistantTask _task(
  int n,
  String title,
  AssistantTaskStatus status, {
  List<AssistantDisplay> displays = const [],
  List<AssistantStep> steps = const [],
  List<AssistantActionRecord> actions = const [],
  AssistantRunEnd? lastEnd,
}) => AssistantTask(
  id: 'task-$n',
  title: title,
  intent: 'command',
  status: status,
  answer: '',
  displays: displays,
  steps: steps,
  actions: actions,
  lastEnd: lastEnd,
  error: status == AssistantTaskStatus.failed ? 'failed' : null,
);

AssistantPendingAction _create(String subject) => AssistantPendingAction(
  kind: AssistantActionKind.createUser,
  serverId: ServerId('zolder'),
  serverName: 'Zolder',
  subject: subject,
  execute: ({password}) async => const {},
);

const _scanned = AssistantActionRecord(kind: AssistantActionKind.scanLibrary, serverName: 'Zolder', subject: 'Films');
const _step = AssistantStep(index: 0, tool: 'list_libraries', phase: AssistantStepPhase.started, serverName: 'Zolder');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('test_assistant_tasks_entry');
  final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  late FakeAssistantController c;
  late StreamController<void> presses;
  late AssistantToolContext toolContext;

  setUp(() {
    TvDetectionService.debugSetAppleTVOverride(true);
    c = FakeAssistantController();
    presses = StreamController<void>.broadcast();
    toolContext = AssistantToolContext(servers: MultiServerManager());
    messenger.setMockMethodCallHandler(
      channel,
      (call) async => <String, dynamic>{'text': _question, 'submitted': true},
    );
  });

  tearDown(() {
    TvDetectionService.debugSetAppleTVOverride(null);
    messenger.setMockMethodCallHandler(channel, null);
    NativeInputSession.debugReset();
    unawaited(presses.close());
    c.dispose();
  });

  Future<void> press(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyEvent(key);
    await settle(tester);
  }

  /// What the controller says now, on screen.
  Future<void> show(WidgetTester tester, AssistantSurfaceState state, List<AssistantTask> tasks) async {
    c
      ..prompt = _question
      ..state = state
      ..tasks = tasks
      ..steps = [for (final task in tasks) ...task.steps]
      ..actions = [for (final task in tasks) ...task.actions]
      ..displays = [for (final task in tasks) ...task.displays]
      ..resultIsError = tasks.any((task) => task.status == AssistantTaskStatus.failed)
      ..emit();
    await settle(tester);
  }

  List<AutomationNode> nodes(WidgetTester tester, String id) =>
      tester.widgetList<AutomationNode>(find.byType(AutomationNode)).where((node) => node.id == id).toList();

  List<Object?> taskStates(WidgetTester tester) => [
    for (final node in nodes(tester, AutomationIds.assistantTask)) node.state!(),
  ];

  /// The capsules on screen, by the index of their task.
  List<String?> capsules(WidgetTester tester) => [
    for (final chip in tester.widgetList<TvAssistantChip>(find.byType(TvAssistantChip)))
      if (chip.automationId == AutomationIds.assistantTaskCancel) chip.automationInstance,
  ];

  Finder taskCard(int index) => find.byWidgetPredicate(
    (w) => w is AutomationNode && w.id == AutomationIds.assistantTask && w.instance == '$index',
  );

  Finder button(String label) => find.text(label);

  final surfaces = <String, Future<void> Function(WidgetTester)>{
    'the surface': (tester) async {
      final entry = AppleTvNativeTextEntry(channel: channel);
      await pumpTvFrame(
        tester,
        c,
        TvAssistantScreen(
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
        ),
      );
    },
    'the summoned panel': (tester) async {
      final entry = AppleTvNativeTextEntry(channel: channel);
      await pumpTvFrame(
        tester,
        c,
        TvAssistantSummonHost(
          longPresses: presses.stream,
          speech: SpeechSearchService(textEntry: entry),
          textEntry: entry,
          child: const SizedBox.expand(),
        ),
      );
      presses.add(null);
      await settle(tester);
    },
  };

  for (final MapEntry(key: name, value: pump) in surfaces.entries) {
    final summoned = name == 'the summoned panel';

    group('$name,', () {
      List<AssistantTask> working() => [
        _task(1, 'Films scannen · Zolder', AssistantTaskStatus.completed, actions: const [_scanned]),
        _task(2, 'Metadata vernieuwen · Series · Zolder', AssistantTaskStatus.running, steps: const [_step]),
        _task(3, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.pending),
      ];

      testWidgets('one command keeps the screen it had: steps, no cards, Annuleren', (tester) async {
        await pump(tester);
        await show(tester, AssistantSurfaceState.working, [
          _task(1, _question, AssistantTaskStatus.running, steps: const [_step]),
        ]);

        expect(find.byType(TvAssistantStepList), findsOneWidget);
        expect(taskStates(tester), isEmpty);
        expect(capsules(tester), isEmpty);
        expect(button(t.assistant.result.cancel), findsOneWidget);
        expect(button(t.assistant.tasks.cancelAll), findsNothing);
        expect(find.text(t.assistant.working.status), findsOneWidget);
        expect(focusedLabel(), 'assistant.cancel');

        await press(tester, LogicalKeyboardKey.select);
        expect(c.cancelledAll, 0, reason: 'one command is let go as before, not cancelled as a task');
      });

      testWidgets('werken: a card per task in the order asked, each with its state', (tester) async {
        await pump(tester);
        await show(tester, AssistantSurfaceState.working, working());

        expect(taskStates(tester), [
          {'id': 'task-1', 'status': 'completed', 'cancellable': false},
          {'id': 'task-2', 'status': 'running', 'cancellable': true},
          {'id': 'task-3', 'status': 'pending', 'cancellable': true},
        ]);
        expect(find.byType(TvAssistantStepList), findsNothing);
        expect(find.text(t.assistant.tasks.working(count: 3, done: 1)), findsOneWidget);
        expect(find.text('Films scannen · Zolder'), findsOneWidget);
        expect(find.textContaining(t.assistant.actions.scanLibrary, findRichText: true), findsOneWidget);
        expect(find.textContaining(t.assistant.steps.listLibraries, findRichText: true), findsOneWidget);
        expect(find.textContaining(t.assistant.tasks.queued, findRichText: true), findsOneWidget);
        // Only what can still be stopped has a capsule.
        expect(capsules(tester), ['1', '2']);
        expect(button(t.assistant.tasks.cancelAll), findsOneWidget);
        expect(focusedLabel(), 'assistant.cancel');
      });

      testWidgets('a task that finishes later keeps its place, and its results sit under its own card', (tester) async {
        await pump(tester);
        // The second task is the first with something to show.
        await show(tester, AssistantSurfaceState.working, [
          _task(1, 'Dune zoeken', AssistantTaskStatus.running),
          _task(
            2,
            'Severance aanvragen',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [_option('Severance')]),
            ],
          ),
          _task(3, 'Films scannen', AssistantTaskStatus.running),
        ]);

        expect(taskStates(tester).map((s) => (s! as Map)['id']), ['task-1', 'task-2', 'task-3']);
        final first = tester.getTopLeft(taskCard(0)).dy;
        final second = tester.getTopLeft(taskCard(1)).dy;
        final result = tester.getTopLeft(find.byType(TvAssistantOptionCard)).dy;
        final third = tester.getTopLeft(taskCard(2)).dy;
        expect(first, lessThan(second));
        expect(second, lessThan(result));
        expect(result, lessThan(third), reason: 'the result belongs to task 2, not to the end of the panel');
      });

      testWidgets('Annuleren on a card stops that task only; Alles annuleren stops what is left', (tester) async {
        await pump(tester);
        await show(tester, AssistantSurfaceState.working, working());
        final resets = c.resets;
        final aborts = c.aborts;

        // Up from the bottom button lands on the lowest capsule, not on a card.
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), 'assistant.task.cancel.task-3');
        await press(tester, LogicalKeyboardKey.select);
        expect(c.cancelledTasks, ['task-3']);
        expect(c.cancelledAll, 0);

        await press(tester, LogicalKeyboardKey.arrowDown);
        expect(focusedLabel(), 'assistant.cancel');
        await press(tester, LogicalKeyboardKey.select);
        expect(c.cancelledAll, 1);
        expect(c.resets, resets, reason: 'the cards stay; nothing is thrown away');
        expect(c.aborts, aborts);
        expect(taskStates(tester), hasLength(3));
      });

      testWidgets('the capsule says in full which task it stops, however long the title', (tester) async {
        const title =
            'Metadata vernieuwen · Series · De server op zolder met een bijzonder lange naam · alle seizoenen';
        final handle = tester.ensureSemantics();
        await pump(tester);
        await show(tester, AssistantSurfaceState.working, [
          _task(1, 'Films scannen', AssistantTaskStatus.completed),
          _task(2, title, AssistantTaskStatus.running),
        ]);

        final capsule = find.bySemanticsLabel(RegExp(RegExp.escape(t.assistant.tasks.cancelTask(title: title))));
        expect(capsule, findsOneWidget);
        handle.dispose();
      });

      testWidgets('a finished task takes a choice while another still runs; a running task does not', (tester) async {
        await pump(tester);
        final dune = _option('Dune');
        final arrival = _option('Arrival');
        await show(tester, AssistantSurfaceState.working, [
          _task(
            1,
            'Dune zoeken',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [dune]),
            ],
          ),
          _task(
            2,
            'Arrival zoeken',
            AssistantTaskStatus.running,
            displays: [
              AssistantRequestOptions(toolContext, [arrival]),
            ],
          ),
        ]);

        final cards = tester.widgetList<TvAssistantOptionCard>(find.byType(TvAssistantOptionCard)).toList();
        expect(cards.map((card) => card.onSelect != null), [true, false]);
        expect(focusedLabel(), 'assistant.cancel', reason: 'a result that came in does not take the remote');

        // Bottom button, the running task's inert card, its capsule, then
        // the finished task's card.
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.select);
        expect(c.picked, isEmpty);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), 'assistant.task.cancel.task-2');
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.select);

        expect(c.picked, [same(dune)]);
        expect(c.pickedForTask, ['task-1']);
      });

      testWidgets('a change behind the remote leaves it where it is; a capsule that goes hands it on', (tester) async {
        await pump(tester);
        await show(tester, AssistantSurfaceState.working, working());
        await press(tester, LogicalKeyboardKey.arrowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), 'assistant.task.cancel.task-2');
        final held = FocusManager.instance.primaryFocus;

        // Task 3 leaves the queue: nothing the viewer is on changed.
        await show(tester, AssistantSurfaceState.working, [
          working()[0],
          working()[1],
          _task(3, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.running),
        ]);
        expect(FocusManager.instance.primaryFocus, same(held));

        // Task 2 finishes under the remote: on to the next capsule down.
        await show(tester, AssistantSurfaceState.working, [
          working()[0],
          _task(2, 'Metadata vernieuwen · Series · Zolder', AssistantTaskStatus.completed),
          _task(3, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.running),
        ]);
        expect(focusedLabel(), 'assistant.task.cancel.task-3');

        // The last one finishes: no capsule left, the bottom control has it.
        await show(tester, AssistantSurfaceState.result, [
          working()[0],
          _task(2, 'Metadata vernieuwen · Series · Zolder', AssistantTaskStatus.completed),
          _task(3, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.completed),
        ]);
        expect(focusedLabel(), 'assistant.ask');
        // Nothing above it is a stop any more; the remote stays on a control.
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedLabel(), 'assistant.ask');
      });

      testWidgets('a choice the viewer is on keeps the remote when the last task ends', (tester) async {
        await pump(tester);
        List<AssistantTask> tasks(AssistantTaskStatus last) => [
          _task(
            1,
            'Dune zoeken',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [_option('Dune')]),
            ],
          ),
          _task(
            2,
            'Arrival zoeken',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [_option('Arrival')]),
            ],
          ),
          _task(3, 'Films scannen', last),
        ];
        await show(tester, AssistantSurfaceState.working, tasks(AssistantTaskStatus.running));
        await press(tester, LogicalKeyboardKey.arrowUp); // task 3's capsule
        await press(tester, LogicalKeyboardKey.arrowUp); // Arrival
        final held = FocusManager.instance.primaryFocus;
        expect(focusedLabel(), isNot('assistant.option'));
        expect(focusedLabel(), isNot(startsWith('assistant.task.cancel')));

        await show(tester, AssistantSurfaceState.result, tasks(AssistantTaskStatus.completed));

        expect(FocusManager.instance.primaryFocus, same(held));
      });

      testWidgets('a choice the viewer is on stays theirs when an earlier task shows its first result', (tester) async {
        await pump(tester);
        final dune = _option('Dune');
        final severance = _option('Severance');
        List<AssistantTask> tasks({required bool duneFound}) => [
          _task(
            1,
            'Dune zoeken',
            AssistantTaskStatus.running,
            displays: [
              if (duneFound) AssistantRequestOptions(toolContext, [dune]),
            ],
          ),
          _task(
            2,
            'Severance aanvragen',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [severance]),
            ],
          ),
        ];
        String? focusedTitle() => FocusManager.instance.primaryFocus?.context
            ?.findAncestorWidgetOfExactType<TvAssistantOptionCard>()
            ?.option
            .title;

        await show(tester, AssistantSurfaceState.working, tasks(duneFound: false));
        await press(tester, LogicalKeyboardKey.arrowUp);
        final held = FocusManager.instance.primaryFocus;
        expect(focusedTitle(), 'Severance');

        // Task 1's first result comes in above the card the viewer is on.
        await show(tester, AssistantSurfaceState.working, tasks(duneFound: true));

        expect(find.byType(TvAssistantOptionCard), findsNWidgets(2));
        expect(FocusManager.instance.primaryFocus, same(held));
        expect(focusedTitle(), 'Severance');
        await press(tester, LogicalKeyboardKey.select);
        expect(c.picked, [same(severance)]);
        expect(c.pickedForTask, ['task-2']);
      });

      testWidgets('resultaat with choices: the remote starts on the first choice of the first task that has one', (
        tester,
      ) async {
        await pump(tester);
        final dune = _option('Dune');
        await show(tester, AssistantSurfaceState.working, [
          _task(1, 'Films scannen', AssistantTaskStatus.completed),
          _task(2, 'Dune zoeken', AssistantTaskStatus.running),
          _task(3, 'Arrival zoeken', AssistantTaskStatus.running),
        ]);
        expect(focusedLabel(), 'assistant.cancel');

        await show(tester, AssistantSurfaceState.result, [
          _task(1, 'Films scannen', AssistantTaskStatus.completed),
          _task(
            2,
            'Dune zoeken',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [dune]),
            ],
          ),
          _task(
            3,
            'Arrival zoeken',
            AssistantTaskStatus.completed,
            displays: [
              AssistantRequestOptions(toolContext, [_option('Arrival')]),
            ],
          ),
        ]);

        await press(tester, LogicalKeyboardKey.select);
        expect(c.picked, [same(dune)]);
        expect(c.pickedForTask, ['task-2']);
      });

      testWidgets('resultaat: the same cards with their end state, no capsules, no second card', (tester) async {
        await pump(tester);
        await show(tester, AssistantSurfaceState.result, [
          _task(1, 'Films scannen · Zolder', AssistantTaskStatus.completed, actions: const [_scanned]),
          _task(2, 'Metadata vernieuwen', AssistantTaskStatus.failed, lastEnd: AssistantRunEnd.stepLimit),
          _task(3, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.cancelled),
        ]);

        expect(taskStates(tester), [
          {'id': 'task-1', 'status': 'completed', 'cancellable': false},
          {'id': 'task-2', 'status': 'failed', 'cancellable': false},
          {'id': 'task-3', 'status': 'cancelled', 'cancellable': false},
        ]);
        expect(capsules(tester), isEmpty);
        expect(find.byType(TvAssistantResultCard), findsNothing);
        expect(find.text(t.assistant.tasks.someDone(count: 3, done: 1)), findsOneWidget);
        expect(find.textContaining(t.assistant.result.doneBy), findsOneWidget);
        expect(find.textContaining(t.assistant.tasks.failed, findRichText: true), findsOneWidget);
        expect(find.textContaining(t.assistant.ends.stepLimit, findRichText: true), findsOneWidget);
        expect(find.textContaining(t.assistant.tasks.cancelled, findRichText: true), findsOneWidget);
        // A cancelled task never claims that nothing was sent.
        expect(find.textContaining(t.assistant.ends.nothingChanged, findRichText: true), findsNothing);
        expect(button(t.assistant.tasks.cancelAll), findsNothing);
        expect(focusedLabel(), 'assistant.ask');
      });

      group('the confirmation card', () {
        final first = AssistantTaskConfirmation(id: 'confirmation-1', taskId: 'task-2', action: _create('Guido'));
        final second = AssistantTaskConfirmation(id: 'confirmation-2', taskId: 'task-3', action: _create('Sam'));

        List<AssistantTask> waiting() => [
          _task(1, 'Films scannen · Zolder', AssistantTaskStatus.running),
          _task(2, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.waitingForConfirmation),
          _task(3, 'Gebruiker aanmaken · Sam', AssistantTaskStatus.waitingForConfirmation),
        ];

        Future<void> raise(WidgetTester tester) async {
          await pump(tester);
          c
            ..confirmation = first
            ..pending = first.action;
          await show(tester, AssistantSurfaceState.working, waiting());
        }

        testWidgets('comes up by itself on Annuleren and answers for its own task', (tester) async {
          await raise(tester);

          expect(find.byType(TvAssistantConfirmCard), findsOneWidget);
          expect(focusedLabel(), 'assistant.confirm.cancel');
          expect((taskStates(tester)[1]! as Map)['status'], 'waitingForConfirmation');

          await press(tester, LogicalKeyboardKey.select);

          expect(c.cancelledConfirmations, [('task-2', 'confirmation-1')]);
          expect(c.cancelledTasks, isEmpty, reason: 'the card declines one action; it stops nothing else');
          expect(c.cancelledAll, 0);
        });

        testWidgets('an old card cannot answer for the action that took its place', (tester) async {
          await raise(tester);

          // The queue moved on under the card; the surface has not heard yet.
          c
            ..confirmation = second
            ..pending = second.action;
          await press(tester, LogicalKeyboardKey.arrowRight);
          await press(tester, LogicalKeyboardKey.select);

          expect(c.confirmedTasks, isEmpty);
          expect(c.cancelledConfirmations, isEmpty);

          // Now it hears: the card for the new action comes, and answers for it.
          c.emit();
          await settle(tester);
          expect(find.byType(TvAssistantConfirmCard), findsOneWidget);
          expect(find.descendant(of: find.byType(TvAssistantConfirmCard), matching: find.text('Sam')), findsOneWidget);
          await press(tester, LogicalKeyboardKey.arrowRight);
          await press(tester, LogicalKeyboardKey.select);

          expect(c.confirmedTasks, [('task-3', 'confirmation-2')]);
        });

        testWidgets('one card at a time: the next in the queue follows the one answered', (tester) async {
          await raise(tester);

          await press(tester, LogicalKeyboardKey.arrowRight);
          await press(tester, LogicalKeyboardKey.select);
          expect(c.confirmedTasks, [('task-2', 'confirmation-1')]);

          c
            ..confirmation = second
            ..pending = second.action
            ..emit();
          await settle(tester);

          expect(find.byType(TvAssistantConfirmCard), findsOneWidget);
          expect(focusedLabel(), 'assistant.confirm.cancel');
          await press(tester, LogicalKeyboardKey.select);
          expect(c.cancelledConfirmations, [('task-3', 'confirmation-2')]);

          c
            ..confirmation = null
            ..pending = null
            ..emit();
          await settle(tester);
          expect(find.byType(TvAssistantConfirmCard), findsNothing);
          expect(focusedLabel(), 'assistant.cancel', reason: 'back where the remote was before the cards');
        });
      });

      if (summoned) {
        Object? lingering(WidgetTester tester) =>
            (nodes(tester, AutomationIds.assistantSummon).single.state!()! as Map)['lingering'];

        testWidgets('stays until Menu when a task was cancelled; leaves by itself when all are done', (tester) async {
          await pump(tester);
          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Films scannen', AssistantTaskStatus.completed),
            _task(2, 'Gebruiker aanmaken', AssistantTaskStatus.cancelled),
          ]);
          expect(lingering(tester), isFalse);

          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Films scannen', AssistantTaskStatus.completed),
            _task(2, 'Gebruiker aanmaken', AssistantTaskStatus.completed),
          ]);
          expect(lingering(tester), isTrue);
        });
      }
    });
  }
}
