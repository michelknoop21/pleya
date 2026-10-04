import 'assistant_spoiler_context.dart';
import 'dart:async';
import 'dart:convert';

import '../exceptions/media_server_exceptions.dart';
import '../media/ids.dart';
import '../media/media_kind.dart';
import '../services/unified_catalog/home_custom_row_loader.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_age_gate.dart';
import 'assistant_entitlement.dart';
import 'assistant_execution.dart';
import 'assistant_named_titles.dart';
import 'assistant_provider.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';

part 'assistant_run_answer.dart';
part 'assistant_run_prompt.dart';

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

  /// The answer still names a title the age filter turned down, after the
  /// one correction round: Pleya adds its own notice under it.
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
    _ctx.kidsMode = AgeGate.kidsIntent(prompt);
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
      // A for_kids call anywhere in the reply makes the whole ask one for
      // children before any sibling runs.
      if (reply.toolCalls.any(_asksForKids)) _ctx.kidsMode = true;
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
          splitTasks: List.unmodifiable(plans),
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
        // An answer for children without any known age: the model named its
        // titles unchecked, so the ages card replaces it.
        if (await _kidsAgesMissing()) {
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
        return _end(AssistantRunEnd.answered, text: reply.content);
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

  AssistantRunResult _end(AssistantRunEnd end, {String text = '', AssistantModelError? error, String? failure}) {
    final evidenceContext = _ctx;
    final namedTitlesCurrent = _namedTitlesCurrent;
    bool displaysCurrent() => evidenceContext.recommendationError == null && (namedTitlesCurrent?.call() ?? true);
    if (_ctx.libraryDoctorError case final doctorError?) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: doctorError,
        libraryDoctorError: () => evidenceContext.libraryDoctorError,
      );
    }
    if (!_ctx.playbackEvidenceCurrent) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: 'playback_session_changed',
        playbackEvidenceCurrent: () => false,
        displayEvidenceCurrent: displaysCurrent,
        spoilerPrompt: _spoilerQuestion,
      );
    }
    if (evidenceContext.recommendationError case final recommendationError?) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        error: recommendationError,
        displayEvidenceCurrent: displaysCurrent,
      );
    }
    final agesFirst = _displays.whereType<AssistantKidsAgesPrompt>().firstOrNull;
    if (agesFirst != null) {
      return AssistantRunResult(
        end: end,
        actions: List.unmodifiable(_actions),
        displays: [agesFirst],
        kidsAgesNeeded: true,
        spoilerPrompt: _spoilerQuestion,
        playbackEvidenceCurrent: () => evidenceContext.playbackEvidenceCurrent,
        libraryDoctorError: () => evidenceContext.libraryDoctorError,
        providerError: error,
        error: failure,
      );
    }
    return AssistantRunResult(
      end: end,
      text: _ctx.libraryDoctorMode
          ? _ctx.libraryDoctorAnswer?.call(languageName) ??
                (languageName == 'Dutch'
                    ? 'Geen gecontroleerde bibliotheekgegevens; de diagnose blijft onbekend.'
                    : 'No checked library evidence; the diagnosis remains unknown.')
          : text,
      libraryDoctorError: () => evidenceContext.libraryDoctorError,
      spoilerPrompt: _spoilerQuestion,
      playbackEvidenceCurrent: () => evidenceContext.playbackEvidenceCurrent,
      actions: List.unmodifiable(_actions),
      displays: displaysCurrent() ? List.unmodifiable(_displays) : const [],
      displayEvidenceCurrent: displaysCurrent,
      providerError: error,
      ageFilterNotice: _ageNotice,
      error:
          failure ??
          _errors.values.where((code) => code != 'cancelled_by_user').firstOrNull ??
          _errors.values.firstOrNull,
    );
  }

  String _operationKey(AssistantToolCall call) {
    Object? sorted(Object? value) => switch (value) {
      final Map<String, Object?> map => {for (final key in map.keys.toList()..sort()) key: sorted(map[key])},
      final List list => list.map(sorted).toList(),
      _ => value,
    };
    try {
      return '${call.name}:${jsonEncode(sorted(jsonDecode(call.arguments.isEmpty ? '{}' : call.arguments)))}';
    } on FormatException {
      return '${call.name}:${call.arguments}';
    }
  }

  List<AssistantTaskPlan>? _splitPlans(AssistantReply reply) {
    if (reply.toolCalls.length != 1 || reply.toolCalls.single.name != 'split_tasks') return null;
    try {
      final decoded = jsonDecode(reply.toolCalls.single.arguments);
      if (decoded is! Map || decoded.length != 1 || decoded['tasks'] is! List) return null;
      final tasks = decoded['tasks'] as List;
      if (tasks.length < 2 || tasks.length > 10) return null;
      final result = <AssistantTaskPlan>[];
      for (final task in tasks) {
        if (task is! Map || task.length != 3) return null;
        for (final key in ['title', 'intent', 'prompt']) {
          if (task[key] is! String || (task[key] as String).trim().isEmpty || (task[key] as String).length > 4000) {
            return null;
          }
        }
        result.add(
          AssistantTaskPlan(
            title: clipText(task['title'] as String, 120),
            intent: clipText(task['intent'] as String, 80),
            prompt: (task['prompt'] as String).trim(),
          ),
        );
      }
      return result;
    } on FormatException {
      return null;
    }
  }

  /// Stand-in id for asking a serverless tool whether it serves at all, so a
  /// profile with Seerr but no media server still gets its request tools.
  static final _noServer = ServerId('none');

  /// Each tool with the servers it may act on right now.
  Map<AssistantTool, List<String>> _available() {
    // Each tool decides through `serves` whether it needs administration.
    final servers = _ctx.userServers;
    return {
      for (final tool in _spoilerQuestion != null ? [assistantSpoilerTool] : tools ?? assistantTools)
        if ((!_ctx.libraryDoctorMode || tool.name != 'my_watching') &&
            (!_ctx.libraryDoctorMode ||
                tool.risk == AssistantToolRisk.read ||
                (const {'scan_library', 'refresh_metadata'}.contains(tool.name) &&
                    _ctx.libraryDoctorActions.contains(tool.name))))
          // A serverless tool still asks `serves`: a missing service (no Seerr)
          // keeps it out.
          if (!tool.needsServer && [...servers, _noServer].any((id) => tool.serves(_ctx, id)))
            tool: const <String>[]
          else if (!tool.needsServer)
            ...const <AssistantTool, List<String>>{}
          else if ([
                for (final id in servers)
                  if (tool.serves(_ctx, id)) id.value,
              ]
              case final ids when ids.isNotEmpty)
            tool: ids,
    };
  }

  int _stepIndex = 0;

  /// The ask in progress, for the ages card that submits it again.
  String _prompt = '';
  bool _ageNotice = false;

  /// Read by [_end]: the named-title cards are only shown while the sources
  /// they came from are still current.
  bool Function()? _namedTitlesCurrent;

  /// find_media grids whose titles a later call acted on: a lookup on the way
  /// to an action, so the action is the result, not the grid.
  final Map<AssistantMediaGrid, Set<String>> _lookups = {};

  void _consumeLookups(Map<String, Object?> args) {
    final item = args['item_id'];
    if (item is! String) return;
    _lookups.removeWhere((grid, ids) {
      if (!ids.contains(item)) return false;
      _displays.remove(grid);
      return true;
    });
  }

  Future<Map<String, Object?>> _execute(AssistantToolCall call) async {
    if (_cancelled) return {'error': 'cancelled'};
    final index = _stepIndex++;
    String? serverName;
    try {
      final args = jsonDecode(call.arguments.isEmpty ? '{}' : call.arguments);
      final id = args is Map
          ? ServerId.tryParse(args['server_id'] is String ? args['server_id'] as String : null)
          : null;
      // Only a server this run may use gets named; anything else stays blank.
      if (id != null && _ctx.userServers.contains(id)) serverName = _ctx.serverName(id);
    } on FormatException {
      // The call itself reports invalid_arguments.
    }
    onStep?.call(
      AssistantStep(index: index, tool: call.name, serverName: serverName, phase: AssistantStepPhase.started),
    );
    final shown = _displays.length;
    final output = await _executeCall(call);
    final evidenceContext = _ctx;
    if (evidenceContext.recommendationError case final recommendationError?) return {'error': recommendationError};
    if (_ctx.libraryDoctorError case final doctorError?) return {'error': doctorError};
    // Tool preparation and parent await each introduce a publication gap.
    // Never emit a payload whose source lease closed during either gap.
    if (_spoilerQuestion != null && (!_ctx.playbackEvidenceCurrent || _cancelled)) {
      return {'error': 'playback_session_changed'};
    }
    final display = _displays.length > shown ? _displays.last : null;
    final failed =
        output.containsKey('error') ||
        output['library_access'] == 'failed' ||
        output['status'] == 'cancelled_by_user' ||
        output['status'] == 'not_confirmed';
    onStep?.call(
      AssistantStep(
        index: index,
        tool: call.name,
        serverName: serverName,
        phase: failed ? AssistantStepPhase.failed : AssistantStepPhase.done,
        display: display,
        evidenceCurrent: evidenceContext.recommendationCheck != null
            ? () =>
                  evidenceContext.recommendationError == null &&
                  evidenceContext.libraryDoctorError == null &&
                  evidenceContext.playbackEvidenceCurrent
            : _ctx.libraryDoctorMode
            ? () => _ctx.libraryDoctorError == null
            : _ctx.spoilerEvidence?.position == null
            ? null
            : _ctx.spoilerEvidence!.current,
      ),
    );
    return output;
  }

  Future<Map<String, Object?>> _executeCall(AssistantToolCall call) async {
    // Recomputed per call: the list the model saw may be one call stale.
    final available = _available();
    final tool = available.keys.where((t) => t.name == call.name).firstOrNull;
    if (tool == null) return {'error': 'unknown_tool'};
    // The whole ask picks for children: a tool whose titles skip the age
    // gate is refused, whatever arguments the model sent.
    if (_ctx.kidsFilter && _ctx.kidsMode && kidsToolPolicy[tool.name] == KidsTool.blocked) {
      return assistantKidsRefusal;
    }
    final Map<String, Object?> args;
    try {
      final decoded = jsonDecode(call.arguments.isEmpty ? '{}' : call.arguments);
      if (decoded is! Map<String, Object?>) return {'error': 'invalid_arguments'};
      args = decoded;
    } on FormatException {
      return {'error': 'invalid_arguments'};
    }
    ServerId? serverId;
    if (tool.needsServer) {
      serverId = ServerId.tryParse(args['server_id'] is String ? args['server_id'] as String : null);
      if (serverId == null || !available[tool]!.contains(serverId.value)) return {'error': 'server_not_available'};
    }

    try {
      Future<AssistantToolOutcome> prepare() => _operation(() async {
        if (_cancelled) throw const AssistantToolError('cancelled');
        if (tool.risk != AssistantToolRisk.read) {
          if (await entitlement.check() != AssistantEntitlementState.entitled) {
            throw const AssistantToolError('not_entitled');
          }
          if (_cancelled) throw const AssistantToolError('cancelled');
          if (!tool.serves(_ctx, serverId ?? _noServer)) throw const AssistantToolError('not_allowed');
        }
        return tool.run(_ctx, serverId, args);
      });
      // Immediate mutation tools execute inside their run callback. Sensitive
      // tools only prepare the card here; their execute callback locks later.
      final outcome = tool.risk == AssistantToolRisk.mutation && mutations != null
          ? await mutations!.run(prepare)
          : await prepare();
      switch (outcome) {
        case AssistantToolResult(:final data, :final record, :final display):
          if (_ctx.recommendationError case final recommendationError?) return {'error': recommendationError};
          if (_ctx.libraryDoctorError case final doctorError?) return {'error': doctorError};
          if (_spoilerQuestion != null && (!_ctx.playbackEvidenceCurrent || _cancelled)) {
            return {'error': 'playback_session_changed'};
          }
          if (record != null && _actionSucceeded(data)) {
            _actions.add(record);
            _consumeLookups(args);
          }
          if (display != null) _displays.add(display);
          if (tool.name == 'find_media' && display is AssistantMediaGrid) {
            _lookups[display] = {for (final e in display.entries) e.item.id};
          }
          return data;
        case final AssistantPendingAction action:
          final output = await _confirmAndRun(tool, action);
          // A declined or failed action leaves the lookup as the result.
          if (_actionSucceeded(output)) {
            _consumeLookups(args);
          }
          return output;
      }
    } on AssistantToolError catch (e) {
      return {'error': e.code};
    } on MediaServerAuthException {
      return {'error': 'not_allowed'};
    } on ArgumentError {
      return {'error': 'invalid_arguments'};
    } catch (e, st) {
      appLogger.w('Assistant tool ${tool.name} failed', error: e, stackTrace: st);
      return {'error': 'failed'};
    }
  }

  bool _actionSucceeded(Map<String, Object?> data) =>
      data['done'] != false &&
      !data.containsKey('error') &&
      data['status'] != 'cancelled_by_user' &&
      data['status'] != 'not_confirmed';

  Future<Map<String, Object?>> _confirmAndRun(AssistantTool tool, AssistantPendingAction action) async {
    final AssistantConfirmation? answer;
    try {
      final pending = confirm(action);
      answer = await (controllerOwnsConfirmTimeout ? pending : pending.timeout(confirmTimeout));
    } on TimeoutException {
      return {'status': 'not_confirmed'};
    }
    if (answer == null) return {'status': 'cancelled_by_user'};
    Future<Map<String, Object?>> execute() => _operation(() async {
      if (_cancelled) return {'status': 'cancelled_by_user'};
      if (await entitlement.check() != AssistantEntitlementState.entitled) return {'error': 'not_entitled'};
      if (_cancelled) return {'status': 'cancelled_by_user'};
      if (!tool.serves(_ctx, action.serverId)) return {'error': 'not_allowed'};
      return action.execute(password: answer?.password);
    });
    final result = mutations == null ? await execute() : await mutations!.run(execute);
    // A confirmed action that changed nothing (`done: false`) is not shown
    // as done.
    if (_actionSucceeded(result)) {
      _actions.add(action.record);
    }
    return result;
  }
}
