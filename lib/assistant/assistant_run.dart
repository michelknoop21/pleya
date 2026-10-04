import 'assistant_spoiler_context.dart';
import 'dart:async';
import 'dart:convert';

import '../exceptions/media_server_exceptions.dart';
import '../media/ids.dart';
import '../media/media_kind.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_entitlement.dart';
import 'assistant_execution.dart';
import 'assistant_intent.dart';
import 'assistant_named_titles.dart';
import 'assistant_provider.dart';
import 'assistant_recommend_constraints.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';

part 'assistant_run_answer.dart';
part 'assistant_run_execute.dart';
part 'assistant_run_loop.dart';
part 'assistant_run_prompt.dart';
part 'assistant_run_result.dart';

/// The user's answer on a confirmation card.
class AssistantConfirmation {
  const AssistantConfirmation({this.password});

  /// From Pleya's secure input. Never shown to, or sent to, the model.
  final String? password;
}

/// Shows [action] as a Pleya card and resolves with the user's answer, or
/// null when they cancel.
typedef AssistantConfirm = Future<AssistantConfirmation?> Function(AssistantPendingAction action);

enum AssistantStepPhase { started, done, failed }

/// One tool call as the UI shows it in the live step list. Built from the
/// tool name and Pleya's own server name, never from model text.
class AssistantStep {
  const AssistantStep({
    required this.index,
    required this.tool,
    required this.phase,
    this.serverName,
    this.display,
    this.evidenceCurrent,
  });
  final int index;
  final String tool;
  final String? serverName;
  final AssistantStepPhase phase;

  /// What the finished call handed the UI, so it can show while the model
  /// still composes its reply. Also in [AssistantRunResult.displays].
  final AssistantDisplay? display;
  final bool Function()? evidenceCurrent;
}

enum AssistantRunEnd { answered, stepLimit, notEntitled, noTools, toolsUnsupported, providerError }

class AssistantRunResult {
  const AssistantRunResult({
    required this.end,
    this.text = '',
    this.actions = const [],
    this.displays = const [],
    this.providerError,
    this.error,
    this.splitTasks = const [],
    this.playbackEvidenceCurrent,
    this.spoilerPrompt,
    this.libraryDoctorError,
    this.displayEvidenceCurrent,
    this.ageFilterNotice = false,
    this.kidsAgesNeeded = false,
    this.intent = AssistantIntent.unknown,
  });
  final AssistantRunEnd end;

  /// The model's closing words, for display only.
  final String text;

  /// What Pleya actually did, in order. Built from validated data.
  final List<AssistantActionRecord> actions;

  /// What tools handed the UI to show (a grid of titles, a comparison).
  final List<AssistantDisplay> displays;
  final AssistantModelError? providerError;
  final String? error;
  final List<AssistantTaskPlan> splitTasks;
  final bool Function()? playbackEvidenceCurrent;
  final String? spoilerPrompt;
  final String? Function()? libraryDoctorError;
  final bool Function()? displayEvidenceCurrent;

  /// The answer still named a title the age filter did not pass after the
  /// one correction round: [text] is empty and Pleya shows its own line.
  final bool ageFilterNotice;

  /// The ask is for children whose ages Pleya does not know yet: no model
  /// text and no title cards, only the ages card under Pleya's own line.
  final bool kidsAgesNeeded;

  /// What this ask fixed from the user's words, for tasks split off it.
  final AssistantIntent intent;
}

/// Model-proposed independent command, validated before any execution.
class AssistantTaskPlan {
  const AssistantTaskPlan({required this.title, required this.intent, required this.prompt});
  final String title;
  final String intent;
  final String prompt;
}

const _splitSpec = <String, Object?>{
  'type': 'function',
  'function': {
    'name': 'split_tasks',
    'description':
        'For a prompt with independent commands, return all commands as 2 to ${AssistantQuestionBudget.splitTaskCap} tasks. '
        'Use this call alone. Keep dependent steps (find then request) in one task. '
        'Tasks cannot refer to other tasks. Do not split a single command.',
    'parameters': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'tasks': {
          'type': 'array',
          'minItems': 2,
          'maxItems': AssistantQuestionBudget.splitTaskCap,
          'items': {
            'type': 'object',
            'additionalProperties': false,
            'properties': {
              'title': {'type': 'string'},
              'intent': {'type': 'string'},
              'prompt': {'type': 'string'},
            },
            'required': ['title', 'intent', 'prompt'],
          },
        },
      },
      'required': ['tasks'],
    },
  },
};

/// One prompt, answered: model call, validated tool calls, authority,
/// confirmation where needed, execution, and back to the model, at most
/// [maxSteps] times.
///
/// The model chooses tools; it never decides what is allowed. Every step
/// recomputes which tools and servers are available, so a role change or a
/// server going offline mid-run takes effect on the next call.
class AssistantRun {
  AssistantRun({
    required this.model,
    required this.context,
    required this.confirm,
    this.entitlement = const AssistantEntitlement(),
    this.tools,
    this.maxSteps = 6,
    this.languageName = 'Dutch',
    this.confirmTimeout = const Duration(minutes: 2),
    this.healthRefresh = const Duration(seconds: 10),
    this.onStep,
    this.cancel,
    this.allowSplit = false,
    this.budget,
    this.operations,
    this.mutations,
    this.controllerOwnsConfirmTimeout = false,
    this.refreshHealth,
    this.originalSpoilerPrompt,
    this.originalLibraryDoctorScope = false,
    this.inheritedIntent,
    this.conversation = const [],
  });

  /// The earlier turns of this conversation, oldest first: context for a
  /// follow-up, never evidence. See [_memoryMessages].
  final List<AssistantTurn> conversation;

  /// Whether the last [ask] ran for a children's profile; read by the
  /// controller to tag the turn it keeps.
  bool get askedAsKids => _ctx.kidsMode;

  /// Fires once the user cancelled or left (reset, profile switch): the
  /// model call on the wire is aborted, tools see it through their context,
  /// and it is checked before every model call, tool call and confirmed
  /// action, so nothing new starts after a cancel.
  final AbortController? cancel;

  bool get _cancelled => cancel?.isAborted ?? false;

  /// Called when a tool call starts and when it ends, for the live step list.
  final void Function(AssistantStep step)? onStep;

  final AssistantModelClient model;
  final AssistantToolContext context;
  final AssistantConfirm confirm;
  final AssistantEntitlement entitlement;
  final List<AssistantTool>? tools;
  final int maxSteps;
  final String languageName;
  final Duration confirmTimeout;
  final Duration healthRefresh;
  final bool allowSplit;

  /// Carried from the original submit; split children cannot rewrite it.
  final String? originalSpoilerPrompt;
  final bool originalLibraryDoctorScope;

  /// What the question this task was split from fixed; the task's own words win.
  final AssistantIntent? inheritedIntent;
  String? _spoilerQuestion;
  final AssistantQuestionBudget? budget;
  final AssistantOperationPool? operations;
  final AssistantOperationPool? mutations;
  final bool controllerOwnsConfirmTimeout;
  final Future<void> Function()? refreshHealth;
  final Map<String, String> _errors = {};

  Future<T> _operation<T>(Future<T> Function() operation) => operations?.run(operation) ?? operation();

  final List<AssistantActionRecord> _actions = [];
  final List<AssistantDisplay> _displays = [];

  /// Calls carried out per model reply and per run. A reply with a hundred
  /// scans, or a planted instruction that asks for them, stops here.
  static const int maxCallsPerReply = 4;
  static const int maxCallsPerRun = 10;

  /// The context of the ask in progress: a fresh copy of [context] per
  /// call, so ids, queries and candidates shown in one ask never carry into
  /// the next, nor across a profile switch between two asks.
  late AssistantToolContext _ctx;

  /// What the user's words fix about this ask; enforced on tool arguments.
  AssistantIntent _intent = AssistantIntent.unknown;
  bool _busy = false;

  /// One ask at a time; a second call while one runs is refused.
  Future<AssistantRunResult> ask(String prompt) async {
    if (_busy) throw StateError('AssistantRun.ask is already running');
    _busy = true;
    try {
      _ctx = context.fresh(cancel: cancel);
      _ctx.libraryDoctorMode = originalLibraryDoctorScope || assistantNeedsLibraryDoctorScope(prompt);
      _spoilerQuestion = originalSpoilerPrompt ?? (assistantNeedsSpoilerScope(prompt) ? prompt : null);
      _ctx.spoilerQuestion = _spoilerQuestion;
      return await _ask(prompt);
    } finally {
      _busy = false;
    }
  }

  /// Stand-in id for asking a serverless tool whether it serves at all, so a
  /// profile with Seerr but no media server still gets its request tools.
  static final _noServer = ServerId('none');

  int _stepIndex = 0;

  /// The ask in progress, for the ages card that submits it again.
  String _prompt = '';
  bool _ageNotice = false;

  /// Read by [_end]: the named-title cards are only shown while the sources
  /// they came from are still current.
  bool Function()? _namedTitlesCurrent;

  /// The my_watching pick grids of this run and the titles of the history it
  /// returned. The picks are material for the model, not an answer: only what
  /// the answer names stays a card, in the order the answer names it.
  final Set<AssistantMediaGrid> _pickGrids = {};
  final Set<String> _history = {};
  int? _wanted;
  bool _personal = false;

  /// find_media grids whose titles a later call acted on: a lookup on the way
  /// to an action, so the action is the result, not the grid.
  /// Each entry is (server, item id): backend ids are only unique per
  /// server, so an action on A's item `42` must not take B's `42` grid.
  final Map<AssistantMediaGrid, Set<(String?, String)>> _lookups = {};
}
