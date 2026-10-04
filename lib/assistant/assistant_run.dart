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
import 'assistant_named_titles.dart';
import 'assistant_provider.dart';
import 'assistant_recommend_constraints.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';

part 'assistant_run_answer.dart';
part 'assistant_run_execute.dart';
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
        'For a prompt with independent commands, return all commands as 2 to 10 tasks. '
        'Use this call alone. Keep dependent steps (find then request) in one task. '
        'Tasks cannot refer to other tasks. Do not split a single command.',
    'parameters': {
      'type': 'object',
      'additionalProperties': false,
      'properties': {
        'tasks': {
          'type': 'array',
          'minItems': 2,
          'maxItems': 10,
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
  });

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

  Future<AssistantRunResult> _ask(String prompt) async {
    _errors.clear();
    _actions.clear();
    _displays.clear();
    _lookups.clear();
    _namedTitlesCurrent = null;
    _stepIndex = 0;
    _prompt = prompt;
    _ageNotice = false;
    // The profile decides, never the prompt or the model.
    _ctx.kidsMode = await _ctx.kidsProfile?.call() ?? false;
    _ctx.recommend = AssistantRecommendConstraints.fromPrompt(prompt);
    _pickGrids.clear();
    _history.clear();
    _personal = false;
    _wanted = assistantAskedCount(prompt);
    var corrected = false;
    var callsThisRun = 0;
    if (await entitlement.check() != AssistantEntitlementState.entitled) {
      return const AssistantRunResult(end: AssistantRunEnd.notEntitled);
    }
    // Fresh roles before the first decision: the health probe re-reads the
    // Jellyfin admin flag and the Pleya Server role.
    try {
      await (refreshHealth?.call() ?? _ctx.servers.checkServerHealth()).timeout(healthRefresh);
    } on TimeoutException {
      // Offline servers simply drop out of the tool list.
    }

    final messages = <Map<String, Object?>>[
      {'role': 'system', 'content': _system},
      if (_screenNote() case final note?) {'role': 'system', 'content': note},
      if (_ctx.recommend.describe() case final note?) {'role': 'system', 'content': note},
      {'role': 'user', 'content': prompt},
    ];

    for (var step = 0; step < maxSteps; step++) {
      final available = _available();
      // Nothing to act on (no server and no serverless service such as
      // Seerr): do not spend a model call.
      if (_ctx.userServers.isEmpty && available.keys.every((t) => t.name == 'list_servers')) {
        return _end(callsThisRun > 0 && _errors.isEmpty ? AssistantRunEnd.answered : AssistantRunEnd.noTools);
      }
      final AssistantReply reply;
      try {
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        if (budget != null && !budget!.reserveModel()) {
          return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
        }
        reply = await _operation(() async {
          if (_cancelled) throw const AssistantToolError('cancelled');
          return model.chat(messages, [
            for (final e in available.entries) e.key.spec(e.value),
            if (allowSplit && step == 0) _splitSpec,
          ], abort: cancel);
        });
      } on AssistantModelException catch (e) {
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        return _end(
          e.error == AssistantModelError.toolsUnsupported
              ? AssistantRunEnd.toolsUnsupported
              : AssistantRunEnd.providerError,
          error: e.error,
        );
      } catch (e, st) {
        // Anything else from the provider path is still a provider failure,
        // not a crash of the run.
        appLogger.w('Assistant model call failed', error: e.runtimeType, stackTrace: st);
        return _end(AssistantRunEnd.providerError, error: AssistantModelError.badResponse);
      }
      // Any request for the safe route tightens this run before executing
      // siblings in the same reply. Model candidates/prose never become facts.
      if (reply.toolCalls.any((call) => call.name == 'diagnose_library')) {
        _ctx.libraryDoctorMode = true;
      }
      if (reply.toolCalls.any((call) => call.name == 'spoiler_context')) {
        _spoilerQuestion ??= prompt;
        _ctx.spoilerQuestion = _spoilerQuestion;
      }
      messages.add(reply.message);
      if (reply.toolCalls.any((call) => call.name == 'split_tasks')) {
        if (!allowSplit || step != 0) return _end(AssistantRunEnd.stepLimit, failure: 'invalid_split');
        var plans = _splitPlans(reply);
        if (plans == null) {
          // One repair turn, with only the read-only routing spec. Neither the
          // malformed reply nor its repair may execute ordinary tools.
          for (final call in reply.toolCalls) {
            messages.add({
              'role': 'tool',
              'tool_call_id': call.id,
              'content': jsonEncode({'error': 'invalid_split'}),
            });
          }
          messages.add({
            'role': 'user',
            'content':
                'Return one exclusive valid split_tasks call containing every independent command. No other tools.',
          });
          if (budget != null && !budget!.reserveModel()) {
            return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
          }
          try {
            final repair = await _operation(() async {
              if (_cancelled) throw const AssistantToolError('cancelled');
              // Repair a fenced route without echoing invented plot facts,
              // child labels, prompts or arbitrary tool-call names to the model.
              final repairMessages = _spoilerQuestion == null
                  ? messages
                  : <Map<String, Object?>>[
                      {'role': 'system', 'content': _system},
                      {'role': 'user', 'content': prompt},
                      {
                        'role': 'user',
                        'content':
                            'Return one exclusive valid split_tasks call containing every independent command. No other tools.',
                      },
                    ];
              return model.chat(repairMessages, [_splitSpec], abort: cancel);
            });
            plans = _splitPlans(repair);
          } catch (_) {
            return _end(AssistantRunEnd.stepLimit, failure: 'invalid_split');
          }
        }
        if (plans == null || _cancelled) return _end(AssistantRunEnd.stepLimit, failure: 'invalid_split');
        if (budget != null && !budget!.reserveTool()) {
          return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
        }
        if (plans.any((plan) => assistantNeedsSpoilerScope('${plan.intent} ${plan.prompt}'))) {
          _spoilerQuestion ??= prompt;
        }
        return AssistantRunResult(
          end: AssistantRunEnd.answered,
          // A child task's title is model text the age gate never sees: on a
          // children's profile it stays empty and the controller numbers it.
          splitTasks: List.unmodifiable([
            for (final plan in plans)
              _ctx.kidsMode ? AssistantTaskPlan(title: '', intent: plan.intent, prompt: plan.prompt) : plan,
          ]),
          spoilerPrompt: _spoilerQuestion,
        );
      }
      if (_spoilerQuestion != null) {
        // Enforce execution as well as advertised specs. Even an invented
        // unrestricted call or a tool-free hallucination ends with source data.
        for (final call in reply.toolCalls.take(maxCallsPerReply)) {
          if (budget != null && !budget!.reserveTool()) {
            return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
          }
          if (call.name == 'spoiler_context') {
            await _execute(call);
          } else {
            // Rejection must not publish model-invented tool names as UI labels.
            await _executeCall(call);
          }
        }
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        if (_ctx.spoilerEvidence == null) {
          if (budget != null && !budget!.reserveTool()) {
            return _end(AssistantRunEnd.stepLimit, failure: 'budget_exhausted');
          }
          await _execute(AssistantToolCall(id: 'safe-context', name: 'spoiler_context', arguments: '{}'));
        }
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        // Kids mode refuses spoiler_context: no evidence, no answer.
        final evidence = _ctx.spoilerEvidence;
        if (evidence == null) return _end(AssistantRunEnd.answered, failure: 'kids_mode_unsupported');
        return _end(AssistantRunEnd.answered, text: evidence.answer(languageName));
      }
      if (reply.toolCalls.isEmpty) {
        // An answer for children that names titles without any known age:
        // the model named them unchecked, so the ages card replaces it. An
        // answer without titles (a server status) goes through.
        if (_namesTitles(reply.content) && await _kidsAgesMissing()) {
          _askKidsAges();
          return _end(AssistantRunEnd.answered);
        }
        // One correction round when the answer names a title the age
        // filter turned down; Pleya writes that message, not the model.
        final correction = await _settleAnswer(reply.content, mayCorrect: !corrected && step + 1 < maxSteps);
        if (correction != null) {
          corrected = true;
          messages.add({'role': 'system', 'content': correction});
          continue;
        }
        // Still naming a title the age filter did not pass: Pleya's own line
        // (the controller words it), never the model's text.
        return _end(AssistantRunEnd.answered, text: _ageNotice ? '' : reply.content);
      }
      // Serial on purpose: a write must see the state the previous one left.
      for (final (index, call) in reply.toolCalls.indexed) {
        // Every call gets an answer, so the history stays valid.
        final output = index >= maxCallsPerReply || callsThisRun >= maxCallsPerRun
            ? const <String, Object?>{'error': 'too_many_calls'}
            : budget != null && !budget!.reserveTool()
            ? const <String, Object?>{'error': 'budget_exhausted'}
            : await _execute(call);
        final operationKey = _operationKey(call);
        // Missing children's ages is a question for the user (the ages card),
        // and a tool refused for children a hint to the model: neither is a
        // failed task.
        if (output['error'] case final String code when !_kidsCodes.contains(code)) {
          _errors[operationKey] = code;
        } else if (output['library_access'] == 'failed') {
          _errors[operationKey] = 'library_access_failed';
        } else if (output['status'] == 'not_confirmed' || output['status'] == 'cancelled_by_user') {
          _errors[operationKey] = output['status'] as String;
        } else {
          _errors.remove(operationKey);
        }
        callsThisRun++;
        if (output['error'] == 'kids_ages_unknown') _askKidsAges();
        messages.add({'role': 'tool', 'tool_call_id': call.id, 'content': jsonEncode(output)});
      }
    }
    return _end(AssistantRunEnd.stepLimit);
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
  final Map<AssistantMediaGrid, Set<String>> _lookups = {};
}
