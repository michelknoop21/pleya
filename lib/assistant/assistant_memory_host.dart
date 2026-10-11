import 'package:flutter/foundation.dart';

import '../utils/app_logger.dart';
import '../utils/media_server_http_client.dart' show AbortController;
import 'assistant_entitlement.dart';
import 'assistant_memory.dart';
import 'assistant_provider.dart';
import 'assistant_run.dart';
import 'assistant_tool_context.dart';
import 'assistant_tools.dart';

/// The "Vraag of werk bij" field of the memory screen: a Big P run of its
/// own with the three memory tools and nothing else. It shares no state with
/// the conversation: not its turns, not its busy state and not its cards, so
/// a question here never lands in the chat and a card waiting there does not
/// block this field.
///
/// The rules for writing are the conversation's: a new fact after a typed
/// "onthoud dat" is stored at once, replacing and forgetting always wait for
/// a yes on a card. A follow-up question the model wrote ([askFollowUp])
/// never stores at once.
class AssistantMemoryHost extends ChangeNotifier {
  AssistantMemoryHost({
    required this._buildContext,
    required this._languageName,
    this._entitlement = const AssistantEntitlement(),
    Future<AssistantProviderConfig?> Function()? loadConfig,
    AssistantModelClient Function(AssistantProviderConfig config)? modelFor,
  }) : _loadConfig = loadConfig ?? AssistantProviderStore.instance.load,
       _modelFor = modelFor ?? AssistantModelClient.new;

  /// A fresh context of the profile session per ask, as the conversation
  /// gets it. Only its memory and the profile stand are used here.
  final AssistantToolContext Function() _buildContext;
  final String Function() _languageName;
  final AssistantEntitlement _entitlement;
  final Future<AssistantProviderConfig?> Function() _loadConfig;
  final AssistantModelClient Function(AssistantProviderConfig config) _modelFor;

  bool _busy = false;
  bool _disposed = false;
  int _asks = 0;
  AbortController? _cancel;
  String? _question;
  String _answer = '';
  String? _failure;
  final List<AssistantMemoryProposal> _proposals = [];
  AssistantMemoryOutcome? _outcome;
  bool _overviewStale = false;

  /// A run of this field is going; a second question waits for it.
  bool get busy => _busy;

  /// The last question asked here, and Big P's answer to it.
  String? get question => _question;
  String get answer => _answer;

  /// Why the last run gave no answer, as a fixed code, or null.
  String? get failure => _failure;

  /// The card that waits above the field, or null.
  AssistantMemoryProposal? get proposal => _busy ? null : _proposals.firstOrNull;

  /// What became of the last answered card.
  AssistantMemoryOutcome? get outcome => _outcome;

  /// A fact changed through this field since the overview was last written:
  /// the screen writes it again and calls [overviewWritten].
  bool get overviewStale => _overviewStale;

  void overviewWritten() {
    if (!_overviewStale) return;
    _overviewStale = false;
    _notify();
  }

  /// A question or request the user typed.
  Future<void> ask(String text) => _ask(text, typed: true);

  /// A follow-up question from "Duik dieper". The model wrote it, so whatever
  /// it says it is no explicit request of the user: every write it leads to
  /// gets a card.
  Future<void> askFollowUp(String text) => _ask(text, typed: false);

  Future<void> _ask(String text, {required bool typed}) async {
    final prompt = text.trim();
    if (_disposed || _busy || prompt.isEmpty) return;
    final ask = ++_asks;
    final cancel = _cancel = AbortController();
    _busy = true;
    _question = prompt;
    _answer = '';
    _failure = null;
    _outcome = null;
    _proposals.clear();
    _notify();
    AssistantModelClient? model;
    try {
      final config = await _loadConfig();
      if (config == null || !config.isComplete) {
        _failure = 'needs_setup';
        return;
      }
      model = _modelFor(config);
      final result = await AssistantRun(
        model: model,
        context: _buildContext(),
        // No memory tool asks for a confirmation of this kind.
        confirm: (_) async => null,
        entitlement: _entitlement,
        tools: assistantMemoryTools,
        languageName: _languageName(),
        cancel: cancel,
        memoryOnly: true,
        userTyped: typed,
        // The memory needs no server; no probe is spent on one.
        refreshHealth: () async {},
      ).ask(prompt);
      if (_disposed || ask != _asks) return;
      _answer = assistantMemoryAnswer(result, result.text);
      if (result.end == AssistantRunEnd.answered) {
        _proposals.addAll(result.memoryProposals);
        _failure = result.error;
      } else {
        _failure = result.error ?? result.end.name;
      }
      if (result.memoryStored.isNotEmpty) _overviewStale = true;
    } catch (e) {
      appLogger.w('Memory field ask failed: ${e.runtimeType}');
      if (ask == _asks) _failure = 'failed';
    } finally {
      model?.close();
      if (ask == _asks) {
        _busy = false;
        _notify();
      }
    }
  }

  /// The answer on the card. Yes writes when the profile is still the one
  /// the proposal was made for; no stores nothing.
  Future<void> answerProposal(AssistantMemoryProposal proposal, {required bool accept}) async {
    final at = _proposals.indexWhere((p) => identical(p, proposal));
    if (at < 0 || _disposed) return;
    // The card goes first, so a second press finds nothing to answer.
    _proposals.removeAt(at);
    _notify();
    if (!accept) return;
    AssistantMemoryOutcome outcome;
    try {
      outcome = await _entitlement.check() == AssistantEntitlementState.entitled
          ? await applyMemoryProposal(proposal)
          : AssistantMemoryOutcome(proposal.kind, 'not_entitled');
    } catch (e) {
      appLogger.w('Memory field card failed: ${e.runtimeType}');
      outcome = AssistantMemoryOutcome(proposal.kind, 'failed');
    }
    if (_disposed) return;
    _outcome = outcome;
    if (outcome.ok) _overviewStale = true;
    _answer = [_answer, assistantMemoryOutcomeLine(outcome)].where((line) => line.isNotEmpty).join('\n');
    _notify();
  }

  /// Stops the run in progress; its answer is dropped.
  void cancel() {
    _cancel?.abort();
    _asks++;
    if (!_busy) return;
    _busy = false;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _cancel?.abort();
    _disposed = true;
    super.dispose();
  }
}
