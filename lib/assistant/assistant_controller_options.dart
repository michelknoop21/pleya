part of 'assistant_controller.dart';

// Pleya's own cards: the confirmation queue, and an option the user picked.

extension _AssistantConfirming on AssistantController {
  Future<AssistantConfirmation?> _confirm(AssistantPendingAction action, _AssistantTaskState task) {
    if (!_alive(task)) return Future.value(null);
    final entry = _QueuedConfirmation(id: 'confirmation-${++_nextConfirmation}', task: task, action: action);
    _confirmations.add(entry);
    task.pending = action;
    task.status = AssistantTaskStatus.waitingForConfirmation;
    _showNextConfirmation();
    _update();
    return entry.completer.future;
  }

  void _showNextConfirmation() {
    final entry = _confirmations.firstOrNull;
    _pending = entry?.action;
    if (entry == null || entry.timer != null) return;
    entry.timer = Timer(confirmTimeout, () => _finishConfirmation(entry, null, timedOut: true));
  }

  void _finishConfirmation(_QueuedConfirmation entry, AssistantConfirmation? answer, {bool timedOut = false}) {
    if (!_confirmations.remove(entry)) return;
    entry.timer?.cancel();
    if (_alive(entry.task)) {
      entry.task.pending = null;
      entry.task.status = AssistantTaskStatus.running;
    }
    if (!entry.completer.isCompleted) {
      timedOut
          ? entry.completer.completeError(TimeoutException('Confirmation expired'))
          : entry.completer.complete(answer);
    }
    _showNextConfirmation();
    _update();
  }
}

extension _AssistantOptionPicking on AssistantController {
  AssistantToolContext? _optionContext(_AssistantTaskState task, AssistantRequestOption option) => task.displays
      .map(
        (display) => switch (display) {
          AssistantRequestOptions(:final context, :final options) when options.any((o) => identical(o, option)) =>
            context,
          AssistantTitleMatches(:final context, :final matches) when matches.any((m) => identical(m.request, option)) =>
            context,
          _ => null,
        },
      )
      .nonNulls
      .firstOrNull;

  /// Body of [AssistantController.pickTaskRequestOption].
  Future<void> _pickTaskRequestOption(String taskId, AssistantRequestOption option, {bool fourK = false}) async {
    final task = _tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null ||
        !_alive(task) ||
        (task.status != AssistantTaskStatus.completed && task.status != AssistantTaskStatus.failed)) {
      return;
    }
    final ctx = _optionContext(task, option);
    if (ctx == null) return;
    task.status = AssistantTaskStatus.running;
    _update();
    String? failure;
    try {
      if (!task.budget.reserveTool()) throw const AssistantToolError('budget_exhausted');
      final outcome = await _operations.run(() async {
        if (!_alive(task)) throw const AssistantToolError('cancelled');
        return assistantRequestFromOption(ctx, option.seerrId, fourK: fourK);
      });
      if (!_alive(task)) return;
      switch (outcome) {
        case AssistantToolResult(:final data, :final display):
          failure = data['error'] as String?;
          if (display != null) task.displays.add(display);
        case final AssistantPendingAction action:
          final AssistantConfirmation? answer;
          try {
            answer = await _confirm(action, task);
          } on TimeoutException {
            failure = 'not_confirmed';
            break;
          }
          if (answer == null) {
            failure = 'cancelled_by_user';
            break;
          }
          final result = await _mutations.run(
            () => _operations.run(() async {
              if (!_alive(task)) return <String, Object?>{'error': 'cancelled'};
              if (await _entitlement.check() != AssistantEntitlementState.entitled) {
                return <String, Object?>{'error': 'not_entitled'};
              }
              if (!_alive(task)) return <String, Object?>{'error': 'cancelled'};
              final tool = (_tools ?? assistantTools).where((t) => t.name == 'request_title').firstOrNull;
              if (tool == null || !tool.serves(ctx, action.serverId)) return <String, Object?>{'error': 'not_allowed'};
              return action.execute(password: answer?.password);
            }),
          );
          if (!_alive(task)) return;
          failure = result['error'] as String?;
          if (failure == null && result['done'] != false) task.actions.add(action.record);
      }
    } on AssistantToolError catch (e) {
      failure = e.code;
    } catch (e, st) {
      appLogger.w('Assistant request option failed', error: e.runtimeType, stackTrace: st);
      failure = 'failed';
    } finally {
      if (_alive(task)) {
        task.error = failure;
        task.status = _outcomeStatus(failure);
        _update();
      }
    }
  }
}

class _QueuedConfirmation {
  _QueuedConfirmation({required this.id, required this.task, required this.action});
  final String id;
  final _AssistantTaskState task;
  final AssistantPendingAction action;
  final Completer<AssistantConfirmation?> completer = Completer();
  Timer? timer;
  AssistantTaskConfirmation get view => AssistantTaskConfirmation(id: id, taskId: task.id, action: action);
}
