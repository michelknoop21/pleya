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
    if (_memoryCarry.isNotEmpty) {
      // What a superseded question stored is said with the next answer.
      task.memoryStored = true;
      task.answer = [..._memoryCarry, task.answer].where((line) => line.isNotEmpty).join('\n');
      _memoryCarry.clear();
    }
    if (result.end == AssistantRunEnd.answered) task.memoryProposals.addAll(result.memoryProposals);
  }

  /// The run of [task] ended after the task was cancelled or superseded. A
  /// fact it stored at once is still reported: on the task when it is still
  /// on screen, with the next answer when a new question took over, and as an
  /// answer of its own after "Nieuw gesprek".
  void _carryMemory(_AssistantTaskState task, AssistantRunResult result) {
    if (_disposed || result.memoryStored.isEmpty) return;
    final line = assistantMemoryAnswer(result, '');
    if (_tasks.contains(task)) {
      task.answer = line;
      task.memoryStored = true;
      _update();
      return;
    }
    _memoryCarry.add(line);
    if (_tasks.isNotEmpty || _state != AssistantSurfaceState.idle) return;
    final shown =
        _newTask(
            title: task.title,
            intent: task.intent,
            prompt: task.prompt,
            generation: _generation,
            budget: AssistantQuestionBudget(),
          )
          ..status = AssistantTaskStatus.completed
          ..memoryStored = true
          ..answer = _memoryCarry.join('\n');
    _memoryCarry.clear();
    _prompt = task.prompt;
    _tasks.add(shown);
    _update();
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

/// The memory cards against the profile as it is now.
extension AssistantMemoryCardGuard on AssistantController {
  /// Takes every waiting memory card away when the profile became a
  /// children's profile: Big P uses no memory there. Called when the switch
  /// in Instellingen changes.
  Future<void> recheckMemoryCards() async {
    final waiting = [for (final task in _tasks) ...task.memoryProposals];
    if (waiting.isEmpty || !await waiting.first.memory.kidsNow || _disposed) return;
    for (final task in _tasks) {
      task.memoryProposals.clear();
    }
    _update();
  }
}
