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
import '../../../widgets/big_p/assistant/big_p_answer.dart';
import '../../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../../widgets/big_p/assistant/big_p_labels.dart';
import '../../../widgets/big_p/assistant/big_p_results.dart';

/// The node of each task's first choice, owned by the surface. A task keeps
/// its node for as long as its cards are up, so a result that comes in above
/// the remote never takes the node the remote is on.
class TvAssistantTaskOptionNodes {
  final _nodes = <String, FocusNode>{};

  FocusNode of(String taskId) =>
      _nodes.putIfAbsent(taskId, () => FocusNode(debugLabel: 'assistant.task.option.$taskId'));

  /// The first choice on the panel: where the remote starts on a result.
  FocusNode? first(List<AssistantTask> tasks) =>
      _nodes[tasks.where((task) => bigPHasChoices(task.displays)).firstOrNull?.id];

  void dispose() {
    for (final node in _nodes.values) {
      node.dispose();
    }
    _nodes.clear();
  }
}

/// The task cards with their results, scrolling, and under them, always in
/// view, the panel's bottom control ([footer]). A card is not a focus stop;
/// its Annuleren capsule is, while the task can still be stopped. When the
/// capsule under the remote goes, the remote moves to the next capsule down,
/// else to whichever of [footerNodes] is on screen.
///
/// What the remote is on is shown whole, clear of the list's fading edges,
/// and stays where it is when a result comes in above or below it.
class TvAssistantTaskList extends StatefulWidget {
  const TvAssistantTaskList({
    super.key,
    required this.controller,
    required this.footer,
    required this.footerNodes,
    required this.optionNodes,
    required this.onOpenTitle,
    this.followUps,
    this.groupNode,
    this.compact = false,
  });

  final AssistantController controller;
  final Widget footer;
  final List<FocusNode> footerNodes;
  final TvAssistantTaskOptionNodes optionNodes;
  final ValueChanged<AssistantTitleTarget> onOpenTitle;

  /// The follow-ups for the whole question, once every task has ended. After
  /// the cards when there are cards to walk through, else above [footer].
  final Widget? followUps;

  /// Has the focus while the remote is on a capsule or a result, so the
  /// surface can leave it there when a task changes behind it.
  final FocusNode? groupNode;
  final bool compact;

  @override
  State<TvAssistantTaskList> createState() => _TvAssistantTaskListState();
}

class _TvAssistantTaskListState extends State<TvAssistantTaskList> {
  final _cancelNodes = <String, FocusNode>{};
  // The reading stop of each task's answer, and of the list itself when
  // nothing in it can be chosen.
  final _answerNodes = <String, FocusNode>{};
  final _listNode = FocusNode(debugLabel: 'assistant.results');
  // Around all that scrolls: what the remote is on is in the list or not.
  final _contentNode = FocusNode(debugLabel: 'assistant.tasks.content');
  // A list per stand, each with its own controller: for a frame the list
  // that goes and the list that comes are both up.
  final _walkScroll = ScrollController();
  final _readScroll = ScrollController();
  FocusNode? _revealed;
  bool _walkable = true;

  ScrollController get _scroll => _walkable ? _walkScroll : _readScroll;

  FocusNode _cancelNode(String taskId) =>
      _cancelNodes.putIfAbsent(taskId, () => FocusNode(debugLabel: 'assistant.task.cancel.$taskId'));

  FocusNode _answerNode(String taskId) =>
      _answerNodes.putIfAbsent(taskId, () => FocusNode(debugLabel: 'assistant.task.answer.$taskId'));

  /// A node keeps its context after its widget is gone, so ask the context.
  static bool _onScreen(FocusNode node) => (node.context?.mounted ?? false) && node.canRequestFocus;

  @override
  void initState() {
    super.initState();
    FocusManager.instance.addListener(_onFocus);
  }

  @override
  void didUpdateWidget(TvAssistantTaskList oldWidget) {
    super.didUpdateWidget(oldWidget);
    _holdFocused();
    final tasks = widget.controller.tasks;
    // A result under the remote can go: a task's displays are replaced, not
    // only added to. Then on to the first choice left, else the bottom
    // control. A capsule that goes is handed on below.
    final focused = FocusManager.instance.primaryFocus;
    if (focused != null && !_cancelNodes.containsValue(focused) && _rect(focused) != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || _onScreen(focused)) return;
        [widget.optionNodes.first(tasks), ...widget.footerNodes].nonNulls.where(_onScreen).firstOrNull?.requestFocus();
      });
    }
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
    FocusManager.instance.removeListener(_onFocus);
    for (final node in [..._cancelNodes.values, ..._answerNodes.values, _listNode, _contentNode]) {
      node.dispose();
    }
    _walkScroll.dispose();
    _readScroll.dispose();
    // The cards are gone with this list; the next question starts clean.
    widget.optionNodes.dispose();
    super.dispose();
  }

  /// Where [node] sits in the list's box; null when it is not in the list.
  Rect? _rect(FocusNode? node) {
    // Asked of the focus tree first: a node outside the list can be on a
    // card that is closing, and that has no box to ask for any more.
    if (node == null || !node.ancestors.contains(_contentNode) || !_scroll.hasClients) return null;
    final context = node.context;
    final target = context != null && context.mounted ? context.findRenderObject() : null;
    final viewport = _scroll.position.context.notificationContext?.findRenderObject();
    if (target is! RenderBox || viewport is! RenderBox || !target.attached || !target.hasSize) return null;
    RenderObject? box = target.parent;
    while (!identical(box, viewport)) {
      if (box == null) return null;
      box = box.parent;
    }
    return MatrixUtils.transformRect(target.getTransformTo(viewport), Offset.zero & target.size);
  }

  void _onFocus() {
    final node = FocusManager.instance.primaryFocus;
    if (identical(node, _revealed)) return;
    _revealed = node;
    WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
  }

  /// A result that comes in while the remote is in the list moves what is
  /// under it; the list scrolls by as much, as far as it can, so the remote
  /// stays where the viewer left it.
  void _holdFocused() {
    final node = FocusManager.instance.primaryFocus;
    final before = _rect(node)?.top;
    if (before == null) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !identical(node, FocusManager.instance.primaryFocus)) return;
      final after = _rect(node)?.top;
      if (after == null) return;
      final position = _scroll.position;
      final to = (position.pixels + after - before).clamp(0.0, position.maxScrollExtent);
      if ((to - position.pixels).abs() > 0.5) position.jumpTo(to);
      // Where the list could not take it all, e.g. at its end.
      WidgetsBinding.instance.addPostFrameCallback((_) => _reveal());
      WidgetsBinding.instance.ensureVisualUpdate();
    });
  }

  /// Brings what the remote is on, ring included, out of the fading edges.
  void _reveal() {
    if (!mounted) return;
    final box = _rect(FocusManager.instance.primaryFocus);
    if (box == null) return;
    final pt = TvHig.of(context);
    final position = _scroll.position;
    // The 4 pt ring and 8 pt of air around it.
    final target = box.inflate(12 * pt);
    // As far as [BigPEdgeFade] reaches in from an edge with more beyond it.
    final top = 44 * pt;
    final bottom = position.viewportDimension - top;
    final max = position.maxScrollExtent;
    var to = position.pixels;
    if (target.top < top || target.height > bottom - top) {
      to += target.top - top;
    } else if (target.bottom > bottom) {
      to += target.bottom - bottom;
    }
    to = to.clamp(0.0, max);
    // Close to an end the list goes all the way, and that edge stops fading,
    // unless that would push the target into the other edge.
    final snap = 56 * pt;
    if (to < snap && target.bottom + position.pixels <= bottom) {
      to = 0;
    } else if (max - to < snap && target.top - (max - position.pixels) >= top) {
      to = max;
    }
    if ((to - position.pixels).abs() < 0.5) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      position.jumpTo(to);
    } else {
      unawaited(position.animateTo(to, duration: const Duration(milliseconds: 200), curve: Curves.easeInOut));
    }
  }

  /// The answers that run past their four lines, in the order asked.
  List<FocusNode> get _answerStops =>
      [for (final task in widget.controller.tasks) _answerNodes[task.id]].nonNulls.where(_onScreen).toList();

  /// A list read as one holds its answers' reading stops inside its own, out
  /// of the D-pad's reach. An answer at its first or last line hands the
  /// remote to the answer before or after it, and after the last to the list.
  KeyEventResult _onAnswerKey(FocusNode _, KeyEvent event) {
    final up = event.logicalKey == LogicalKeyboardKey.arrowUp;
    if (_walkable || event is KeyUpEvent || (!up && event.logicalKey != LogicalKeyboardKey.arrowDown)) {
      return KeyEventResult.ignored;
    }
    final stops = _answerStops;
    final at = stops.indexWhere((node) => node.hasPrimaryFocus);
    if (at < 0) return KeyEventResult.ignored;
    final next = up
        ? (at > 0 ? stops[at - 1] : null)
        : (at + 1 < stops.length ? stops[at + 1] : (_onScreen(_listNode) ? _listNode : null));
    if (next == null) return KeyEventResult.ignored;
    next.requestFocus();
    return KeyEventResult.handled;
  }

  /// Up from that list, scrolled to its top: the last answer to read on in.
  KeyEventResult _onListKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowUp || !_listNode.hasPrimaryFocus) {
      return KeyEventResult.ignored;
    }
    final last = _answerStops.lastOrNull;
    if (last == null) return KeyEventResult.ignored;
    last.requestFocus();
    return KeyEventResult.handled;
  }

  /// Up from the bottom control lands on the lowest capsule. A result card
  /// below that capsule is nearer and is found by the usual traversal.
  KeyEventResult _onFooterKey(FocusNode _, KeyEvent event) {
    if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowUp) return KeyEventResult.ignored;
    for (final task in widget.controller.tasks.reversed) {
      if (bigPHasChoices(task.displays)) break;
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
    var anyChoices = false;
    var anyCapsule = false;
    final cards = <Widget>[];
    for (final (index, task) in c.tasks.indexed) {
      final cancellable = assistantTaskCancellable(task);
      anyCapsule |= cancellable;
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
      for (final display in task.displays.where((d) => !bigPDisplayIsEmpty(d))) {
        final choices = bigPChoiceCount(display);
        results.add(
          Padding(
            padding: EdgeInsets.only(bottom: choices > 0 ? 0 : 10 * pt),
            child: BigPDisplayView(
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
      anyChoices |= firstOptionTaken;
      // What the task said, above what it shows. Cards are the answer, and an
      // action is named on the task's own card: there the words stay out.
      final answer = task.status == AssistantTaskStatus.completed && task.actions.isEmpty
          ? assistantTaskAnswer(task)
          : '';
      if (!firstOptionTaken && task.actions.isEmpty && ended && answer.isNotEmpty) {
        results.insert(
          0,
          Padding(
            // Room for the reading thumb, which stands right of the text.
            padding: EdgeInsets.only(right: 26 * pt, bottom: 10 * pt),
            // Four lines at once, the rest by Up and Down: never cut short.
            child: BigPAnswer(
              key: ValueKey('assistant.task.answer.${task.id}'),
              text: answer,
              lead: false,
              bodyLines: 4,
              focusNode: _answerNode(task.id),
              style: TextStyle(
                color: tk.text,
                fontSize: TvHig.caption1 * pt,
                height: TvHig.caption1Leading / TvHig.caption1,
              ),
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
    final followUps = widget.followUps;
    _walkable = anyChoices || anyCapsule;
    final content = Focus(
      focusNode: _contentNode,
      canRequestFocus: false,
      skipTraversal: true,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Focus(
            focusNode: widget.groupNode,
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: _onAnswerKey,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: cards,
            ),
          ),
          // After the cards, in the same list: the cards keep the height.
          if (anyChoices && followUps != null) ...[SizedBox(height: 6 * pt), followUps, SizedBox(height: 10 * pt)],
        ],
      ),
    );
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          // Nothing in it to walk through: the list scrolls on Up and Down
          // itself, and an answer longer than its four lines still has its
          // own reading stop.
          child: _walkable
              ? BigPEdgeFade(
                  controller: _walkScroll,
                  builder: (controller) => SingleChildScrollView(controller: controller, child: content),
                )
              : Focus(
                  canRequestFocus: false,
                  skipTraversal: true,
                  onKeyEvent: _onListKey,
                  child: BigPReadableList(controller: _readScroll, focusNode: _listNode, child: content),
                ),
        ),
        SizedBox(height: 16 * pt),
        // Under the scrolling part: always in view, whatever the tasks do.
        if (!anyChoices && followUps != null) ...[followUps, SizedBox(height: 16 * pt)],
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
        child: BigPCard(
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
                  // The title keeps the row; the capsule its own short label.
                  ConstrainedBox(
                    constraints: BoxConstraints(maxWidth: 260 * pt),
                    child: BigPChip(
                      label: t.assistant.result.cancel,
                      semanticLabel: t.assistant.tasks.cancelTask(title: task.title),
                      dense: true,
                      fill: const Color(0x26FFFFFF),
                      focusNode: node,
                      automationId: AutomationIds.assistantTaskCancel,
                      automationInstance: '$index',
                      onSelect: onCancel,
                    ),
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
