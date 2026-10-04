import 'dart:async';
import 'dart:convert';

import '../exceptions/media_server_exceptions.dart';
import '../media/ids.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_age_gate.dart';
import 'assistant_entitlement.dart';
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
  const AssistantStep({required this.index, required this.tool, required this.phase, this.serverName, this.display});
  final int index;
  final String tool;
  final String? serverName;
  final AssistantStepPhase phase;

  /// What the finished call handed the UI, so it can show while the model
  /// still composes its reply. Also in [AssistantRunResult.displays].
  final AssistantDisplay? display;
}

enum AssistantRunEnd { answered, stepLimit, notEntitled, noTools, toolsUnsupported, providerError }

class AssistantRunResult {
  const AssistantRunResult({
    required this.end,
    this.text = '',
    this.actions = const [],
    this.displays = const [],
    this.providerError,
    this.ageFilterNotice = false,
  });
  final AssistantRunEnd end;

  /// The model's closing words, for display only.
  final String text;

  /// What Pleya actually did, in order. Built from validated data.
  final List<AssistantActionRecord> actions;

  /// What tools handed the UI to show (a grid of titles, a comparison).
  final List<AssistantDisplay> displays;
  final AssistantModelError? providerError;

  /// The answer still names a title the age filter turned down, after the
  /// one correction round: Pleya adds its own notice under it.
  final bool ageFilterNotice;
}

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
      return await _ask(prompt);
    } finally {
      _busy = false;
    }
  }

  Future<AssistantRunResult> _ask(String prompt) async {
    _actions.clear();
    _displays.clear();
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
      await _ctx.servers.checkServerHealth().timeout(healthRefresh);
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
        return _end(AssistantRunEnd.noTools);
      }
      final AssistantReply reply;
      try {
        if (_cancelled) return _end(AssistantRunEnd.stepLimit);
        reply = await model.chat(messages, [for (final e in available.entries) e.key.spec(e.value)], abort: cancel);
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
      messages.add(reply.message);
      if (reply.toolCalls.isEmpty) {
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
            ? const {'error': 'too_many_calls'}
            : await _execute(call);
        callsThisRun++;
        if (output['error'] == 'kids_ages_unknown') _askKidsAges();
        messages.add({'role': 'tool', 'tool_call_id': call.id, 'content': jsonEncode(output)});
      }
    }
    return _end(AssistantRunEnd.stepLimit);
  }

  AssistantRunResult _end(AssistantRunEnd end, {String text = '', AssistantModelError? error}) => AssistantRunResult(
    end: end,
    text: text,
    actions: List.unmodifiable(_actions),
    displays: List.unmodifiable(_displays),
    providerError: error,
    ageFilterNotice: _ageNotice,
  );

  /// Stand-in id for asking a serverless tool whether it serves at all, so a
  /// profile with Seerr but no media server still gets its request tools.
  static final _noServer = ServerId('none');

  /// Each tool with the servers it may act on right now.
  Map<AssistantTool, List<String>> _available() {
    // Each tool decides through `serves` whether it needs administration.
    final servers = _ctx.userServers;
    return {
      for (final tool in tools ?? assistantTools)
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
    final display = _displays.length > shown ? _displays.last : null;
    final failed =
        output.containsKey('error') || output['status'] == 'cancelled_by_user' || output['status'] == 'not_confirmed';
    onStep?.call(
      AssistantStep(
        index: index,
        tool: call.name,
        serverName: serverName,
        phase: failed ? AssistantStepPhase.failed : AssistantStepPhase.done,
        display: display,
      ),
    );
    return output;
  }

  Future<Map<String, Object?>> _executeCall(AssistantToolCall call) async {
    // Recomputed per call: the list the model saw may be one call stale.
    final available = _available();
    final tool = available.keys.where((t) => t.name == call.name).firstOrNull;
    if (tool == null) return {'error': 'unknown_tool'};
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
      final outcome = await tool.run(_ctx, serverId, args);
      switch (outcome) {
        case AssistantToolResult(:final data, :final record, :final display):
          if (record != null) {
            _actions.add(record);
            // Only an action ends a lookup: a read with that item_id does not.
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
          if (!output.containsKey('error') &&
              output['status'] != 'cancelled_by_user' &&
              output['status'] != 'not_confirmed') {
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

  Future<Map<String, Object?>> _confirmAndRun(AssistantTool tool, AssistantPendingAction action) async {
    final AssistantConfirmation? answer;
    try {
      answer = await confirm(action).timeout(confirmTimeout);
    } on TimeoutException {
      return {'status': 'not_confirmed'};
    }
    if (answer == null) return {'status': 'cancelled_by_user'};
    // The card may have been open for a while: entitlement and authority are
    // checked again, against the state of this moment.
    if (await entitlement.check() != AssistantEntitlementState.entitled) return {'error': 'not_entitled'};
    if (!tool.serves(_ctx, action.serverId)) return {'error': 'not_allowed'};
    if (_cancelled) return {'status': 'cancelled_by_user'};
    final result = await action.execute(password: answer.password);
    // A confirmed action that changed nothing (`done: false`) is not shown
    // as done.
    if (result['done'] != false && !result.containsKey('error')) _actions.add(action.record);
    return result;
  }
}
