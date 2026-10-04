import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_entitlement.dart';
import 'assistant_execution.dart';
import 'assistant_task.dart';

export 'assistant_task.dart';
import 'assistant_provider.dart';
import 'assistant_run.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';

part 'assistant_controller_language.dart';

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
  }) : _now = now ?? DateTime.now,
       _loadConfig = loadConfig ?? AssistantProviderStore.instance.load,
       _modelFor = modelFor ?? AssistantModelClient.new,
       _languageName = languageName ?? assistantLanguageName,
       _configChanges = configChanges ?? AssistantProviderStore.changes {
    _configChanges.addListener(_onConfigChanged);
  }

  /// A provider saved or cleared in Instellingen moves the tile and the
  /// summon out of (or into) setup without reopening Mijn Pleya.
  final Listenable _configChanges;
  void _onConfigChanged() => unawaited(refreshAvailability());

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

  /// At most one model preload per window; Ollama keeps it loaded for
  /// [_preloadKeepAlive], which outlasts the window.
  final Duration preloadWindow;
  static const String _preloadKeepAlive = '10m';
  DateTime? _lastPreload;

  /// How long a confirmation card waits; then the run hears `not_confirmed`.
  final Duration confirmTimeout;

  AssistantAvailability _availability = AssistantAvailability.hidden;
  AssistantSurfaceState _state = AssistantSurfaceState.idle;
  bool _resultIsError = false;
  AssistantRunEnd? _lastEnd;
  AssistantModelError? _lastProviderError;
  bool _modelMissing = false;
  String? _prompt;
  String _answer = '';
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

  Future<AssistantAvailability> _computeAvailability() async {
    if (!_rolloutEnabled) return AssistantAvailability.hidden;
    final ctx = _buildContext(null);
    if (ctx.userServers.isEmpty && ctx.requests?.client() == null) return AssistantAvailability.hidden;
    if (await _entitlement.check() != AssistantEntitlementState.entitled) return AssistantAvailability.locked;
    final config = await _loadConfig();
    if (config == null || !config.isComplete) return AssistantAvailability.needsSetup;
    return AssistantAvailability.ready;
  }

  void beginListening({AssistantScreenContext? context}) {
    if (_busy || _pending != null) return;
    _screenContext = context ?? _screenContext;
    _state = AssistantSurfaceState.listening;
    _notify();
    unawaited(_preload());
  }

  /// Warms the Ollama server's model while the user speaks, so the first
  /// answer does not wait for loading. Fire and forget: never blocks, never
  /// surfaces an error. Ollama Cloud and OpenRouter keep models hot already.
  Future<void> _preload() async {
    final now = _now();
    final last = _lastPreload;
    if (last != null && now.difference(last) < preloadWindow) return;
    _lastPreload = now;
    AssistantModelClient? client;
    try {
      final config = await _loadConfig();
      if (_disposed || config == null || !config.isComplete || config.kind != AssistantProviderKind.ollamaServer) {
        return;
      }
      client = _modelFor(config);
      await client.preload(keepAlive: _preloadKeepAlive);
    } catch (e) {
      // Type only: a message could echo the server address or a header.
      appLogger.d('Assistant model preload failed', error: e.runtimeType);
    } finally {
      client?.close();
    }
  }

  /// Back to where listening started: the last result when there is one.
  void cancelListening() {
    if (_state != AssistantSurfaceState.listening) return;
    _state = _prompt == null ? AssistantSurfaceState.idle : AssistantSurfaceState.result;
    _notify();
  }

  /// A new question supersedes every task and card from the previous one.
  Future<void> submit(String prompt) async {
    final text = prompt.trim();
    if (_disposed || text.isEmpty) return;
    final screen = _screenContext;
    reset();
    _screenContext = screen;
    final generation = _generation;
    _prompt = text;
    final budget = AssistantQuestionBudget();
    final root = _newTask(title: text, intent: 'command', prompt: text, generation: generation, budget: budget);
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
      await _runTask(root, config, refresh, allowSplit: true);
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
  }) => _AssistantTaskState(
    id: 'task-${++_nextTask}',
    title: title,
    intent: intent,
    prompt: prompt,
    generation: generation,
    budget: budget,
  );

  bool _alive(_AssistantTaskState task) =>
      !_disposed && task.generation == _generation && !task.cancel.isAborted && _tasks.contains(task);

  Future<void> _runTask(
    _AssistantTaskState task,
    AssistantProviderConfig config,
    Future<void> Function() refreshHealth, {
    bool allowSplit = false,
  }) async {
    AssistantModelClient? model;
    try {
      if (!_alive(task)) return;
      task.status = AssistantTaskStatus.running;
      _update();
      model = _modelFor(config);
      final result = await AssistantRun(
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
        budget: task.budget,
        operations: _operations,
        mutations: _mutations,
        refreshHealth: refreshHealth,
        onStep: (step) {
          if (!_alive(task)) return;
          final at = task.steps.indexWhere((s) => s.index == step.index);
          at < 0 ? task.steps.add(step) : task.steps[at] = step;
          if (step.display case final display?) task.displays.add(display);
          _update();
        },
      ).ask(task.prompt);
      if (!_alive(task)) return;
      if (result.splitTasks.isNotEmpty) {
        final children = [
          for (final plan in result.splitTasks)
            _newTask(
              title: plan.title,
              intent: plan.intent,
              prompt: plan.prompt,
              generation: task.generation,
              budget: task.budget,
            ),
        ];
        _tasks
          ..remove(task)
          ..addAll(children);
        _update();
        await Future.wait([for (final child in children) _runTask(child, config, refreshHealth)]);
        return;
      }
      task.lastEnd = result.end;
      task.providerError = result.providerError;
      task.modelMissing = result.end == AssistantRunEnd.providerError && model.modelMissing;
      final playbackCurrent = result.playbackEvidenceCurrent?.call() ?? true;
      task.error = playbackCurrent
          ? result.error ?? (result.end == AssistantRunEnd.answered ? null : result.end.name)
          : 'playback_session_changed';
      task.answer = playbackCurrent ? result.text : '';
      task.actions.addAll(result.actions);
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

  Future<void> pickRequestOption(AssistantRequestOption option, {bool fourK = false}) async {
    final task = _tasks.where((task) => _optionContext(task, option) != null).firstOrNull;
    if (task != null) await pickTaskRequestOption(task.id, option, fourK: fourK);
  }

  Future<void> pickTaskRequestOption(String taskId, AssistantRequestOption option, {bool fourK = false}) async {
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
    _disposed = true;
    abort();
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
  });
  final String id, title, intent, prompt;
  final int generation;
  final AssistantQuestionBudget budget;
  final AbortController cancel = AbortController();
  AssistantTaskStatus status = AssistantTaskStatus.pending;
  String answer = '';
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

class _QueuedConfirmation {
  _QueuedConfirmation({required this.id, required this.task, required this.action});
  final String id;
  final _AssistantTaskState task;
  final AssistantPendingAction action;
  final Completer<AssistantConfirmation?> completer = Completer();
  Timer? timer;
  AssistantTaskConfirmation get view => AssistantTaskConfirmation(id: id, taskId: task.id, action: action);
}
