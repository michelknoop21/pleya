import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/server_administration.dart';
import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_entitlement.dart';
import 'assistant_provider.dart';
import 'assistant_run.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';

part 'assistant_controller_jobs.dart';
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
    this._serverChanges,
    this.jobPollInterval = const Duration(seconds: 2),
    this.jobWatchLimit = const Duration(minutes: 2),
    this._jobsFor,
  }) : _now = now ?? DateTime.now,
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
  final List<AssistantStep> _steps = [];
  final List<AssistantActionRecord> _actions = [];
  final List<AssistantDisplay> _displays = [];
  AssistantPendingAction? _pending;
  Completer<AssistantConfirmation?>? _confirmer;
  AssistantScreenContext? _screenContext;

  /// Bumped by [reset]: a run that outlives its conversation (Annuleren
  /// while werken) can no longer write state or raise a card.
  int _generation = 0;

  /// The ask in flight's cancel signal: [reset] and [dispose] fire it, which
  /// aborts the model call on the wire and every find_title source.
  AbortController? _cancel;

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
    final AssistantProviderConfig? config;
    try {
      config = await _loadConfig();
    } on AssistantProviderStoreException {
      // An unreadable keychain is not "not configured": keep the last answer.
      // Without one (hidden is only the initial value past the checks above)
      // setup stays reachable. A save there does not write over the item it
      // could not read: it stays on this device and goes up later only into
      // an empty keychain. Every refresh reads again.
      return _availability == AssistantAvailability.hidden ? AssistantAvailability.needsSetup : _availability;
    }
    if (config == null || !config.isComplete) return AssistantAvailability.needsSetup;
    return AssistantAvailability.ready;
  }

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

  /// One ask. A second call while one runs is ignored.
  Future<void> submit(String prompt) async {
    final text = prompt.trim();
    if (_busy || text.isEmpty) return;
    _busy = true;
    _asking = true;
    _runs++;
    _jobsSeq++;
    final generation = _generation;
    final cancel = _cancel = AbortController();
    _prompt = text;
    _answer = '';
    _steps.clear();
    _actions.clear();
    _displays.clear();
    _resultIsError = false;
    _lastEnd = null;
    _lastProviderError = null;
    _modelMissing = false;
    _state = AssistantSurfaceState.working;
    _notify();

    AssistantModelClient? model;
    try {
      final config = await _loadConfig();
      if (config == null || !config.isComplete) {
        if (generation != _generation) return;
        _availability = AssistantAvailability.needsSetup;
        _prompt = null;
        _state = AssistantSurfaceState.idle;
        return;
      }
      model = _modelFor(config);
      final result = await AssistantRun(
        model: model,
        // The session builds contexts without the provider config, which
        // decides the web lookup.
        context: _buildContext(_screenContext).fresh(web: config.webSearch ? _webFor?.call(config) : null),
        confirm: (action) => _confirm(action, generation),
        entitlement: _entitlement,
        tools: _tools,
        languageName: _languageName(),
        confirmTimeout: confirmTimeout,
        // Cancel, reset or a profile switch (dispose) aborts the model call
        // and the tools in flight; nothing new starts after that.
        cancel: cancel,
        onStep: (step) {
          if (generation != _generation) return;
          final at = _steps.indexWhere((s) => s.index == step.index);
          at < 0 ? _steps.add(step) : _steps[at] = step;
          // Shown now, not after the model's last turn; the run's own list
          // repeats these and is not added again.
          if (step.display case final display?) _displays.add(display);
          _notify();
        },
      ).ask(text);
      if (generation != _generation) return;
      _lastEnd = result.end;
      _lastProviderError = result.providerError;
      _modelMissing = result.end == AssistantRunEnd.providerError && model.modelMissing;
      _resultIsError = result.end != AssistantRunEnd.answered;
      _answer = result.text;
      _actions.addAll(result.actions);
      // The run's list is the final word: it drops a lookup that led to an
      // action and adds the cards for titles the answer named.
      _displays
        ..clear()
        ..addAll(result.displays);
      if (_actions.any((a) => a.job != null)) unawaited(_watchJobs());
      if (result.end == AssistantRunEnd.notEntitled) _availability = AssistantAvailability.locked;
      _state = AssistantSurfaceState.result;
    } catch (e, st) {
      appLogger.w('Assistant ask failed', error: e.runtimeType, stackTrace: st);
      if (generation == _generation) {
        _resultIsError = true;
        _state = AssistantSurfaceState.result;
      }
    } finally {
      model?.close();
      if (generation == _generation) {
        _busy = false;
        _asking = false;
        _cancel = null;
      }
      _notify();
    }
  }

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

  /// [password] comes from Pleya's secure field, never from the model.
  void confirmPending({String? password}) => _answerPending(AssistantConfirmation(password: password));

  void cancelPending() => _answerPending(null);

  void _answerPending(AssistantConfirmation? answer) {
    final completer = _confirmer;
    if (completer == null || completer.isCompleted) return;
    completer.complete(answer);
  }

  /// The user picked an option card. No model involved: the card is built
  /// by [assistantRequestFromOption] from the ask that showed [option], and
  /// goes through the same confirmation, entitlement and authority checks
  /// as a card the model asked for.
  Future<void> pickRequestOption(AssistantRequestOption option, {bool fourK = false}) async {
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

  /// A run in flight and a waiting card are let go; what is on screen stays
  /// until [reset] (Big P sliding out). Does not notify.
  void abort() {
    _generation++;
    _jobsSeq++;
    _abortAsk();
    _answerPending(null);
  }

  /// Back to rust; the conversation, a waiting card and a run in flight are
  /// all let go.
  void reset() {
    abort();
    _pending = null;
    _confirmer = null;
    _busy = false;
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

  void _abortAsk() {
    _cancel?.abort();
    _cancel = null;
    _asking = false;
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _configChanges.removeListener(_onConfigChanged);
    _serverChanges?.removeListener(_onServersChanged);
    _disposed = true;
    _generation++;
    _jobsSeq++;
    _abortAsk();
    _answerPending(null);
    for (final cleanup in _onDispose) {
      cleanup();
    }
    super.dispose();
  }
}
