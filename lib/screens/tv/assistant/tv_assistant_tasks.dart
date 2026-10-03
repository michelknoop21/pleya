/// Several commands in one question: one compact card per task, in the
/// order asked, each with what it found directly below it. Shared by Big P's
/// surface and the summoned panel through [TvAssistantConversation].
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_theme.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import 'tv_assistant_labels.dart';
import 'tv_assistant_results.dart';
import 'tv_assistant_widgets.dart';

/// The node of each task's first choice, owned by the surface. A task keeps
/// its node for as long as its cards are up, so a result that comes in above
/// the remote never takes the node the remote is on.
class TvAssistantTaskOptionNodes {
  final _nodes = <String, FocusNode>{};

  FocusNode of(String taskId) =>
      _nodes.putIfAbsent(taskId, () => FocusNode(debugLabel: 'assistant.task.option.$taskId'));

  /// The first choice on the panel: where the remote starts on a result.
  FocusNode? first(List<AssistantTask> tasks) =>
      _nodes[tasks.where((task) => tvAssistantHasChoices(task.displays)).firstOrNull?.id];

  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}

/// The task cards, their results and the panel's bottom control ([footer]).
/// A card is not a focus stop; its Annuleren capsule is, while the task can
/// still be stopped. When the capsule under the remote goes, the remote moves
/// to the next capsule down, else to whichever of [footerNodes] is on screen.
class TvAssistantTaskList extends StatefulWidget {
  const TvAssistantTaskList({
    super.key,
    required this.controller,
    required this.footer,
    required this.footerNodes,
    required this.optionNodes,
    required this.onOpenTitle,
    this.groupNode,
    this.compact = false,
  });

  final AssistantController controller;
  final Widget footer;
  final List<FocusNode> footerNodes;
  final TvAssistantTaskOptionNodes optionNodes;
  final ValueChanged<AssistantTitleTarget> onOpenTitle;

  /// Has the focus while the remote is on a capsule or a result, so the
  /// surface can leave it there when a task changes behind it.
  final FocusNode? groupNode;
  final bool compact;

  @override
  State<TvAssistantTaskList> createState() => _TvAssistantTaskListState();
}

class _TvAssistantTaskListState extends State<TvAssistantTaskList> {
  final _cancelNodes = <String, FocusNode>{};

  FocusNode _cancelNode(String taskId) =>
      _cancelNodes.putIfAbsent(taskId, () => FocusNode(debugLabel: 'assistant.task.cancel.$taskId'));

  /// A node keeps its context after its widget is gone, so ask the context.
  static bool _onScreen(FocusNode node) => (node.context?.mounted ?? false) && node.canRequestFocus;

  @override
  void didUpdateWidget(TvAssistantTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    final tasks = widget.controller.tasks;
    final live = {
      for (final task in tasks)
        if (assistantTaskCancellable(task)) task.id,
    };
    final gone = [..._cancelNodes.keys.where((id) => !live.contains(id))];
    if (gone.isEmpty) return;
    final held = gone.where((id) => _cancelNodes[id]!.hasPrimaryFocus).firstOrNull;
    final next = held == null
        ? null
        : tasks.skip(tasks.indexWhere((task) => task.id == held) + 1).where(assistantTaskCancellable).firstOrNull;
    final stale = [for (final id in gone) _cancelNodes.remove(id)!];
    WidgetsBinding.instance.addPostFrameCallback((_) {
      for (final node in stale) {
        node.dispose();
      }
      if (held == null || !mounted) return;
      [_cancelNodes[next?.id], ...widget.footerNodes].nonNulls.where(_onScreen).firstOrNull?.requestFocus();
    });
  }

  @override
  void dispose() {
    for (final node in _cancelNodes.values) {
      node.dispose();
    }
    // The cards are gone with this list; the next question starts clean.
    widget.optionNodes.dispose();
    super.dispose();
  }

  /// Up from the bottom control lands on the lowest capsule. A result card
  /// below that capsule is nearer and is found by the usual traversal.
  KeyEventResult _onFooterKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    for (final task in widget.controller.tasks.reversed) {
      if (tvAssistantHasChoices(task.displays)) break;
      final node = _cancelNodes[task.id];
      if (node != null && _onScreen(node)) {
        node.requestFocus();
        return KeyEventResult.handled;
      }
    }
    return KeyEventResult.ignored;
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    final c = widget.controller;
    var optionOffset = 0;
    final cards = <Widget>[];
    for (final (index, task) in c.tasks.indexed) {
      final cancellable = assistantTaskCancellable(task);
      cards.add(
        _TaskCard(
          key: ValueKey('assistant.task.card.${task.id}'),
          task: task,
          index: index,
          compact: widget.compact,
          cancelNode: cancellable ? _cancelNode(task.id) : null,
          onCancel: () => c.cancelTask(task.id),
        ),
      );
      // The controller takes a pick from a task that has ended; until then
      // a request card shows but is inert, as in a single command.
      final ended = task.status == AssistantTaskStatus.completed || task.status == AssistantTaskStatus.failed;
      var firstOptionTaken = false;
      final results = <Widget>[];
      for (final display in task.displays) {
        final choices = tvAssistantChoiceCount(display);
        results.add(
          Padding(
            padding: EdgeInsets.only(bottom: choices > 0 ? 0 : 10 * pt),
            child: TvAssistantDisplayView(
              display: display,
              onPickOption: ended ? (option) => unawaited(c.pickTaskRequestOption(task.id, option)) : null,
              onOpenTitle: widget.onOpenTitle,
              compact: widget.compact,
              optionOffset: optionOffset,
              firstOptionNode: choices > 0 && !firstOptionTaken ? widget.optionNodes.of(task.id) : null,
            ),
          ),
        );
        if (choices > 0) {
          optionOffset += choices;
          firstOptionTaken = true;
        }
      }
      // A task that only answered: its words are what it has to show.
      if (results.isEmpty && task.actions.isEmpty && ended && task.answer.trim().isNotEmpty) {
        results.add(
          Padding(
            padding: EdgeInsets.only(bottom: 10 * pt),
            child: Text(
              task.answer.trim(),
              maxLines: 4,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, height: 1.25),
            ),
          ),
        );
      }
      if (results.isNotEmpty) {
        cards.add(
          Container(
            key: ValueKey('assistant.task.results.${task.id}'),
            margin: EdgeInsets.only(left: 24 * pt, bottom: 4 * pt),
            padding: EdgeInsets.only(left: 20 * pt),
            decoration: BoxDecoration(
              border: Border(
                left: BorderSide(color: const Color(0x24FFFFFF), width: 2 * pt),
              ),
            ),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: results),
          ),
        );
      }
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Focus(
          focusNode: widget.groupNode,
          canRequestFocus: false,
          skipTraversal: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: cards,
          ),
        ),
        SizedBox(height: 6 * pt),
        Focus(canRequestFocus: false, skipTraversal: true, onKeyEvent: _onFooterKey, child: widget.footer),
      ],
    );
  }
}

class _TaskCard extends StatelessWidget {
  const _TaskCard({
    super.key,
    required this.task,
    required this.index,
    required this.compact,
    required this.cancelNode,
    required this.onCancel,
  });

  final AssistantTask task;
  final int index;
  final bool compact;
  final FocusNode? cancelNode;
  final VoidCallback onCancel;

  Widget _icon(BuildContext context) {
    final size = 30 * TvHig.of(context);
    final ink = tokens(context).text;
    return switch (task.status) {
      AssistantTaskStatus.pending => Icon(
        Symbols.radio_button_unchecked_rounded,
        color: ink.withValues(alpha: 0.3),
        size: size,
      ),
      AssistantTaskStatus.running => Icon(Symbols.radio_button_checked_rounded, color: ink, size: size),
      AssistantTaskStatus.waitingForConfirmation => Icon(
        Symbols.pause_circle_rounded,
        fill: 1,
        color: kNoticeWarningDark,
        size: size,
      ),
      AssistantTaskStatus.completed => Icon(Symbols.check_circle_rounded, fill: 1, color: kSuccess, size: size),
      AssistantTaskStatus.failed => Icon(Symbols.cancel_rounded, fill: 1, color: kNoticeErrorDark, size: size),
      AssistantTaskStatus.cancelled => Icon(
        Symbols.do_not_disturb_on_rounded,
        color: ink.withValues(alpha: 0.3),
        size: size,
      ),
    };
  }

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final ink = tokens(context).text;
    final muted = ink.withValues(alpha: 0.6);
    final (:status, :detail) = assistantTaskStatusLabel(task);
    final quiet = task.status == AssistantTaskStatus.pending || task.status == AssistantTaskStatus.cancelled;
    final statusColor = switch (task.status) {
      AssistantTaskStatus.completed => ink,
      AssistantTaskStatus.waitingForConfirmation => kNoticeWarningDark,
      AssistantTaskStatus.failed => kNoticeErrorDark,
      _ => muted,
    };
    return Padding(
      padding: EdgeInsets.only(bottom: 10 * pt),
      child: AutomationNode(
        id: AutomationIds.assistantTask,
        instance: '$index',
        role: 'list.item',
        state: () => {'id': task.id, 'status': task.status.name, 'cancellable': cancelNode != null},
        child: TvAssistantCard(
          padding: EdgeInsets.symmetric(horizontal: compact ? 20 : 24, vertical: 16),
          child: ConstrainedBox(
            constraints: BoxConstraints(minHeight: 64 * pt),
            child: Row(
              children: [
                _icon(context),
                SizedBox(width: (compact ? 14 : 18) * pt),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        task.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: quiet ? muted : ink,
                          fontSize: TvHig.caption1 * pt,
                          fontWeight: FontWeight.w600,
                          decoration: task.status == AssistantTaskStatus.cancelled ? TextDecoration.lineThrough : null,
                          decorationColor: ink.withValues(alpha: 0.3),
                        ),
                      ),
                      SizedBox(height: 4 * pt),
                      Text.rich(
                        TextSpan(
                          children: [
                            TextSpan(
                              text: status,
                              style: TextStyle(
                                color: statusColor,
                                fontWeight: statusColor == muted ? null : FontWeight.w500,
                              ),
                            ),
                            if (detail != null) TextSpan(text: ' · $detail'),
                          ],
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(color: muted, fontSize: TvHig.caption2 * pt),
                      ),
                    ],
                  ),
                ),
                if (cancelNode case final node?) ...[
                  SizedBox(width: (compact ? 14 : 18) * pt),
                  TvAssistantChip(
                    label: t.assistant.result.cancel,
                    semanticLabel: t.assistant.tasks.cancelTask(title: task.title),
                    dense: true,
                    focusNode: node,
                    automationId: AutomationIds.assistantTaskCancel,
                    automationInstance: '$index',
                    onSelect: onCancel,
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
