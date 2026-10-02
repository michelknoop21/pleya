import 'dart:async';

import 'package:flutter/foundation.dart';

import '../i18n/strings.g.dart';
import '../utils/app_logger.dart';
import 'assistant_entitlement.dart';
import 'assistant_provider.dart';
import 'assistant_run.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';
import 'assistant_web_lookup.dart';

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
  }) : _now = now ?? DateTime.now,
       _loadConfig = loadConfig ?? AssistantProviderStore.instance.load,
       _modelFor = modelFor ?? AssistantModelClient.new,
       _languageName = languageName ?? assistantLanguageName;

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
  Completer<AssistantConfirmation?>? _confirmer;
  AssistantScreenContext? _screenContext;

  /// Bumped by [reset]: a run that outlives its conversation (Annuleren
  /// while werken) can no longer write state or raise a card.
  int _generation = 0;
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

  /// Non-null while a confirmation card must show.
  AssistantPendingAction? get pending => _pending;
  AssistantScreenContext? get screenContext => _screenContext;

  /// Reads entitlement, servers, Seerr and the provider config. Called by the
  /// UI when an entry point shows; nothing here runs at app start.
  Future<void> refreshAvailability() async {
    _availability = await _computeAvailability();
    _notify();
  }

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

  /// One ask. A second call while one runs is ignored.
  Future<void> submit(String prompt) async {
    final text = prompt.trim();
    if (_busy || text.isEmpty) return;
    _busy = true;
    final generation = _generation;
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
        context: _withWeb(_buildContext(_screenContext), config.webSearch ? _webFor?.call(config) : null),
        confirm: (action) => _confirm(action, generation),
        entitlement: _entitlement,
        tools: _tools,
        languageName: _languageName(),
        confirmTimeout: confirmTimeout,
        // Cancel, reset or a profile switch (dispose) stops the run: no new
        // model call, tool call or confirmed action starts after that.
        isCancelled: () => generation != _generation || _disposed,
        onStep: (step) {
          if (generation != _generation) return;
          final at = _steps.indexWhere((s) => s.index == step.index);
          at < 0 ? _steps.add(step) : _steps[at] = step;
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
      _displays.addAll(result.displays);
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
      if (generation == _generation) _busy = false;
      _notify();
    }
  }

  /// [base] with [web] set: the session builds contexts without knowing the
  /// provider config, which decides the web lookup.
  static AssistantToolContext _withWeb(AssistantToolContext base, AssistantWebServices? web) => web == null
      ? base
      : AssistantToolContext(
          servers: base.servers,
          screen: base.screen,
          catalog: base.catalog,
          insights: base.insights,
          requests: base.requests,
          media: base.media,
          web: web,
        );

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

  /// Back to rust; the conversation, a waiting card and a run in flight are
  /// all let go.
  void reset() {
    _generation++;
    _answerPending(null);
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

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _answerPending(null);
    super.dispose();
  }
}

/// The app language as the model's system prompt names it.
String assistantLanguageName() => switch (LocaleSettings.currentLocale) {
  AppLocale.nl => 'Dutch',
  AppLocale.de => 'German',
  AppLocale.fr => 'French',
  AppLocale.es => 'Spanish',
  AppLocale.it => 'Italian',
  AppLocale.da => 'Danish',
  AppLocale.nb => 'Norwegian',
  AppLocale.sv => 'Swedish',
  AppLocale.pl => 'Polish',
  AppLocale.pt => 'Portuguese',
  AppLocale.ru => 'Russian',
  AppLocale.bg => 'Bulgarian',
  AppLocale.ja => 'Japanese',
  AppLocale.ko => 'Korean',
  AppLocale.zh => 'Chinese',
  AppLocale.en => 'English',
};
