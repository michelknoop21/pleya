part of 'assistant_run.dart';

// One tool call from the model's request to its output: validation,
// authority, confirmation where needed, and execution.

extension _AssistantExecute on AssistantRun {
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
          if (!tool.needsServer && [...servers, AssistantRun._noServer].any((id) => tool.serves(_ctx, id)))
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

  void _consumeLookups(Map<String, Object?> args, ServerId? server) {
    final item = args['item_id'];
    if (item is! String) return;
    _lookups.removeWhere((grid, ids) {
      // A side without a server (a tool that takes none, an item that
      // names none) cannot tell servers apart and matches on the id alone.
      if (!ids.any((e) => e.$2 == item && (server == null || e.$1 == null || e.$1 == server.value))) return false;
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
    // A children's profile: a tool whose titles skip the age gate is
    // refused, whatever arguments the model sent.
    if (_ctx.kidsMode && kidsToolPolicy[tool.name] == KidsTool.blocked) {
      return assistantKidsRefusal;
    }
    final Map<String, Object?> args;
    try {
      final decoded = jsonDecode(call.arguments.isEmpty ? '{}' : call.arguments);
      if (decoded is! Map<String, Object?>) return {'error': 'invalid_arguments'};
      // What the user said overrules what the model chose; a tool that does not
      // fit the question is refused, so the model cannot widen the audience.
      final fixed = _intent.constrain(tool.name, decoded);
      if (fixed.error case final code?) return {'error': code};
      args = fixed.args;
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
          if (!tool.serves(_ctx, serverId ?? AssistantRun._noServer)) throw const AssistantToolError('not_allowed');
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
            _consumeLookups(args, serverId);
          }
          final shown = display == null ? null : _ctx.recommend.admit(display);
          if (shown != null) _displays.add(shown);
          if (tool.name == 'my_watching') {
            _personal = true;
            if (shown is AssistantMediaGrid) _pickGrids.add(shown);
            for (final w in (data['watched_recently'] as List?) ?? const []) {
              _history.add(assistantTitleKey((w as Map)['title'] as String));
            }
          }
          if (tool.name == 'find_media' && shown is AssistantMediaGrid) {
            _lookups[shown] = {for (final e in shown.entries) (e.item.serverId, e.item.id)};
          }
          return data;
        case final AssistantPendingAction action:
          final output = await _confirmAndRun(tool, action);
          // A declined or failed action leaves the lookup as the result.
          if (_actionSucceeded(output)) {
            _consumeLookups(args, action.serverId);
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
