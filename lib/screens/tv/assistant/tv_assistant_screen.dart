/// Big P's surface on TV (mockup 38, DEC-142): a larger, living Big P on the
/// left and an 800 pt glass panel on the right that holds the conversation,
/// newest at the bottom. Opened from the Mijn Pleya tile, or from a
/// library's "Vraag Big P" with that library as context.
///
/// The surface only reads [AssistantController] and calls it. What Pleya
/// shows (steps, actions, the confirmation card) is built from controller
/// data; the model's answer is shown as text and nothing more.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_run.dart';
import '../../../assistant/assistant_tool_context.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../assistant/big_p_voice.dart';
import '../../../widgets/big_p/assistant/big_p_voice_mouth.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../automation/automation_screen.dart';
import '../../../i18n/strings.g.dart';
import '../../../media/ids.dart';
import '../../../mixins/refreshable.dart';
import '../../../navigation/tv/tv_content_route_registry.dart';
import '../../../navigation/tv/tv_nested_surface.dart';
import '../../../profiles/active_profile_provider.dart';
import '../../../providers/multi_server_provider.dart';
import '../../../services/apple_tv_native_text_entry.dart';
import '../../../services/speech_search_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/dialogs.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/big_p_avatar.dart';
import '../../../widgets/big_p/assistant/big_p_labels.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../settings/assistant_settings_screen.dart';
import 'tv_assistant_confirm_flow.dart';
import 'tv_assistant_conversation.dart';
import 'tv_assistant_gate.dart';
import '../../../widgets/big_p/assistant/big_p_results.dart';
import '../../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../../widgets/big_p/assistant/big_p_suggestions.dart';

class TvAssistantScreen extends StatefulWidget {
  const TvAssistantScreen({super.key, this.screenContext, this.speech, this.textEntry});

  /// Where the surface was opened from. Set, the keyboard opens right away.
  final AssistantScreenContext? screenContext;

  /// Injected by tests; the app uses the shared instances.
  final SpeechSearchService? speech;
  final AppleTvNativeTextEntry? textEntry;

  @override
  State<TvAssistantScreen> createState() => TvAssistantScreenState();
}

class TvAssistantScreenState extends State<TvAssistantScreen> with FocusableTab {
  static final _mounted = <TvAssistantScreenState>{};

  /// Whether Big P's own surface is on screen. A destination left for
  /// another tab stays mounted offstage, with its tickers muted.
  static bool get isShowing => _mounted.any((s) => TickerMode.getNotifier(s.context).value);

  AssistantController? _c;
  final _askNode = FocusNode(debugLabel: 'assistant.ask');
  final _cancelNode = FocusNode(debugLabel: 'assistant.cancel');
  final _optionNode = FocusNode(debugLabel: 'assistant.option');
  final _gateNode = FocusNode(debugLabel: 'assistant.gate');
  final _confirmCancelNode = FocusNode(debugLabel: 'assistant.confirm.cancel');

  int _nod = 0;
  DateTime _lastPhraseNod = DateTime.fromMillisecondsSinceEpoch(0);
  int _doneSteps = 0;
  AssistantSurfaceState? _lastState;
  AssistantAvailability? _lastAvailability;
  DateTime _resultAt = DateTime.now();
  AssistantPendingAction? _shownPending;
  BuildContext? _sheetContext;

  SpeechSearchService get _speech => widget.speech ?? SpeechSearchService.instance;
  AppleTvNativeTextEntry get _entry => widget.textEntry ?? AppleTvNativeTextEntry.instance;

  @override
  void initState() {
    super.initState();
    _mounted.add(this);
    // One visit, one set of examples: picked before the first frame.
    if (context.read<AssistantController?>() case final c?) BigPSuggestions.of(c).summoned();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      final c = _c;
      if (!mounted || c == null) return;
      // One visit, one conversation: a run left behind on an earlier visit
      // is let go rather than shown half-finished.
      c.reset();
      if (widget.screenContext != null && c.availability == AssistantAvailability.ready) {
        unawaited(_ask());
      } else {
        focusActiveTabIfReady();
        if (c.availability == AssistantAvailability.ready) unawaited(BigPVoice.of(c)?.say(BigPMoment.greet));
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final c = context.read<AssistantController?>();
    if (identical(c, _c)) return;
    _c?.removeListener(_onChange);
    _c = c?..addListener(_onChange);
    _lastState = c?.state;
    _lastAvailability = c?.availability;
  }

  @override
  void dispose() {
    _mounted.remove(this);
    _c?.removeListener(_onChange);
    // Leaving Big P stops the ask, as the summoned panel's dismissal does.
    // abort() does not notify, so this is safe while the tree unmounts.
    _c?.abort();
    for (final node in [_askNode, _cancelNode, _optionNode, _gateNode, _confirmCancelNode]) {
      node.dispose();
    }
    super.dispose();
  }

  void _onChange() {
    final c = _c;
    if (c == null || !mounted) return;
    if (c.state != _lastState) {
      _lastState = c.state;
      if (c.state == AssistantSurfaceState.working) _doneSteps = 0;
      if (c.state == AssistantSurfaceState.result) _resultAt = DateTime.now();
      _focusDefaultSoon();
    }
    if (c.availability != _lastAvailability) {
      _lastAvailability = c.availability;
      _focusDefaultSoon();
    }
    final done = c.steps.where((s) => s.phase == AssistantStepPhase.done).length;
    if (done > _doneSteps) _nod++; // finger up: a step finished
    _doneSteps = done;

    final pending = c.pending;
    if (pending != null && !identical(pending, _shownPending)) {
      unawaited(_showConfirm(pending));
    } else if (pending == null && _shownPending != null) {
      // Timed out or reset under the card: take it away.
      final sheet = _sheetContext;
      if (sheet != null && sheet.mounted) OverlaySheetController.closeAdaptive(sheet);
    }
    setState(() {});
  }

  FocusNode? get _defaultNode {
    final c = _c;
    if (c == null) return null;
    return switch (c.availability) {
      AssistantAvailability.hidden => null,
      AssistantAvailability.locked || AssistantAvailability.needsSetup => _gateNode,
      AssistantAvailability.ready => switch (c.state) {
        AssistantSurfaceState.idle => _askNode,
        AssistantSurfaceState.listening => null,
        AssistantSurfaceState.working => _cancelNode,
        AssistantSurfaceState.result => bigPHasChoices(c.displays) ? _optionNode : _askNode,
      },
    };
  }

  @override
  void focusActiveTabIfReady() {
    if (_sheetContext != null) return; // the card owns the remote
    final node = _defaultNode;
    if (node != null && node.context != null && node.canRequestFocus) node.requestFocus();
  }

  void _focusDefaultSoon() => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) focusActiveTabIfReady();
  });

  void _onPhrase(String _) {
    final now = DateTime.now();
    if (now.difference(_lastPhraseNod) < const Duration(seconds: 1)) return;
    _lastPhraseNod = now;
    if (mounted) setState(() => _nod++);
  }

  /// "Vraag Big P": the system keyboard with dictation, a send key, and the
  /// question goes to the controller only when the viewer sent it.
  Future<void> _ask() async {
    final c = _c;
    if (c == null) return;
    c.beginListening(context: widget.screenContext);
    if (c.state != AssistantSurfaceState.listening) return;
    String? text;
    try {
      if (await _speech.isSupported()) {
        final result = await _speech.capture(prompt: t.assistant.idle.ask, action: 'send', onPartial: _onPhrase);
        text = result != null && result.submitted ? result.text : null;
      } else if (mounted) {
        text = await showTextInputDialog(
          context,
          title: t.assistant.idle.ask,
          labelText: t.assistant.listening.body,
          hintText: '',
        );
      }
    } catch (e) {
      appLogger.w('Big P: text entry failed', error: e);
    }
    if (!mounted || !identical(c, _c)) return;
    final question = text?.trim() ?? '';
    if (question.isEmpty) {
      c.cancelListening();
    } else {
      unawaited(c.submit(question));
    }
  }

  void _askExample(String example) {
    final c = _c;
    if (c == null) return;
    c.beginListening(context: widget.screenContext);
    unawaited(c.submit(example));
  }

  Future<void> _showConfirm(AssistantPendingAction pending) async {
    final c = _c;
    if (c == null) return;
    _shownPending = pending;
    final confirmed = await showTvAssistantConfirm(
      context,
      controller: c,
      pending: pending,
      cancelNode: _confirmCancelNode,
      entry: _entry,
      onSheet: (sheet) => _sheetContext = sheet,
    );
    _shownPending = null;
    if (confirmed && mounted) setState(() => _nod++); // Big P nods when you confirm
  }

  void _dismiss() {
    final scope = TvNestedRouteScope.readOf(context);
    if (scope != null) {
      scope.dismiss();
    } else {
      unawaited(Navigator.maybePop(context));
    }
  }

  void _openSetup() {
    Widget builder(BuildContext _) => const AssistantSettingsScreen();
    final c = context.read<AssistantController?>();
    // A save refreshes through the store's change signal; the close reads
    // again too, so a keychain that recovered meanwhile ends the set-up gate.
    final closed =
        openTvContentRoute(id: 'tvAssistantSetup', builder: builder) ??
        Navigator.of(context).push<Object?>(MaterialPageRoute<Object?>(builder: builder));
    unawaited(closed.then((_) => c?.refreshAvailability()));
  }

  String _servers() {
    final manager = context.read<MultiServerProvider?>()?.serverManager;
    if (manager == null) return '';
    return [
      for (final id in manager.serverIds)
        if (manager.isServerVisible(ServerId(id)) && manager.canAdministerServer(ServerId(id)))
          manager.serverDisplayName(ServerId(id)),
    ].join(', ');
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    if (c == null || c.availability == AssistantAvailability.hidden) return const SizedBox.shrink();
    final mood = bigPMood(c);
    final Widget body = switch (c.availability) {
      AssistantAvailability.locked || AssistantAvailability.needsSetup => TvAssistantGate(
        locked: c.availability == AssistantAvailability.locked,
        primaryNode: _gateNode,
        onSetup: _openSetup,
        onBack: _dismiss,
      ),
      _ => _active(context, c, mood),
    };
    return AutomationScreen(
      id: AutomationIds.screenAssistant,
      readiness: () => const AutomationReadiness.ready(),
      child: AutomationNode(
        id: AutomationIds.screenAssistant,
        role: 'screen',
        state: () => {
          'availability': c.availability.name,
          'state': c.state.name,
          'mood': mood.name,
          'error': c.resultIsError,
          'pending': c.pending != null,
        },
        child: body,
      ),
    );
  }

  Widget _active(BuildContext context, AssistantController c, BigPMood mood) {
    final pt = TvHig.of(context);
    final working = c.state == AssistantSurfaceState.working;
    final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(_resultAt),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return LayoutBuilder(
      builder: (context, box) => Padding(
        padding: EdgeInsets.only(top: 30 * pt, right: 250 * pt, bottom: 80 * pt),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: EdgeInsets.only(bottom: 100 * pt),
                child: Center(
                  child: RepaintBoundary(
                    child: BigPVoiceMouth(
                      controller: c,
                      builder: (line) => BigPAvatar(
                        mood: mood,
                        size: (560 * pt).clamp(0.0, box.maxHeight * 0.75),
                        nodSignal: _nod,
                        talkingText: line,
                        // Working: the arm follows the newest step down the list.
                        pointAt: working ? Alignment(1, (0.15 * c.steps.length).clamp(0.0, 1.0)) : null,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(
              width: 800 * pt,
              child: ConstrainedBox(
                constraints: BoxConstraints(maxHeight: box.maxHeight - 110 * pt),
                child: BigPGlassPanel(
                  child: TvAssistantConversation(
                    controller: c,
                    name: context.watch<ActiveProfileProvider?>()?.active?.displayName ?? '',
                    servers: _servers(),
                    resultTime: time,
                    askNode: _askNode,
                    cancelNode: _cancelNode,
                    firstOptionNode: _optionNode,
                    onAsk: () => unawaited(_ask()),
                    onDone: () {
                      c.reset();
                      _dismiss();
                    },
                    onCancelWork: c.reset,
                    onExample: _askExample,
                    onPickOption: (option) => unawaited(c.pickRequestOption(option)),
                    // Opens over the surface; Menu comes back to these results.
                    onOpenTitle: (target) => unawaited(navigateToMediaItemDetails(context, target.item)),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
