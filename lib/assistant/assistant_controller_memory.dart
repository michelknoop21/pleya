part of 'assistant_controller.dart';

// The memory cards of a conversation: what a run proposed, and the user's
// answer on the card. The model never writes here; a yes does, through
// [applyMemoryProposal].

extension _AssistantMemoryCards on AssistantController {
  AssistantMemoryProposal? get _memoryProposal =>
      state == AssistantSurfaceState.result ? _tasks.expand((task) => task.memoryProposals).firstOrNull : null;

  AssistantMemoryOutcome? get _memoryOutcome => _tasks.map((task) => task.memoryOutcome).nonNulls.lastOrNull;

  bool get _memoryStored => _tasks.any((task) => task.memoryStored);

  /// Takes the memory part of [result] onto [task]: the proposals become
  /// cards only under a finished answer, and a fact stored at once is always
  /// reported, also when the rest of the answer was withdrawn.
  void _settleMemory(_AssistantTaskState task, AssistantRunResult result) {
    if (result.memoryStored.isNotEmpty) {
      task.memoryStored = true;
      if (task.answer.isEmpty) task.answer = assistantMemoryAnswer(result, '');
    }
    if (result.end == AssistantRunEnd.answered) task.memoryProposals.addAll(result.memoryProposals);
  }

  Future<void> _answerMemoryProposal(AssistantMemoryProposal proposal, {required bool accept}) async {
    final task = _tasks.where((task) => task.memoryProposals.any((p) => identical(p, proposal))).firstOrNull;
    if (task == null || _disposed) return;
    // The card goes first, so a second press finds nothing to answer.
    task.memoryProposals.removeWhere((p) => identical(p, proposal));
    _update();
    if (!accept) return;
    AssistantMemoryOutcome outcome;
    try {
      outcome = await _entitlement.check() == AssistantEntitlementState.entitled
          ? await applyMemoryProposal(proposal)
          : AssistantMemoryOutcome(proposal.kind, 'not_entitled');
    } catch (e) {
      appLogger.w('Assistant memory card failed: ${e.runtimeType}');
      outcome = AssistantMemoryOutcome(proposal.kind, 'failed');
    }
    if (_disposed || !_tasks.contains(task)) return;
    task.memoryOutcome = outcome;
    if (outcome.ok && proposal.kind != AssistantMemoryProposalKind.forget) task.memoryStored = true;
    // Pleya's own line under the answer, on every surface that shows it.
    task.answer = [task.answer, assistantMemoryOutcomeLine(outcome)].where((line) => line.isNotEmpty).join('\n');
    _update();
  }
}
