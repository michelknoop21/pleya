import 'assistant_spoiler_context.dart';
import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/server_administration.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_entitlement.dart';
import 'assistant_kids_ages_store.dart';
import 'assistant_execution.dart';
import 'assistant_task.dart';

export 'assistant_task.dart';
import 'assistant_provider.dart';
import 'assistant_run.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';

part 'assistant_controller_jobs.dart';
part 'assistant_controller_options.dart';
part 'assistant_controller_language.dart';
part 'assistant_controller_reads.dart';

enum AssistantAvailability { hidden, locked, needsSetup, ready }

enum AssistantSurfaceState { idle, listening, working, result }

/// Big P's state for every surface: availability, the four stands of the
/// approved design (rust, luisteren, werken, resultaat) and the confirmation
/// card. Platform-neutral; the TV and mobile UI only read it and call it.
///
/// Holds no provider itself: [buildContext] hands over a fresh
/// [AssistantToolContext] from the live session per ask, so a role change or
/// a Seerr disconnect between two asks is seen by the next one.
class AssistantController extends ChangeNotifier {
  AssistantController({
    required this._buildContext,
    this._rolloutEnabled = AssistantEntitlement.rolloutEnabled,
    this._entitlement = const AssistantEntitlement(),
    Future<AssistantProviderConfig?> Function()? loadConfig,
    AssistantModelClient Function(AssistantProviderConfig config)? modelFor,
    this._webFor,
    String Function()? languageName,
    this.confirmTimeout = const Duration(minutes: 2),
    this.preloadWindow = const Duration(minutes: 5),
    DateTime Function()? now,
    this._tools,
    Listenable? configChanges,
    this._serverChanges,
    this.jobPollInterval = const Duration(seconds: 2),
    this.jobWatchLimit = const Duration(minutes: 2),
    this._jobsFor,
    Future<void> Function(List<int> ages)? saveKidsAges,
  }) : _now = now ?? DateTime.now,
       _saveKidsAges = saveKidsAges ?? KidsAgesStore().save,
       _loadConfig = loadConfig ?? AssistantProviderStore.instance.load,
       _modelFor = modelFor ?? AssistantModelClient.new,
       _languageName = languageName ?? assistantLanguageName,
       _configChanges = configChanges ?? AssistantProviderStore.changes {
    _configChanges.addListener(_onConfigChanged);
    _serverChanges?.addListener(_onServersChanged);
  }

  /// A provider saved or cleared in Instellingen moves the tile and the
  /// summon out of (or into) setup without reopening Mijn Pleya.
  final Listenable _configChanges;
  void _onConfigChanged() => unawaited(refreshAvailability());

  /// Servers load after the session starts, so the first read can see none
  /// and answer hidden. Their arrival (none to some) reads once more, so the
  /// face button and the Discover slot show up without a visit to Mijn Pleya.
  final Listenable? _serverChanges;
  bool _hadServers = false;
  void _onServersChanged() {
    // Every MultiServerProvider notify lands here; with the flag off nothing
    // can become visible, so no tool context gets built.
    if (!_rolloutEnabled || _disposed) return;
    final hasServers = _buildContext(null).userServers.isNotEmpty;
    final arrived = hasServers && !_hadServers;
    _hadServers = hasServers;
    if (arrived && _availability == AssistantAvailability.hidden) unawaited(refreshAvailability());
  }

  final AssistantToolContext Function(AssistantScreenContext? screen) _buildContext;
  final bool _rolloutEnabled;
  final AssistantEntitlement _entitlement;
  final Future<AssistantProviderConfig?> Function() _loadConfig;
  final AssistantModelClient Function(AssistantProviderConfig config) _modelFor;

  /// Web lookup for a run whose config allows it; null keeps the web out.
  final AssistantWebServices? Function(AssistantProviderConfig config)? _webFor;
  final String Function() _languageName;
  final List<AssistantTool>? _tools;
  final DateTime Function() _now;

  /// Writes the children's ages of this profile ([KidsAgesStore.save]).
  final Future<void> Function(List<int> ages) _saveKidsAges;

  /// At most one model preload per window; Ollama keeps it loaded for
  /// [_preloadKeepAlive], which outlasts the window.
  final Duration preloadWindow;
  static const String _preloadKeepAlive = '10m';
  DateTime? _lastPreload;

  /// How long a confirmation card waits; then the run hears `not_confirmed`.
  final Duration confirmTimeout;

  /// How often a started scan or job is looked up, and for how long.
  final Duration jobPollInterval;
  final Duration jobWatchLimit;

  /// Tests only: job lists without a registered server.
  final Future<List<ServerJob>?> Function(ServerId serverId)? _jobsFor;

  /// Bumped by a new ask, [abort] and [dispose]: stops the job watch.
  int _jobsSeq = 0;

  AssistantAvailability _availability = AssistantAvailability.hidden;
  AssistantSurfaceState _state = AssistantSurfaceState.idle;
  bool _resultIsError = false;

  /// Bumped by every [submit]: tells one answer from the next, also when the
  /// same question is asked again.
  int get runs => _runs;
  int _runs = 0;
  AssistantRunEnd? _lastEnd;
  AssistantModelError? _lastProviderError;
  bool _modelMissing = false;
  String? _prompt;
  String _answer = '';
  bool _ageFilterNotice = false;
  final List<AssistantStep> _steps = [];
  final List<AssistantActionRecord> _actions = [];
  final List<AssistantDisplay> _displays = [];
  AssistantPendingAction? _pending;
  final List<_AssistantTaskState> _tasks = [];
  final List<_QueuedConfirmation> _confirmations = [];
  final AssistantOperationPool _operations = AssistantOperationPool(3);
  final AssistantOperationPool _mutations = AssistantOperationPool(1);
  int _nextTask = 0;
  int _nextConfirmation = 0;

  List<AssistantTask> get tasks => List.unmodifiable(_tasks.map((task) => task.view));
  AssistantTaskConfirmation? get pendingConfirmation => _confirmations.firstOrNull?.view;
  AssistantScreenContext? _screenContext;

  /// Bumped by [reset]: a run that outlives its conversation (Annuleren
  /// while werken) can no longer write state or raise a card.
  int _generation = 0;

  /// True while a [submit] run is still going, displays streamed or not.
  bool _asking = false;
  bool _busy = false;
  bool _disposed = false;

  AssistantAvailability get availability => _availability;

  /// Lets a listener with its own timers (Big P's voice) stand down.
  bool get disposed => _disposed;

  final List<VoidCallback> _onDispose = [];

  /// Runs [cleanup] when this controller is disposed, e.g. to silence Big P.
  void onDispose(VoidCallback cleanup) => _onDispose.add(cleanup);
  AssistantSurfaceState get state => _state;
  bool get resultIsError => _resultIsError;
  AssistantRunEnd? get lastEnd => _lastEnd;
  AssistantModelError? get lastProviderError => _lastProviderError;

  /// The last run failed because the saved model is gone; the UI says so
  /// with `t.assistant.ends.modelMissing` instead of the generic error.
  bool get modelMissing => _modelMissing;
  String? get prompt => _prompt;

  /// The model's words: display only, never a source of actions.
  String get answer => _answer;

  /// Some answer carries Pleya's age notice ([t.assistant.kids.filterNotice]),
  /// so a surface that shows only the lead can still show the notice.
  bool get ageFilterNotice => _ageFilterNotice;
  List<AssistantStep> get steps => List.unmodifiable(_steps);
  List<AssistantActionRecord> get actions => List.unmodifiable(_actions);
  List<AssistantDisplay> get displays => List.unmodifiable(_displays);

  /// Results are already on screen but the model is still composing its
  /// reply: the UI says Big P is still checking, not that it is done.
  bool get stillChecking => _asking && _state == AssistantSurfaceState.working && _displays.isNotEmpty;

  /// Non-null while a confirmation card must show.
  AssistantPendingAction? get pending => _pending;
  AssistantScreenContext? get screenContext => _screenContext;

  /// Reads entitlement, servers, Seerr and the provider config. Called by the
  /// UI when an entry point shows; nothing here runs at app start.
  Future<void> refreshAvailability() async {
    // A slower, older refresh must not overwrite a newer answer.
    final seq = ++_availabilitySeq;
    final availability = await _computeAvailability();
    if (seq != _availabilitySeq) return;
    _availability = availability;
    _notify();
  }

  int _availabilitySeq = 0;

  /// Forgets the screen Big P was last asked from. [beginListening] keeps it
  /// across a null context (TV's follow-ups); a summon from somewhere
  /// without one (iPhone and iPad) must not ask about the last library.
  void clearScreenContext() => _screenContext = null;

  void beginListening({AssistantScreenContext? context}) {
    if (_busy || _pending != null) return;
    _screenContext = context ?? _screenContext;
    _state = AssistantSurfaceState.listening;
    _notify();
    unawaited(_preload());
  }

  /// Back to where listening started: the last result when there is one.
  void cancelListening() {
    if (_state != AssistantSurfaceState.listening) return;
    _state = _prompt == null ? AssistantSurfaceState.idle : AssistantSurfaceState.result;
    _notify();
  }

  /// A new question supersedes every task and card from the previous one.
  /// [kidsFilter] false runs it once without the age gate ("Zonder filter").
  Future<void> submit(String prompt, {bool kidsFilter = true}) async {
    final text = prompt.trim();
    if (_disposed || text.isEmpty) return;
    final screen = _screenContext;
    reset();
    _screenContext = screen;
    _runs++;
    final generation = _generation;
    _prompt = text;
    final budget = AssistantQuestionBudget();
    final root = _newTask(
      title: text,
      intent: 'command',
      prompt: text,
      generation: generation,
      budget: budget,
      originalSpoilerPrompt: assistantNeedsSpoilerScope(text) ? text : null,
    );
    _tasks.add(root);
    _update();
    try {
      final config = await _loadConfig();
      if (!_alive(root)) return;
      if (config == null || !config.isComplete) {
        _availability = AssistantAvailability.needsSetup;
        reset();
        return;
      }
      // One health refresh per question. Child contexts still check live
      // authority on every tool and after acquiring the mutation lock.
      final context = _buildContext(_screenContext);
      Future<void>? health;
      Future<void> refresh() => health ??= context.servers.checkServerHealth();
      await _runTask(root, config, refresh, allowSplit: true, kidsFilter: kidsFilter);
    } catch (e, st) {
      appLogger.w('Assistant ask failed', error: e.runtimeType, stackTrace: st);
      if (_alive(root)) {
        root.error = 'failed';
        root.status = AssistantTaskStatus.failed;
        _update();
      }
    }
  }

  _AssistantTaskState _newTask({
    required String title,
    required String intent,
    required String prompt,
    required int generation,
    required AssistantQuestionBudget budget,
    String? originalSpoilerPrompt,
  }) => _AssistantTaskState(
    id: 'task-${++_nextTask}',
    title: title,
    intent: intent,
    prompt: prompt,
    generation: generation,
    budget: budget,
    originalSpoilerPrompt: originalSpoilerPrompt,
  );

  bool _alive(_AssistantTaskState task) =>
      !_disposed && task.generation == _generation && !task.cancel.isAborted && _tasks.contains(task);

  Future<void> _runTask(
    _AssistantTaskState task,
    AssistantProviderConfig config,
    Future<void> Function() refreshHealth, {
    bool allowSplit = false,
    bool libraryDoctorScope = false,
    bool kidsFilter = true,
  }) async {
    AssistantModelClient? model;
    try {
      if (!_alive(task)) return;
      task.status = AssistantTaskStatus.running;
      _update();
      model = _modelFor(config);
      final result = await AssistantRun(
        model: model,
        context: _buildContext(
          _screenContext,
        ).fresh(web: config.webSearch ? _webFor?.call(config) : null, kidsFilter: kidsFilter),
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
      ).ask(task.prompt);
      if (!_alive(task)) return;
      if (result.splitTasks.isNotEmpty) {
        final inheritedSpoilerPrompt = task.originalSpoilerPrompt ?? result.spoilerPrompt;
        final children = [
          for (final plan in result.splitTasks)
            _newTask(
              // A fenced parent cannot delegate an unrestricted task or show
              // model-invented narrative labels. Conservative whole-question scope.
              title: inheritedSpoilerPrompt ?? plan.title,
              intent: inheritedSpoilerPrompt == null ? plan.intent : 'spoiler_context',
              prompt: inheritedSpoilerPrompt ?? plan.prompt,
              originalSpoilerPrompt: inheritedSpoilerPrompt,
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
          for (final child in children)
            _runTask(child, config, refreshHealth, libraryDoctorScope: doctorScope, kidsFilter: kidsFilter),
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
      // Pleya's own words, never the model's: the answer still names a
      // title the age filter turned down.
      final text = result.kidsAgesNeeded
          ? t.assistant.kids.agesFirst
          : result.ageFilterNotice
          ? '${result.text}\n\n${t.assistant.kids.filterNotice}'
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

  /// Confirm exactly the visible task/action. Old sheet responses do nothing.
  void confirmTask(String taskId, String confirmationId, {String? password}) {
    final entry = _confirmations.firstOrNull;
    if (entry == null || entry.task.id != taskId || entry.id != confirmationId || !_alive(entry.task)) return;
    _finishConfirmation(entry, AssistantConfirmation(password: password));
  }

  void cancelTaskConfirmation(String taskId, String confirmationId) {
    final entry = _confirmations.firstOrNull;
    if (entry == null || entry.task.id != taskId || entry.id != confirmationId) return;
    _finishConfirmation(entry, null);
  }

  /// Legacy single-card projection. Pass the captured action for stale-sheet
  /// protection; task-aware surfaces use [confirmTask].
  void confirmPending({String? password, AssistantPendingAction? action}) {
    final entry = _confirmations.firstOrNull;
    if (entry == null || (action != null && !identical(action, entry.action))) return;
    confirmTask(entry.task.id, entry.id, password: password);
  }

  void cancelPending({AssistantPendingAction? action}) {
    final entry = _confirmations.firstOrNull;
    if (entry == null || (action != null && !identical(action, entry.action))) return;
    cancelTaskConfirmation(entry.task.id, entry.id);
  }

  Future<void> pickRequestOption(AssistantRequestOption option, {bool fourK = false}) async {
    final task = _tasks.where((task) => _optionContext(task, option) != null).firstOrNull;
    if (task != null) await pickTaskRequestOption(task.id, option, fourK: fourK);
  }

  /// The user picked an option card. No model involved: the card is built
  /// by [assistantRequestFromOption] from the ask that showed [option], and
  /// goes through the same confirmation, entitlement and authority checks
  /// as a card the model asked for.
  Future<void> pickTaskRequestOption(String taskId, AssistantRequestOption option, {bool fourK = false}) =>
      _pickTaskRequestOption(taskId, option, fourK: fourK);

  /// The ages card waits: the last answer asked for the children's ages.
  /// Every surface hides its question field until it is answered or closed.
  AssistantKidsAgesPrompt? get kidsAgesPrompt =>
      state == AssistantSurfaceState.result ? displays.whereType<AssistantKidsAgesPrompt>().firstOrNull : null;

  /// The ages card was answered: saves [ages] for this profile and asks the
  /// question that needed them again.
  Future<void> saveKidsAgesAndRetry(List<int> ages) async {
    final prompt = _displays.whereType<AssistantKidsAgesPrompt>().firstOrNull?.prompt ?? _prompt;
    await _saveKidsAges(ages);
    if (prompt != null && !_disposed) await submit(prompt);
  }

  /// "Zonder filter": the same question once more without the age gate.
  /// Nothing is saved, so a next ask for children shows the card again.
  Future<void> retryWithoutKidsFilter() async {
    final prompt = kidsAgesPrompt?.prompt ?? _prompt;
    if (prompt != null && !_disposed) await submit(prompt, kidsFilter: false);
  }

  /// The ages card closed unanswered (Menu): the answer stays, the card goes.
  void dismissKidsAges() {
    for (final task in _tasks) {
      task.displays.removeWhere((d) => d is AssistantKidsAgesPrompt);
    }
    _update();
  }

  // Declining a confirmation declines that action; the model still receives
  // its tool response and can continue. Only the final task label changes.
  AssistantTaskStatus _outcomeStatus(String? error) => switch (error) {
    null => AssistantTaskStatus.completed,
    'cancelled_by_user' => AssistantTaskStatus.cancelled,
    _ => AssistantTaskStatus.failed,
  };

  void cancelTask(String taskId) {
    final task = _tasks.where((task) => task.id == taskId).firstOrNull;
    if (task == null || task.status == AssistantTaskStatus.cancelled) return;
    task.cancel.abort();
    task.status = AssistantTaskStatus.cancelled;
    for (final entry in _confirmations.where((entry) => identical(entry.task, task)).toList()) {
      _finishConfirmation(entry, null);
    }
    _update();
  }

  void cancelAll() {
    for (final task in _tasks.toList()) {
      if (task.status == AssistantTaskStatus.pending ||
          task.status == AssistantTaskStatus.running ||
          task.status == AssistantTaskStatus.waitingForConfirmation) {
        cancelTask(task.id);
      }
    }
  }

  /// Drop lifecycle authority while keeping the last visible results.
  void abort() {
    cancelAll();
    _generation++;
    _jobsSeq++;
  }

  void reset() {
    abort();
    _tasks.clear();
    _pending = null;
    _busy = false;
    _asking = false;
    _state = AssistantSurfaceState.idle;
    _resultIsError = false;
    _lastEnd = null;
    _lastProviderError = null;
    _modelMissing = false;
    _prompt = null;
    _answer = '';
    _ageFilterNotice = false;
    _steps.clear();
    _actions.clear();
    _displays.clear();
    _screenContext = null;
    _notify();
  }

  void _update() {
    _busy = _tasks.any(
      (task) =>
          task.status == AssistantTaskStatus.pending ||
          task.status == AssistantTaskStatus.running ||
          task.status == AssistantTaskStatus.waitingForConfirmation,
    );
    _asking = _busy;
    _state = _busy
        ? AssistantSurfaceState.working
        : _tasks.isEmpty
        ? AssistantSurfaceState.idle
        : AssistantSurfaceState.result;
    _resultIsError = _tasks.any((task) => task.status == AssistantTaskStatus.failed);
    _answer = _tasks.map((task) => task.answer).where((answer) => answer.isNotEmpty).join('\n');
    _ageFilterNotice = _tasks.any((task) => task.ageFilterNotice && task.answer.isNotEmpty);
    _steps
      ..clear()
      ..addAll(_tasks.expand((task) => task.steps));
    _actions
      ..clear()
      ..addAll(_tasks.expand((task) => task.actions));
    _displays
      ..clear()
      ..addAll(_tasks.expand((task) => task.displays));
    _lastEnd = _tasks.map((task) => task.lastEnd).nonNulls.lastOrNull;
    _lastProviderError = _tasks.map((task) => task.providerError).nonNulls.firstOrNull;
    _modelMissing = _tasks.any((task) => task.modelMissing);
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _configChanges.removeListener(_onConfigChanged);
    _serverChanges?.removeListener(_onServersChanged);
    _disposed = true;
    abort();
    for (final cleanup in _onDispose) {
      cleanup();
    }
    super.dispose();
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
  });
  final String id, title, intent, prompt;
  final int generation;
  final String? originalSpoilerPrompt;
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
