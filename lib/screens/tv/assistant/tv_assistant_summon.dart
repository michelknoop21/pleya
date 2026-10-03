/// Big P summoned from any TV screen (mockup 38, "Oproepen vanaf elk
/// scherm"): a long press on Play/Pause brings him in bottom right with a
/// 760 pt glass panel, the screen behind dims but stays the context, and the
/// system keyboard opens right away. After a good result he leaves on his
/// own; an error or a choice stays until Menu.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_run.dart';
import '../../../assistant/assistant_tool_context.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../navigation/tv/tv_content_route_registry.dart';
import '../../../services/apple_tv_native_text_entry.dart';
import '../../../services/apple_tv_remote_touch_service.dart';
import '../../../services/speech_search_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/media_navigation_helper.dart';
import '../../../utils/native_input_session.dart';
import '../../../utils/platform_detector.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/big_p_avatar.dart';
import '../../../widgets/overlay_sheet.dart';
import 'big_p_voice_mouth.dart';
import 'tv_assistant_confirm_flow.dart';
import 'tv_assistant_conversation.dart';
import 'tv_assistant_labels.dart';
import 'tv_assistant_results.dart';
import 'tv_assistant_screen.dart';
import 'tv_assistant_summon_layer.dart';

/// Mounted once in the TV shell, above the content. Listens for the long
/// press only while nothing else owns the remote: not under the player or any
/// other route, not while the system keyboard or a sheet is up.
class TvAssistantSummonHost extends StatefulWidget {
  const TvAssistantSummonHost({
    super.key,
    required this.child,
    this.screenContext,
    this.longPresses,
    this.speech,
    this.textEntry,
  });

  final Widget child;

  /// What the screen behind shows, read at the moment of the press.
  final AssistantScreenContext? Function()? screenContext;

  /// Injected by tests; the app uses the shared instances.
  final Stream<void>? longPresses;
  final SpeechSearchService? speech;
  final AppleTvNativeTextEntry? textEntry;

  /// How long a good result stays before Big P leaves, restarted by any key.
  static const linger = Duration(seconds: 4);

  /// Added to [linger] per character of the answer: time to read it.
  static const lingerPerCharacter = Duration(milliseconds: 60);

  @override
  State<TvAssistantSummonHost> createState() => _TvAssistantSummonHostState();
}

class _TvAssistantSummonHostState extends State<TvAssistantSummonHost> {
  StreamSubscription<void>? _sub;
  AssistantController? _c;
  bool _open = false;
  bool _shown = false;
  bool _leaving = false;
  DateTime _resultAt = DateTime.now();
  FocusNode? _returnTo;
  Timer? _linger;
  Timer? _remove;
  AssistantSurfaceState? _lastState;
  AssistantPendingAction? _shownPending;
  BuildContext? _sheetContext;
  int _nod = 0;
  int _doneSteps = 0;

  final _scope = FocusScopeNode(debugLabel: 'assistant.summon');
  final _panelNode = FocusNode(debugLabel: 'assistant.summon.panel');
  final _askNode = FocusNode(debugLabel: 'assistant.ask');
  final _cancelNode = FocusNode(debugLabel: 'assistant.cancel');
  final _optionNode = FocusNode(debugLabel: 'assistant.option');
  final _confirmCancelNode = FocusNode(debugLabel: 'assistant.confirm.cancel');

  SpeechSearchService get _speech => widget.speech ?? SpeechSearchService.instance;
  AppleTvNativeTextEntry get _entry => widget.textEntry ?? AppleTvNativeTextEntry.instance;

  @override
  void initState() {
    super.initState();
    _sub = (widget.longPresses ?? AppleTvRemoteTouchService.instance.playPauseLongPresses).listen(
      (_) => unawaited(_onLongPress()),
    );
  }

  @override
  void dispose() {
    unawaited(_sub?.cancel());
    _linger?.cancel();
    _remove?.cancel();
    _c?.removeListener(_onChange);
    for (final node in [_panelNode, _askNode, _cancelNode, _optionNode, _confirmCancelNode, _scope]) {
      node.dispose();
    }
    super.dispose();
  }

  /// Play/Pause belongs to the player while one is up; any route above the
  /// shell (the player is one) makes this one not current. Big P's own
  /// surface is a nested shell route, not a Navigator one, so it is asked
  /// itself: a summon there would reset the conversation it shows.
  bool get _remoteIsFree =>
      mounted &&
      !_open &&
      !TvAssistantScreenState.isShowing &&
      PlatformDetector.isAppleTV() &&
      !NativeInputSession.isActive &&
      (ModalRoute.of(context)?.isCurrent ?? true) &&
      !(OverlaySheetController.maybeOf(context)?.isOpen ?? false);

  Future<void> _onLongPress() async {
    if (!_remoteIsFree) return;
    final c = context.read<AssistantController?>();
    if (c == null) return;
    // Nothing reads availability at app start; the press is the first ask.
    if (c.availability == AssistantAvailability.hidden) await c.refreshAvailability();
    if (!_remoteIsFree) return;
    switch (c.availability) {
      case AssistantAvailability.hidden:
        return;
      case AssistantAvailability.locked || AssistantAvailability.needsSetup:
        _openSurface();
      case AssistantAvailability.ready:
        _summon(c);
    }
  }

  /// The full surface shows the locked and set-up gates.
  void _openSurface() {
    Widget builder(BuildContext _) => const TvAssistantScreen();
    if (openTvContentRoute(id: 'tvAssistant', builder: builder) == null) {
      unawaited(Navigator.of(context).push(MaterialPageRoute<void>(builder: builder)));
    }
  }

  void _summon(AssistantController c) {
    _remove?.cancel();
    _returnTo = FocusManager.instance.primaryFocus;
    c.reset();
    _c = c..addListener(_onChange);
    _lastState = c.state;
    setState(() {
      _open = true;
      _shown = false;
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_open) return;
      setState(() => _shown = true);
      _panelNode.requestFocus();
    });
    unawaited(_ask(context: widget.screenContext?.call()));
  }

  /// The system keyboard with dictation and a send key, as on the surface.
  Future<void> _ask({AssistantScreenContext? context}) async {
    final c = _c;
    if (c == null) return;
    c.beginListening(context: context);
    if (c.state != AssistantSurfaceState.listening) return;
    String? text;
    try {
      final result = await _speech.capture(prompt: t.assistant.idle.ask, action: 'send', onPartial: _onPhrase);
      text = result != null && result.submitted ? result.text : null;
    } catch (e) {
      appLogger.w('Big P: text entry failed', error: e);
    }
    if (!mounted || !identical(c, _c) || _leaving) return;
    final question = text?.trim() ?? '';
    if (question.isNotEmpty) {
      unawaited(c.submit(question));
      return;
    }
    c.cancelListening();
    // Backed out of the first question: nothing was asked, Big P leaves.
    if (c.state == AssistantSurfaceState.idle) _dismiss();
  }

  void _onPhrase(String _) {
    if (mounted) setState(() => _nod++);
  }

  void _onChange() {
    final c = _c;
    if (c == null || !mounted) return;
    if (c.state != _lastState) {
      _lastState = c.state;
      if (c.state == AssistantSurfaceState.working) _doneSteps = 0;
      if (c.state == AssistantSurfaceState.result) _resultAt = DateTime.now();
      WidgetsBinding.instance.addPostFrameCallback((_) => _focusDefault());
    }
    final done = c.steps.where((s) => s.phase == AssistantStepPhase.done).length;
    if (done > _doneSteps) _nod++;
    _doneSteps = done;

    final pending = c.pending;
    if (pending != null && !identical(pending, _shownPending)) {
      unawaited(_showConfirm(c, pending));
    } else if (pending == null && _shownPending != null) {
      final sheet = _sheetContext;
      if (sheet != null && sheet.mounted) OverlaySheetController.closeAdaptive(sheet);
    }
    _armLinger();
    setState(() {});
  }

  Future<void> _showConfirm(AssistantController c, AssistantPendingAction pending) async {
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
    if (confirmed && mounted) setState(() => _nod++);
  }

  /// A good result with nothing left to choose: Big P leaves after [linger].
  void _armLinger() {
    _linger?.cancel();
    final c = _c;
    if (c == null || c.state != AssistantSurfaceState.result || c.resultIsError || c.pending != null) return;
    if (tvAssistantHasChoices(c.displays)) return;
    _linger = Timer(
      TvAssistantSummonHost.linger + TvAssistantSummonHost.lingerPerCharacter * assistantHeadline(c).length,
      _dismiss,
    );
  }

  void _focusDefault() {
    final c = _c;
    if (!mounted || c == null || _sheetContext != null) return;
    final node = switch (c.state) {
      AssistantSurfaceState.working => _cancelNode,
      AssistantSurfaceState.result => tvAssistantHasChoices(c.displays) ? _optionNode : _askNode,
      _ => _panelNode,
    };
    (node.context != null && node.canRequestFocus ? node : _panelNode).requestFocus();
  }

  /// A found title in a library: Big P steps aside and its detail page
  /// opens in the shell behind him, as from a catalog card.
  void _openTitle(AssistantTitleTarget target) {
    _dismiss();
    unawaited(navigateToMediaItemDetails(context, target.item));
  }

  /// Menu, Klaar or the linger: Big P slides out, a run in flight or a
  /// waiting card is let go, and the remote is back where it was.
  void _dismiss() {
    if (!_open || _leaving) return;
    _leaving = true;
    _linger?.cancel();
    final c = _c;
    c?.removeListener(_onChange);
    c?.abort();
    setState(() => _shown = false);
    final back = _returnTo;
    _returnTo = null;
    if (back != null && back.context != null && back.canRequestFocus) {
      back.requestFocus();
    } else {
      _scope.unfocus();
    }
    // The run and a waiting card are let go above; the panel keeps its last
    // words while it slides out, then the conversation is cleared.
    _remove = Timer(_motion(context), () {
      c?.reset();
      if (!mounted) return;
      setState(() {
        _c = null;
        _open = false;
        _leaving = false;
      });
    });
  }

  Duration _motion(BuildContext context) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : const Duration(milliseconds: 380);

  KeyEventResult _onKey(FocusNode _, KeyEvent event) {
    if (_linger?.isActive ?? false) _armLinger(); // still reading
    return handleBackKeyAction(event, _dismiss);
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    return Stack(
      fit: StackFit.expand,
      children: [
        widget.child,
        if (_open)
          ExcludeFocus(
            excluding: _leaving,
            child: FocusScope(
              node: _scope,
              child: Focus(
                focusNode: _panelNode,
                // Holds the focus when nothing else can; Up or Down must
                // not land on it and strand the remote.
                skipTraversal: true,
                onKeyEvent: _onKey,
                child: AutomationNode(
                  id: AutomationIds.assistantSummon,
                  role: 'region',
                  state: () => {
                    'shown': _shown,
                    'state': c?.state.name,
                    'error': c?.resultIsError ?? false,
                    'pending': c?.pending != null,
                    'lingering': _linger?.isActive ?? false,
                  },
                  child: _overlay(context, c),
                ),
              ),
            ),
          ),
      ],
    );
  }

  Widget _overlay(BuildContext context, AssistantController? c) {
    final pt = TvHig.of(context);
    return TvAssistantSummonLayer(
      shown: _shown,
      listening: c?.state == AssistantSurfaceState.listening,
      motion: _motion(context),
      panel: c == null
          ? null
          : TvAssistantConversation(
              controller: c,
              name: '',
              servers: '',
              compact: true,
              resultTime: MaterialLocalizations.of(context).formatTimeOfDay(
                TimeOfDay.fromDateTime(_resultAt),
                alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
              ),
              askNode: _askNode,
              cancelNode: _cancelNode,
              firstOptionNode: _optionNode,
              onAsk: () => unawaited(_ask()),
              onDone: _dismiss,
              onCancelWork: _dismiss,
              onExample: (_) {},
              onPickOption: (option) => unawaited(c.pickRequestOption(option)),
              onOpenTitle: _openTitle,
              onArrow: () {
                if (_linger?.isActive ?? false) _armLinger(); // still reading
              },
            ),
      avatar: BigPVoiceMouth(
        controller: c,
        builder: (line) => BigPAvatar(
          mood: c == null ? BigPMood.idle : tvAssistantMood(c),
          size: 340 * pt,
          nodSignal: _nod,
          talkingText: line,
          // He stands right of the panel: point left, down the list.
          pointAt: c?.state == AssistantSurfaceState.working
              ? Alignment(-1, (0.15 * c!.steps.length).clamp(0.0, 1.0))
              : null,
        ),
      ),
    );
  }
}
