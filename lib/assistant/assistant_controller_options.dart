part of 'assistant_controller.dart';

// Pleya's own cards: a confirmation, and an option the user picked.

extension _AssistantConfirming on AssistantController {
  /// The run's confirm callback: shows [action] through [pending] until the
  /// user answers, [reset] runs, or [confirmTimeout] passes.
  Future<AssistantConfirmation?> _confirm(AssistantPendingAction action, int generation) async {
    if (generation != _generation || _disposed) return null;
    final completer = Completer<AssistantConfirmation?>();
    _pending = action;
    _confirmer = completer;
    _notify();
    try {
      // A TimeoutException reaches the run, which reports `not_confirmed`.
      return await completer.future.timeout(confirmTimeout);
    } finally {
      if (identical(_confirmer, completer)) {
        _pending = null;
        _confirmer = null;
        _notify();
      }
    }
  }

  void _answerPending(AssistantConfirmation? answer) {
    final completer = _confirmer;
    if (completer == null || completer.isCompleted) return;
    completer.complete(answer);
  }
}

extension _AssistantOptionPicking on AssistantController {
  /// Body of [AssistantController.pickRequestOption].
  Future<void> _pickRequestOption(AssistantRequestOption option, {bool fourK = false}) async {
    if (_busy) return;
    // Option cards and found titles both carry a Seerr request.
    final ctx = _displays
        .map(
          (d) => switch (d) {
            AssistantRequestOptions(:final context, :final options)
                when options.any((o) => o.seerrId == option.seerrId) =>
              context,
            AssistantTitleMatches(:final context, :final matches)
                when matches.any((m) => m.request?.seerrId == option.seerrId) =>
              context,
            _ => null,
          },
        )
        .nonNulls
        .firstOrNull;
    if (ctx == null) return;
    _busy = true;
    final generation = _generation;
    _state = AssistantSurfaceState.working;
    _notify();
    var failed = true;
    try {
      final outcome = await assistantRequestFromOption(ctx, option.seerrId, fourK: fourK);
      if (generation != _generation) return;
      switch (outcome) {
        case AssistantToolResult(:final data):
          failed = data.containsKey('error');
        case final AssistantPendingAction action:
          final AssistantConfirmation? answer;
          try {
            answer = await _confirm(action, generation);
          } on TimeoutException {
            return;
          }
          if (answer == null || generation != _generation) {
            failed = false;
            return;
          }
          if (await _entitlement.check() != AssistantEntitlementState.entitled) return;
          final tool = (_tools ?? assistantTools).where((t) => t.name == 'request_title').firstOrNull;
          if (tool == null || !tool.serves(ctx, action.serverId)) return;
          // The entitlement check awaited: a reset or profile switch since
          // the confirmation must not still create the request.
          if (generation != _generation || _disposed) return;
          final result = await action.execute(password: answer.password);
          if (generation != _generation) return;
          failed = result.containsKey('error');
          if (!failed && result['done'] != false) _actions.add(action.record);
      }
    } catch (e, st) {
      // Seerr refused, or the client changed under the card.
      appLogger.w('Assistant request option failed', error: e.runtimeType, stackTrace: st);
    } finally {
      if (generation == _generation) {
        _busy = false;
        _resultIsError = failed;
        _state = AssistantSurfaceState.result;
      }
      _notify();
    }
  }
}
