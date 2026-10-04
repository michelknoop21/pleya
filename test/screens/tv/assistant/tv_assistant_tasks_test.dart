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
import 'package:pleya/assistant/big_p_voice.dart';
import 'package:pleya/automation/automation_ids.dart';
import 'package:pleya/automation/automation_node.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_screen.dart';
import 'package:pleya/screens/tv/assistant/tv_assistant_summon.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_assistant_widgets.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_confirm_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_option_card.dart';
import 'package:pleya/widgets/big_p/assistant/big_p_results.dart';
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
  String answer = '',
}) => AssistantTask(
  id: 'task-$n',
  title: title,
  intent: 'command',
  status: status,
  answer: answer,
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
    for (final chip in tester.widgetList<BigPChip>(find.byType(BigPChip)))
      if (chip.automationId == AutomationIds.assistantTaskCancel) chip.automationInstance,
  ];

  /// The follow-ups on screen, by their place in the row.
  List<String?> followUps(WidgetTester tester) => [
    for (final chip in tester.widgetList<BigPChip>(find.byType(BigPChip)))
      if (chip.automationId == AutomationIds.assistantFollowUp) chip.automationInstance,
  ];

  /// The scrolling part of the task list; an answer's own box comes after it.
  Finder list() => find
      .descendant(of: find.byKey(const ValueKey('assistant.tasks')), matching: find.byType(SingleChildScrollView))
      .first;

  ScrollPosition listPosition(WidgetTester tester) =>
      tester.state<ScrollableState>(find.descendant(of: list(), matching: find.byType(Scrollable)).first).position;

  Rect focusedRect() {
    final box = FocusManager.instance.primaryFocus!.context!.findRenderObject()! as RenderBox;
    return box.localToGlobal(Offset.zero) & box.size;
  }

  /// What the remote is on, with the ring it draws inside its own box, is in
  /// the list's box and in no edge that fades because there is more beyond.
  void expectFocusedClearOfFades(WidgetTester tester) {
    final view = tester.getRect(list());
    final position = listPosition(tester);
    final rect = focusedRect();
    final label = focusedLabel();
    expect(
      rect.top,
      greaterThanOrEqualTo(view.top + (position.extentBefore > 0.5 ? 44 : 0) - 0.5),
      reason: '$label under the top edge',
    );
    expect(
      rect.bottom,
      lessThanOrEqualTo(view.bottom - (position.extentAfter > 0.5 ? 44 : 0) + 0.5),
      reason: '$label over the bottom edge',
    );
  }

  /// Whether the remote is in the scrolling list, not on the buttons that
  /// stand under it: only the list has edges that fade.
  bool focusedInList(WidgetTester tester) {
    final view = tester.element(list());
    var inside = false;
    FocusManager.instance.primaryFocus?.context?.visitAncestorElements((element) {
      inside = identical(element, view);
      return !inside;
    });
    return inside;
  }

  String? focusedOption() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BigPOptionCard>()?.option.title;

  String? focusedChip() =>
      FocusManager.instance.primaryFocus?.context?.findAncestorWidgetOfExactType<BigPChip>()?.automationId;

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

        expect(find.byType(BigPStepList), findsOneWidget);
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
        expect(find.byType(BigPStepList), findsNothing);
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
        final result = tester.getTopLeft(find.byType(BigPOptionCard)).dy;
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

        final cards = tester.widgetList<BigPOptionCard>(find.byType(BigPOptionCard)).toList();
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
        // No card above it is a stop any more: Up finds the follow-ups, the
        // only thing left to choose, and the remote stays on a control.
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedChip(), AutomationIds.assistantFollowUp);
        await press(tester, LogicalKeyboardKey.arrowUp);
        expect(focusedChip(), AutomationIds.assistantFollowUp);
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
        await show(tester, AssistantSurfaceState.working, tasks(duneFound: false));
        await press(tester, LogicalKeyboardKey.arrowUp);
        final held = FocusManager.instance.primaryFocus;
        expect(focusedOption(), 'Severance');

        // Task 1's first result comes in above the card the viewer is on.
        await show(tester, AssistantSurfaceState.working, tasks(duneFound: true));

        expect(find.byType(BigPOptionCard), findsNWidgets(2));
        expect(FocusManager.instance.primaryFocus, same(held));
        expect(focusedOption(), 'Severance');
        await press(tester, LogicalKeyboardKey.select);
        expect(c.picked, [same(severance)]);
        expect(c.pickedForTask, ['task-2']);
      });

      // A task's displays are not append-only: its final result can take
      // away what it streamed, also the card the viewer is on.
      for (final sibling in [true, false]) {
        testWidgets('a choice that goes under the remote hands it to '
            '${sibling ? 'the first choice left' : 'the bottom control'}', (tester) async {
          await pump(tester);
          final dune = _option('Dune');
          List<AssistantTask> tasks({required bool current}) => [
            _task(
              1,
              'Dune zoeken',
              AssistantTaskStatus.completed,
              displays: [
                if (sibling) AssistantRequestOptions(toolContext, [dune]),
              ],
            ),
            _task(
              2,
              'Arrival zoeken',
              current ? AssistantTaskStatus.running : AssistantTaskStatus.failed,
              displays: [
                if (current) AssistantRequestOptions(toolContext, [_option('Arrival')]),
              ],
            ),
          ];
          await show(tester, AssistantSurfaceState.working, tasks(current: true));
          await press(tester, LogicalKeyboardKey.arrowUp);
          expect(focusedOption(), 'Arrival');

          // Task 2 ends on evidence that no longer holds: its card is gone.
          await show(tester, AssistantSurfaceState.result, tasks(current: false));

          expect(find.byType(BigPOptionCard), findsNWidgets(sibling ? 1 : 0));
          if (sibling) {
            expect(focusedOption(), 'Dune');
            await press(tester, LogicalKeyboardKey.select);
            expect(c.picked, [same(dune)]);
            expect(c.pickedForTask, ['task-1']);
          } else {
            expect(focusedLabel(), 'assistant.ask');
          }
        });
      }

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
        expect(find.byType(BigPResultCard), findsNothing);
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

      group('several results in one panel:', () {
        final long = List.filled(30, 'De film speelt direct af op deze Apple TV, zonder omzetten.').join(' ');

        AssistantWatchStats watched() => AssistantWatchStats(
          serverName: 'Zolder',
          days: 7,
          users: const [(name: 'Gideuh', plays: 36, seconds: 0), (name: 'Jan', plays: 6, seconds: 0)],
          titles: [
            for (final title in ['The Block', 'House', 'Heat', 'Ronin', 'Sintel'])
              (title: title, plays: 9, viewers: const ['Jan'], show: false, target: null),
          ],
        );

        AssistantTask found(int n, String title, AssistantTaskStatus status, List<String> titles) => _task(
          n,
          title,
          status,
          displays: [
            if (titles.isNotEmpty) AssistantRequestOptions(toolContext, [for (final title in titles) _option(title)]),
          ],
        );

        testWidgets('a task that only answered reads whole: four lines at once, the rest by Up and Down', (
          tester,
        ) async {
          await pump(tester);
          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Afspelen van Dune controleren', AssistantTaskStatus.completed, answer: '**Dune** $long'),
            _task(2, 'Films scannen · Zolder', AssistantTaskStatus.completed, actions: const [_scanned]),
          ]);

          final answer = find.byKey(const ValueKey('assistant.task.answer.task-1'));
          final body = find.descendant(of: answer, matching: find.byKey(const ValueKey('assistant.answer.body')));
          final text = tester.widget<Text>(body);
          expect(text.data, 'Dune $long', reason: 'every word, in plain text');
          expect(text.maxLines, isNull, reason: 'never cut short with an ellipsis');
          final line = text.style!.fontSize! * text.style!.height!;
          expect(tester.getSize(answer).height, closeTo(4 * line, 0.5));
          // Under its own task, above the next one.
          expect(tester.getRect(answer).top, greaterThan(tester.getRect(taskCard(0)).bottom - 0.5));
          expect(tester.getRect(answer).bottom, lessThan(tester.getRect(taskCard(1)).top + 0.5));

          // Up from Ask, past the follow-ups.
          for (var i = 0; i < 8 && focusedLabel() != 'assistant.task.answer.task-1'; i++) {
            await press(tester, LogicalKeyboardKey.arrowUp);
          }
          expect(focusedLabel(), 'assistant.task.answer.task-1');
          final top = tester.getRect(body).top;
          await press(tester, LogicalKeyboardKey.arrowDown);
          expect(tester.getRect(body).top, lessThan(top), reason: 'Down reads on');
          expect(focusedLabel(), 'assistant.task.answer.task-1');
          for (var i = 0; i < 60 && focusedLabel() == 'assistant.task.answer.task-1'; i++) {
            await press(tester, LogicalKeyboardKey.arrowDown);
          }
          expect(focusedLabel(), isNot('assistant.task.answer.task-1'), reason: 'at its last line the key moves on');
        });

        testWidgets('each answer keeps its own words and its own reading stop', (tester) async {
          await pump(tester);
          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Afspelen van Dune controleren', AssistantTaskStatus.completed, answer: 'Eerste. $long'),
            _task(2, 'Afspelen van Heat controleren', AssistantTaskStatus.completed, answer: 'Tweede. $long'),
          ]);

          Finder body(int n) => find.descendant(
            of: find.byKey(ValueKey('assistant.task.answer.task-$n')),
            matching: find.byKey(const ValueKey('assistant.answer.body')),
          );
          expect(tester.widget<Text>(body(1)).data, startsWith('Eerste.'));
          expect(tester.widget<Text>(body(2)).data, startsWith('Tweede.'));

          final seen = <String?>{};
          for (var i = 0; i < 12; i++) {
            await press(tester, LogicalKeyboardKey.arrowUp);
            seen.add(focusedLabel());
          }
          expect(seen, containsAll(['assistant.task.answer.task-1', 'assistant.task.answer.task-2']));
        });

        testWidgets('follow-ups: one row of three, only once every task has ended and none failed', (tester) async {
          await pump(tester);
          await show(tester, AssistantSurfaceState.working, [
            found(1, 'Dune zoeken', AssistantTaskStatus.completed, ['Dune']),
            _task(2, 'Films scannen', AssistantTaskStatus.running),
          ]);
          expect(followUps(tester), isEmpty, reason: 'a task still runs');

          await show(tester, AssistantSurfaceState.result, [
            found(1, 'Dune zoeken', AssistantTaskStatus.completed, ['Dune']),
            _task(2, 'Films scannen', AssistantTaskStatus.completed),
          ]);
          expect(followUps(tester), ['0', '1', '2']);

          await show(tester, AssistantSurfaceState.result, [
            found(1, 'Dune zoeken', AssistantTaskStatus.completed, ['Dune']),
            _task(2, 'Films scannen', AssistantTaskStatus.failed, lastEnd: AssistantRunEnd.stepLimit),
          ]);
          expect(followUps(tester), isEmpty, reason: 'a failed task is no answer to follow up on');
        });

        testWidgets('a failed task keeps what the others found on screen and theirs to choose', (tester) async {
          await pump(tester);
          final heat = _option('Heat');
          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Afspelen van Dune controleren', AssistantTaskStatus.failed, lastEnd: AssistantRunEnd.stepLimit),
            _task(
              2,
              'Iets voor vanavond zoeken',
              AssistantTaskStatus.completed,
              displays: [
                AssistantRequestOptions(toolContext, [heat]),
              ],
            ),
            _task(3, 'Reacher aanvragen', AssistantTaskStatus.cancelled),
          ]);

          expect(find.textContaining(t.assistant.ends.stepLimit, findRichText: true), findsOneWidget);
          expect(find.byType(BigPResultCard), findsNothing, reason: 'no red card over the task that did end well');
          expect(tester.widget<BigPOptionCard>(find.byType(BigPOptionCard)).onSelect, isNotNull);
          expect(focusedLabel(), 'assistant.task.option.task-2');
          await press(tester, LogicalKeyboardKey.select);
          expect(c.picked, [same(heat)]);
          expect(c.pickedForTask, ['task-2']);
          expect(button(t.assistant.idle.ask), findsOneWidget);
          expect(button(t.assistant.result.done), findsOneWidget);
        });

        testWidgets('a long list scrolls under buttons that stay put, and the remote is never in a fading edge', (
          tester,
        ) async {
          await pump(tester);
          await show(tester, AssistantSurfaceState.result, [
            found(1, 'Dune zoeken', AssistantTaskStatus.completed, ['Dune', 'Dune: Part Two', 'Arrival', 'Tenet']),
            found(2, 'Heat zoeken', AssistantTaskStatus.completed, ['Heat', 'Ronin', 'Collateral', 'Thief']),
            found(3, 'Alien zoeken', AssistantTaskStatus.completed, ['Alien', 'Aliens', 'Prometheus', 'Sunshine']),
          ]);

          final ask = tester.getRect(button(t.assistant.idle.ask));
          expect(listPosition(tester).maxScrollExtent, greaterThan(0), reason: 'twelve cards do not fit');
          expect(focusedLabel(), 'assistant.task.option.task-1');
          expect(followUps(tester), ['0', '1', '2']);

          final walked = <String?>[];
          var scrolled = false;
          for (var i = 0; i < 20 && focusedInList(tester); i++) {
            expectFocusedClearOfFades(tester);
            walked.add(focusedOption());
            scrolled |= listPosition(tester).pixels > 0.5;
            expect(tester.getRect(button(t.assistant.idle.ask)), ask, reason: 'the buttons do not scroll');
            await press(tester, LogicalKeyboardKey.arrowDown);
          }
          // Out of the list, on a button under it: whichever is nearest to
          // the last follow-up.
          expect(focusedLabel(), anyOf('assistant.ask', t.assistant.result.done));
          expect(scrolled, isTrue);
          expect(
            walked.nonNulls,
            containsAllInOrder(['Dune', 'Tenet', 'Heat', 'Thief', 'Alien', 'Sunshine']),
            reason: 'every card is a stop, in the order asked',
          );

          // And back up, to the first card.
          for (var i = 0; i < 20 && focusedLabel() != 'assistant.task.option.task-1'; i++) {
            await press(tester, LogicalKeyboardKey.arrowUp);
            expectFocusedClearOfFades(tester);
          }
          expect(focusedLabel(), 'assistant.task.option.task-1');
          expect(tester.getRect(button(t.assistant.idle.ask)), ask);
        });

        testWidgets('results that come in above the remote leave it on its card, in the same place', (tester) async {
          await pump(tester);
          List<AssistantTask> tasks(List<String> first) => [
            found(1, 'Dune zoeken', AssistantTaskStatus.running, first),
            found(2, 'Heat zoeken', AssistantTaskStatus.completed, ['Heat', 'Ronin', 'Collateral', 'Thief']),
            found(3, 'Alien zoeken', AssistantTaskStatus.completed, ['Alien', 'Aliens', 'Prometheus', 'Sunshine']),
          ];
          await show(tester, AssistantSurfaceState.working, tasks(const []));
          expect(focusedLabel(), 'assistant.cancel');
          // Up from the bottom button: the lowest card in view.
          await press(tester, LogicalKeyboardKey.arrowUp);
          final held = FocusManager.instance.primaryFocus;
          final title = focusedOption();
          expect(title, isNotNull, reason: 'the remote is on a card of task 2 or 3');
          expect(listPosition(tester).maxScrollExtent, greaterThan(0));
          final before = focusedRect();
          final footer = tester.getRect(button(t.assistant.tasks.cancelAll));

          // Task 1 streams its first result in above that card, then a second.
          await show(tester, AssistantSurfaceState.working, tasks(const ['Dune']));
          expect(FocusManager.instance.primaryFocus, same(held));
          expect(focusedOption(), title);
          expect(focusedRect().top, closeTo(before.top, 1), reason: 'the list took the new card by scrolling');
          expectFocusedClearOfFades(tester);

          await show(tester, AssistantSurfaceState.working, tasks(const ['Dune', 'Dune: Part Two']));
          expect(FocusManager.instance.primaryFocus, same(held));
          expect(focusedOption(), title);
          expect(focusedRect().top, closeTo(before.top, 1));
          expect(tester.getRect(button(t.assistant.tasks.cancelAll)), footer);

          // Its own task, though every card's place in the panel moved on.
          await press(tester, LogicalKeyboardKey.select);
          expect(c.picked.single.title, title);
          expect(c.pickedForTask.single, anyOf('task-2', 'task-3'));
        });

        testWidgets('rows that cannot be chosen are no stops: the list is read as one, the buttons stay put', (
          tester,
        ) async {
          await pump(tester);
          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Afspelen van Dune controleren', AssistantTaskStatus.completed, answer: long),
            _task(2, 'Kijkcijfers van Zolder tonen', AssistantTaskStatus.completed, displays: [watched()]),
            _task(3, 'Kijkcijfers van Kelder tonen', AssistantTaskStatus.completed, displays: [watched()]),
          ]);

          expect(find.text('The Block'), findsNWidgets(2), reason: 'both tasks show their rows');
          expect(followUps(tester), ['0', '1', '2']);
          expect(focusedLabel(), 'assistant.ask');
          final ask = tester.getRect(button(t.assistant.idle.ask));
          final chips = [
            for (final chip in find.byType(BigPChip).evaluate()) tester.getRect(find.byWidget(chip.widget)),
          ];
          expect(listPosition(tester).maxScrollExtent, greaterThan(0));

          final seen = <String?>{};
          for (var i = 0; i < 24; i++) {
            await press(tester, i < 12 ? LogicalKeyboardKey.arrowUp : LogicalKeyboardKey.arrowDown);
            seen.add(focusedLabel());
            expect(focusedOption(), isNull);
            expect(tester.getRect(button(t.assistant.idle.ask)), ask, reason: 'the buttons do not scroll');
          }
          expect(seen, contains('assistant.results'), reason: 'the list itself is the reading stop');
          expect(seen, contains('assistant.task.answer.task-1'));
          expect(
            seen.difference(<String?>{'assistant.results', 'assistant.task.answer.task-1', 'assistant.ask'}),
            everyElement(isNot(startsWith('assistant.task'))),
            reason: 'no row and no task card took the remote',
          );
          expect(
            [for (final chip in find.byType(BigPChip).evaluate()) tester.getRect(find.byWidget(chip.widget))],
            chips,
            reason: 'the follow-ups stand above the buttons, out of the scrolling list',
          );
        });
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

          expect(find.byType(BigPConfirmCard), findsOneWidget);
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
          expect(find.byType(BigPConfirmCard), findsOneWidget);
          expect(find.descendant(of: find.byType(BigPConfirmCard), matching: find.text('Sam')), findsOneWidget);
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

          expect(find.byType(BigPConfirmCard), findsOneWidget);
          expect(focusedLabel(), 'assistant.confirm.cancel');
          await press(tester, LogicalKeyboardKey.select);
          expect(c.cancelledConfirmations, [('task-3', 'confirmation-2')]);

          c
            ..confirmation = null
            ..pending = null
            ..emit();
          await settle(tester);
          expect(find.byType(BigPConfirmCard), findsNothing);
          expect(focusedLabel(), 'assistant.cancel', reason: 'back where the remote was before the cards');
        });

        testWidgets('declining the card leaves its task running; only the controller ends it', (tester) async {
          await raise(tester);
          await press(tester, LogicalKeyboardKey.select);
          expect(c.cancelledConfirmations, [('task-2', 'confirmation-1')]);

          // The model got its answer and goes on: the task is still live,
          // with its capsule, and so are the others.
          c
            ..confirmation = null
            ..pending = null;
          await show(tester, AssistantSurfaceState.working, [
            _task(1, 'Films scannen · Zolder', AssistantTaskStatus.running),
            _task(2, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.running),
            _task(3, 'Gebruiker aanmaken · Sam', AssistantTaskStatus.pending),
          ]);
          expect(find.byType(BigPConfirmCard), findsNothing);
          expect(capsules(tester), ['0', '1', '2']);
          expect((taskStates(tester)[1]! as Map)['status'], 'running');
          expect(c.cancelledTasks, isEmpty);
          expect(c.cancelledAll, 0);

          // Its end is the controller's to say.
          await show(tester, AssistantSurfaceState.working, [
            _task(1, 'Films scannen · Zolder', AssistantTaskStatus.running),
            _task(2, 'Gebruiker aanmaken · Guido', AssistantTaskStatus.cancelled),
            _task(3, 'Gebruiker aanmaken · Sam', AssistantTaskStatus.running),
          ]);
          expect(capsules(tester), ['0', '2']);
          expect(find.textContaining(t.assistant.tasks.cancelled, findRichText: true), findsOneWidget);
        });

        testWidgets('Big P says his nod only when the card on screen was confirmed while still current', (
          tester,
        ) async {
          await raise(tester);
          final played = <String>[];
          BigPVoice(
            c,
            enabled: () => true,
            dictating: () => false,
            playbackActive: () => false,
            language: () => 'nl',
            clips: () async => const {'assets/audio/bigp/nl_nod_1.m4a': 'Doe ik.'},
            play: (asset) async {
              played.add(asset);
              return 0.05;
            },
            stop: () async {},
          );

          // The queue moved on under the card: its Goedkeuren confirms nothing.
          c
            ..confirmation = second
            ..pending = second.action;
          await press(tester, LogicalKeyboardKey.arrowRight);
          await press(tester, LogicalKeyboardKey.select);
          expect(c.confirmedTasks, isEmpty);
          expect(played, isEmpty, reason: 'nothing was confirmed');

          // The card for the action now waiting: declined, then no nod either.
          c.emit();
          await settle(tester);
          await press(tester, LogicalKeyboardKey.select);
          expect(c.cancelledConfirmations, [('task-3', 'confirmation-2')]);
          expect(played, isEmpty, reason: 'a declined action gets no nod');

          // A card confirmed while it is the one waiting.
          final third = AssistantTaskConfirmation(id: 'confirmation-3', taskId: 'task-2', action: _create('Guido'));
          c
            ..confirmation = third
            ..pending = third.action
            ..emit();
          await settle(tester);
          await press(tester, LogicalKeyboardKey.arrowRight);
          await press(tester, LogicalKeyboardKey.select);
          expect(c.confirmedTasks, [('task-2', 'confirmation-3')]);
          expect(played, ['assets/audio/bigp/nl_nod_1.m4a']);
        });
      });

      if (summoned) {
        testWidgets('stays until Menu or Klaar, also when every task is done', (tester) async {
          await pump(tester);
          final aborts = c.aborts;
          await show(tester, AssistantSurfaceState.result, [
            _task(1, 'Films scannen', AssistantTaskStatus.completed),
            _task(2, 'Gebruiker aanmaken', AssistantTaskStatus.completed),
          ]);

          await tester.pump(const Duration(seconds: 30));
          await settle(tester);

          expect((nodes(tester, AutomationIds.assistantSummon).single.state!()! as Map)['shown'], isTrue);
          expect(taskStates(tester), hasLength(2));
          expect(c.aborts, aborts, reason: 'he does not leave by himself');
        });
      }
    });
  }
}
