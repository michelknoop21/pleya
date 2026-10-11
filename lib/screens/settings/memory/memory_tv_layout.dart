import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/focus_memory_tracker.dart';
import '../../../focus/key_event_utils.dart';
import '../../../i18n/strings.g.dart';
import '../../../services/speech_search_service.dart';
import '../../../utils/app_logger.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/tv/tv_page_surface.dart';
import 'memory_actions.dart';
import 'memory_composer.dart';
import 'memory_labels.dart';
import 'memory_screen_model.dart';
import 'memory_tv_answer.dart';
import 'memory_tv_read.dart';
import 'memory_tv_text.dart';
import 'memory_tv_widgets.dart';

/// Geheugen on TV (43 M): the overview to read on the left, the tiles on the
/// right. "Vraag of werk bij" opens the system keyboard or dictation; under
/// it the follow-up questions and the management controls, with "Overzicht
/// opnieuw schrijven" as the fourth. A waiting card takes the place of the
/// tiles, with the remote on its safe button and Menu as the no.
class MemoryTvLayout extends StatefulWidget {
  const MemoryTvLayout({
    super.key,
    required this.model,
    required this.actions,
    required this.speech,
    required this.onBack,
  });

  final MemoryScreenModel model;
  final MemoryActionCallbacks actions;
  final SpeechSearchService speech;
  final VoidCallback onBack;

  @override
  State<MemoryTvLayout> createState() => _MemoryTvLayoutState();
}

class _MemoryTvLayoutState extends State<MemoryTvLayout> {
  final _nodes = FocusMemoryTracker();
  final _readNode = FocusNode(debugLabel: 'memory.tv.read');
  final _answerNode = FocusNode(debugLabel: 'memory.tv.answer');
  bool _answerStop = false;
  bool _landed = false;
  bool _cardShown = false;

  MemoryScreenModel get _model => widget.model;

  @override
  void dispose() {
    _nodes.dispose();
    _readNode.dispose();
    _answerNode.dispose();
    super.dispose();
  }

  void _focus(String key) {
    final node = _nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  void _focusLater(String key) => WidgetsBinding.instance.addPostFrameCallback((_) {
    if (mounted) _focus(key);
  });

  /// The system keyboard or dictation. What comes back is the viewer's own
  /// words, so it goes in as typed.
  Future<void> _ask() async {
    if (!_model.canAsk || _model.host.busy) return;
    String? text;
    try {
      text = await memoryTvCaptureText(context, widget.speech, prompt: t.assistant.memory.screen.ask);
    } catch (e) {
      appLogger.w('Memory screen: text entry failed: ${e.runtimeType}');
    }
    if (!mounted) return;
    _focusLater('ask');
    final question = text?.trim() ?? '';
    if (question.isNotEmpty) unawaited(_model.host.ask(question));
  }

  void _back() {
    final proposal = _model.host.proposal;
    // Menu on a waiting card is the no; the screen stays.
    if (proposal != null) return unawaited(_model.host.answerProposal(proposal, accept: false));
    widget.onBack();
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final s = t.assistant.memory.screen;
    final status = memoryStatusLabel(_model);
    final proposal = _model.host.proposal;

    final tiles = proposal == null ? _tiles() : const <_Tile>[];
    final keys = [for (final tile in tiles) tile.key];
    final held = _nodes.lastFocusedKey;
    // Where the remote lands: the switch while the memory is off, otherwise
    // the first tile that does something.
    final landing = _model.view == MemoryScreenView.off && keys.contains('use')
        ? 'use'
        : (tiles.where((tile) => tile.onSelect != null).firstOrNull ?? tiles.firstOrNull)?.key;
    void land() {
      final key = landing;
      if (key != null) _focusLater(key);
    }

    if (proposal != null) {
      _cardShown = true;
    } else if (landing != null) {
      if (_cardShown || !_landed) {
        // First paint and after a card.
        land();
        _landed = true;
      } else if (held != null && _nodes.isFocused(held) && !keys.contains(held)) {
        // The tile under the remote goes away (the overview is rewritten).
        land();
      } else if (held == 'clear' && _nodes.isFocused('clear') && tiles.last.onSelect == null) {
        // Everything is wiped: the tile that did it has nothing left to do.
        land();
      }
      _cardShown = false;
    }
    final answer = proposal == null && _model.answerShown;
    // The stop belongs to the answer on screen: a card or a wipe takes the
    // answer away without a word from it, and the next one starts short.
    if (!answer) _answerStop = false;
    void toRead() {
      if (_readNode.canRequestFocus) _readNode.requestFocus();
    }

    return Focus(
      canRequestFocus: false,
      skipTraversal: true,
      onKeyEvent: (_, event) => handleBackKeyAction(event, _back),
      child: Material(
        type: MaterialType.transparency,
        child: TvPageSurface(
          title: s.title,
          automationInstance: 'assistant_memory',
          expanded: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: MemoryTvReadColumn(
                  model: _model,
                  node: _readNode,
                  onRight: keys.isEmpty
                      ? null
                      : () {
                          // Back to the tile the remote left for the text.
                          final last = _nodes.lastFocusedKey;
                          _focus(last != null && keys.contains(last) ? last : keys.first);
                        },
                ),
              ),
              SizedBox(width: 72 * pt),
              SizedBox(
                width: 740 * pt,
                child: SingleChildScrollView(
                  padding: EdgeInsets.only(bottom: 24 * pt),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (proposal != null) ...[
                        MemoryAnswerPanel(model: _model, remote: true),
                        SizedBox(height: 14 * pt),
                      ] else if (answer) ...[
                        MemoryTvAnswer(
                          model: _model,
                          node: _answerNode,
                          onStopChanged: (stop) => setState(() => _answerStop = stop),
                          onLeave: () {
                            if (keys.isNotEmpty) _focus(keys.first);
                          },
                          onLeft: toRead,
                        ),
                        SizedBox(height: 14 * pt),
                      ],
                      for (final (i, tile) in tiles.indexed) ...[
                        if (tile.label case final label?) MemoryTvLabel(label, first: i == 0, top: 2),
                        if (tile.label == null && i > 0) SizedBox(height: 2 * pt),
                        MemoryTvTile(
                          title: tile.title,
                          subtitle: tile.subtitle,
                          value: tile.value,
                          icon: tile.icon,
                          compact: tile.subtitle == null,
                          titleLines: tile.followUp != null ? 2 : 1,
                          node: _nodes.get(tile.key, debugLabel: 'memory.tv.${tile.key}'),
                          instance: tile.followUp == null ? tile.key : '${tile.followUp}',
                          automationId: tile.followUp == null
                              ? AutomationIds.settingsMemoryAction
                              : AutomationIds.settingsMemoryFollowUp,
                          state: tile.state,
                          onSelect: tile.onSelect,
                          // Up from the first tile: into a long answer, or
                          // on to the top navigation.
                          onNavigateUp: i == 0
                              ? (answer && _answerStop ? _answerNode.requestFocus : null)
                              : () => _focus(keys[i - 1]),
                          onNavigateDown: i == keys.length - 1 ? () {} : () => _focus(keys[i + 1]),
                          onNavigateLeft: toRead,
                          onNavigateRight: () {},
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
          ),
          // The state on the row of the title, as 43 M draws it.
          trailing: status.isEmpty ? null : Text(status, style: memoryTvSmall(context)),
          children: const [],
        ),
      ),
    );
  }

  /// The tiles of the right column for the state the screen is in.
  List<_Tile> _tiles() {
    final s = t.assistant.memory.screen;
    final model = _model;
    final view = model.view;
    if (view == MemoryScreenView.loading) return const [];
    final facts = model.facts;
    final busy = model.host.busy;
    final followUps = view == MemoryScreenView.overview ? model.overview!.followUps : const <String>[];
    final field = view != MemoryScreenView.kids && view != MemoryScreenView.error;
    return [
      // No field on a children's profile: Big P uses no memory there.
      if (field)
        _Tile(
          'ask',
          s.ask,
          icon: Symbols.chat_bubble_rounded,
          subtitle: busy ? s.status.asking : s.askTvHint,
          onSelect: model.canAsk && !busy ? () => unawaited(_ask()) : null,
        ),
      for (final (i, question) in followUps.indexed)
        _Tile(
          'followUp$i',
          question,
          icon: Symbols.subdirectory_arrow_right_rounded,
          label: i == 0 ? s.deeper : null,
          followUp: i,
          // Written by the model: asked as a follow-up, never as typed.
          onSelect: busy ? null : () => unawaited(model.host.askFollowUp(question)),
        ),
      if (view == MemoryScreenView.error)
        _Tile('retry', t.common.retry, icon: Symbols.refresh_rounded, onSelect: () => unawaited(model.load())),
      _Tile(
        'manage',
        s.menu.manage,
        icon: Symbols.description_rounded,
        label: s.menu.management,
        value: facts == null ? null : '${facts.length}',
        onSelect: widget.actions.openList,
      ),
      // Not on a children's profile: Big P uses no memory there, whatever
      // the switch says.
      if (view != MemoryScreenView.kids)
        _Tile(
          'use',
          model.enabled ? s.menu.useOn : s.menu.useOff,
          icon: model.enabled ? Symbols.toggle_on_rounded : Symbols.toggle_off_rounded,
          state: () => {'selected': model.enabled},
          onSelect: widget.actions.toggle,
        ),
      if (model.canAsk && model.count > 0)
        _Tile('rewrite', s.menu.rewrite, icon: Symbols.edit_note_rounded, onSelect: widget.actions.rewrite),
      // Resting colour, as 43 M draws it; the colour of a destructive tile on
      // TV waits for the ACTION-ERROR-CONTRAST decision.
      _Tile(
        'clear',
        s.menu.clear,
        icon: Symbols.delete_rounded,
        onSelect: facts != null && facts.isEmpty ? null : widget.actions.clear,
      ),
    ];
  }
}

/// One tile of the right column.
class _Tile {
  const _Tile(
    this.key,
    this.title, {
    this.icon,
    this.subtitle,
    this.value,
    this.label,
    this.followUp,
    this.onSelect,
    this.state,
  });

  final String key;
  final String title;
  final IconData? icon;
  final String? subtitle;
  final String? value;

  /// The group label above this tile.
  final String? label;

  /// The index of a follow-up question, for its automation instance.
  final int? followUp;
  final VoidCallback? onSelect;
  final Map<String, Object?> Function()? state;
}
