part of 'assistant_controller.dart';

// One command from submit to its settled result: the run, a split into
// child tasks, and what the task shows afterwards.

extension _AssistantTaskRunning on AssistantController {
  Future<void> _runTask(
    _AssistantTaskState task,
    AssistantProviderConfig config,
    Future<void> Function() refreshHealth, {
    bool allowSplit = false,
    bool libraryDoctorScope = false,
  }) async {
    AssistantModelClient? model;
    try {
      if (!_alive(task)) return;
      // A question about two audiences at once is cut in code, before the
      // model can answer only one half of it.
      // Not on a follow-up that points back ("daarvan" would lose its referent),
      // a library-doctor question or a children's profile (whose ages card
      // resubmits one clause). The cut is computed first so the profile read is
      // only paid for a question that would be cut.
      final parts =
          allowSplit &&
              task.originalSpoilerPrompt == null &&
              !(_conversation.isNotEmpty && AssistantIntent.refersBack(task.prompt)) &&
              !libraryDoctorScope &&
              !assistantNeedsLibraryDoctorScope(task.prompt)
          ? AssistantIntent.splitMixedAudience(task.prompt)
          : null;
      if (parts != null) {
        final kids = await _buildContext(_screenContext).kidsProfile?.call() ?? false;
        // The question may have been superseded or cancelled while the profile was read.
        if (!_alive(task)) return;
        if (!kids) {
          final children = [
            for (final part in parts)
              _newTask(
                title: clipText(part, 80),
                intent: 'command',
                prompt: part,
                parentIntent: AssistantIntent.fromPrompt(task.prompt),
                generation: task.generation,
                budget: task.budget,
              ),
          ];
          _tasks
            ..remove(task)
            ..addAll(children);
          _update();
          final doctorScope = libraryDoctorScope || assistantNeedsLibraryDoctorScope(task.prompt);
          await Future.wait([
            for (final child in children) _runTask(child, config, refreshHealth, libraryDoctorScope: doctorScope),
          ]);
          return;
        }
      }
      task.status = AssistantTaskStatus.running;
      _update();
      model = _modelFor(config);
      final run = AssistantRun(
        model: model,
        context: _buildContext(_screenContext).fresh(web: config.webSearch ? _webFor?.call(config) : null),
        confirm: (action) => _confirm(action, task),
        entitlement: _entitlement,
        tools: _tools,
        languageName: _languageName(),
        confirmTimeout: confirmTimeout,
        controllerOwnsConfirmTimeout: true,
        cancel: task.cancel,
        allowSplit: allowSplit,
        originalSpoilerPrompt: task.originalSpoilerPrompt,
        originalLibraryDoctorScope: libraryDoctorScope,
        inheritedIntent: task.parentIntent,
        // Sampled at both ends of a read as well as on every server change:
        // a change nobody announced still moves it, and so does the way back.
        rightsEpoch: () {
          _noteRights(_buildContext(null));
          return _rightsEpoch;
        },
        // Only the question itself follows on; a split child is standalone.
        conversation: allowSplit ? List.of(_conversation) : const [],
        budget: task.budget,
        operations: _operations,
        mutations: _mutations,
        refreshHealth: refreshHealth,
        onStep: (step) {
          if (!_alive(task) || !(step.evidenceCurrent?.call() ?? true)) return;
          final at = task.steps.indexWhere((s) => s.index == step.index);
          at < 0 ? task.steps.add(step) : task.steps[at] = step;
          if (step.display case final display?) task.displays.add(display);
          _update();
        },
      );
      final result = await run.ask(task.prompt);
      if (!_alive(task)) return;
      if (result.splitTasks.isNotEmpty) {
        final inheritedSpoilerPrompt = task.originalSpoilerPrompt ?? result.spoilerPrompt;
        final children = [
          for (final (i, plan) in result.splitTasks.indexed)
            _newTask(
              // A fenced parent cannot delegate an unrestricted task or show
              // model-invented narrative labels. Conservative whole-question scope.
              // An empty title is a children's profile's: Pleya numbers it.
              title: inheritedSpoilerPrompt ?? (plan.title.isEmpty ? t.assistant.tasks.numbered(n: i + 1) : plan.title),
              intent: inheritedSpoilerPrompt == null ? plan.intent : 'spoiler_context',
              prompt: inheritedSpoilerPrompt ?? plan.prompt,
              originalSpoilerPrompt: inheritedSpoilerPrompt,
              parentIntent: result.intent,
              generation: task.generation,
              budget: task.budget,
            ),
        ];
        _tasks
          ..remove(task)
          ..addAll(children);
        _update();
        final doctorScope = libraryDoctorScope || assistantNeedsLibraryDoctorScope(task.prompt);
        await Future.wait([
          for (final child in children) _runTask(child, config, refreshHealth, libraryDoctorScope: doctorScope),
        ]);
        return;
      }
      task.lastEnd = result.end;
      task.providerError = result.providerError;
      task.modelMissing = result.end == AssistantRunEnd.providerError && model.modelMissing;
      final playbackCurrent = result.playbackEvidenceCurrent?.call() ?? true;
      final doctorError = result.libraryDoctorError?.call();
      final displayCurrent = result.displayEvidenceCurrent?.call() ?? true;
      if (doctorError != null || !displayCurrent) {
        task.displays.clear();
        task.steps.clear();
      }
      if (!playbackCurrent && (task.originalSpoilerPrompt != null || result.spoilerPrompt != null)) {
        // Only this current task: streamed evidence must disappear when its
        // final lease closes. Other tasks/generations retain their results.
        task.displays.clear();
        task.steps.clear();
      }
      task.error =
          doctorError ??
          (!displayCurrent ? 'catalog_changed' : null) ??
          (playbackCurrent
              ? result.error ?? (result.end == AssistantRunEnd.answered ? null : result.end.name)
              : 'playback_session_changed');
      // Pleya's own words, never the model's: the answer kept naming a
      // title the age filter did not pass.
      final text = result.kidsAgesNeeded
          ? t.assistant.kids.agesFirst
          : result.ageFilterNotice
          ? t.assistant.kids.noFit
          : result.text;
      task.answer = playbackCurrent && doctorError == null && displayCurrent ? text : '';
      task.ageFilterNotice = result.ageFilterNotice && !result.kidsAgesNeeded;
      task.actions.addAll(result.actions);
      if (playbackCurrent && doctorError == null && displayCurrent) {
        task.displays
          ..clear()
          ..addAll(result.displays);
      }
      if (task.actions.any((action) => action.job != null)) unawaited(_watchJobs(task));
      task.status = _outcomeStatus(task.error);
      if (allowSplit && task.memoryEpoch == _memoryEpoch) _remember(task, result, text, run.askedAsKids);
      if (result.end == AssistantRunEnd.notEntitled) _availability = AssistantAvailability.locked;
    } catch (e, st) {
      appLogger.w('Assistant task failed', error: e.runtimeType, stackTrace: st);
      if (_alive(task)) {
        task.error = 'failed';
        task.status = AssistantTaskStatus.failed;
      }
    } finally {
      model?.close();
      if (task.generation == _generation && !_disposed) _update();
    }
  }
}

extension _AssistantMemory on AssistantController {
  /// Keeps a finished, plain answer as a turn. Never a failed, cancelled or
  /// split run, a fenced (spoiler) one, or Pleya's own kids lines.
  void _remember(_AssistantTaskState task, AssistantRunResult result, String text, bool kids) {
    if (task.status != AssistantTaskStatus.completed || result.end != AssistantRunEnd.answered) return;
    if (task.originalSpoilerPrompt != null || result.spoilerPrompt != null) return;
    if (result.kidsAgesNeeded || result.ageFilterNotice) return;
    final answer = clipText(text, AssistantController.maxAnswerChars);
    if (answer.isEmpty) return;
    _conversation.add(
      AssistantTurn(question: clipText(task.prompt, AssistantController.maxQuestionChars), answer: answer, kids: kids),
    );
    // Oldest first out, but the newest turn always stays.
    int size() => _conversation.fold(0, (sum, t) => sum + t.question.length + t.answer.length);
    while (_conversation.length > 1 && size() > AssistantController.maxMemoryChars) {
      _conversation.removeAt(0);
    }
  }
}

class _AssistantTaskState {
  _AssistantTaskState({
    required this.id,
    required this.title,
    required this.intent,
    required this.prompt,
    required this.generation,
    required this.budget,
    this.originalSpoilerPrompt,
    this.parentIntent,
    required this.memoryEpoch,
  });

  /// The conversation this task started in; a clear since then keeps its
  /// answer out of the memory.
  final int memoryEpoch;
  final String id, title, intent, prompt;
  final int generation;
  final String? originalSpoilerPrompt;

  /// What the question this task was split from fixed (audience, kind, period).
  final AssistantIntent? parentIntent;
  final AssistantQuestionBudget budget;
  final AbortController cancel = AbortController();
  AssistantTaskStatus status = AssistantTaskStatus.pending;
  String answer = '';
  bool ageFilterNotice = false;
  String? error;
  AssistantRunEnd? lastEnd;
  AssistantModelError? providerError;
  bool modelMissing = false;
  AssistantPendingAction? pending;
  final List<AssistantStep> steps = [];
  final List<AssistantActionRecord> actions = [];
  final List<AssistantDisplay> displays = [];
  AssistantTask get view => AssistantTask(
    id: id,
    title: title,
    intent: intent,
    status: status,
    answer: answer,
    error: error,
    lastEnd: lastEnd,
    providerError: providerError,
    modelMissing: modelMissing,
    pending: pending,
    steps: List.unmodifiable(steps),
    actions: List.unmodifiable(actions),
    displays: List.unmodifiable(displays),
  );
}
