import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/focusable_text_field.dart';
import '../../../focus/input_mode_tracker.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../widgets/app_icon.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart';
import '../../../widgets/big_p/big_p_scale.dart';
import '../../../widgets/loading_indicator_box.dart';
import 'memory_labels.dart';
import 'memory_screen_model.dart';
import 'memory_widgets.dart';

/// What stands at the bottom of the memory screen (43 A, H): Big P's answer
/// and a waiting card, and under them the field "Vraag of werk bij".
class MemoryComposer extends StatelessWidget {
  const MemoryComposer({super.key, required this.model});

  final MemoryScreenModel model;

  @override
  Widget build(BuildContext context) => Column(
    mainAxisSize: MainAxisSize.min,
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      if (model.answerShown) ...[Flexible(child: MemoryAnswerPanel(model: model)), const SizedBox(height: 10)],
      MemoryInputBar(model: model),
    ],
  );
}

/// Big P's answer to the last question of the field, and the card that waits
/// for a yes or a no (43 H). The card opens with the focus on the safe button.
class MemoryAnswerPanel extends StatefulWidget {
  const MemoryAnswerPanel({super.key, required this.model, this.remote = false});

  final MemoryScreenModel model;

  /// Driven by a remote (TV): the focus is the white button.
  final bool remote;

  @override
  State<MemoryAnswerPanel> createState() => _MemoryAnswerPanelState();
}

class _MemoryAnswerPanelState extends State<MemoryAnswerPanel> {
  final _declineNode = FocusNode(debugLabel: 'memory.card.decline');
  AssistantMemoryProposal? _focusedFor;

  @override
  void dispose() {
    _declineNode.dispose();
    super.dispose();
  }

  /// A new card takes the focus on its safe button, where a remote or a
  /// keyboard drives the screen.
  void _focusCard(AssistantMemoryProposal? proposal) {
    if (identical(proposal, _focusedFor)) return;
    _focusedFor = proposal;
    if (proposal == null || !(widget.remote || InputModeTracker.isKeyboardMode(context))) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && identical(_focusedFor, proposal) && _declineNode.context != null) _declineNode.requestFocus();
    });
  }

  @override
  Widget build(BuildContext context) {
    final model = widget.model;
    final host = model.host;
    final tk = tokens(context);
    final k = MemoryScale.of(context);
    final proposal = host.proposal;
    _focusCard(proposal);
    final failure = host.failure;
    final text = host.answer.isNotEmpty ? host.answer : (failure == null ? '' : memoryAskFailure(failure));
    final answer = Container(
      padding: EdgeInsets.fromLTRB(14 * k, 10 * k, 6 * k, 12 * k),
      decoration: BoxDecoration(
        color: tk.surfaceElevated,
        borderRadius: BorderRadius.circular(14 * k),
        border: Border.all(color: tk.outline),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(height: 4 * k),
                Text(
                  '${t.assistant.youAsked} ${host.question ?? ''}',
                  maxLines: proposal == null ? 3 : 1,
                  overflow: TextOverflow.ellipsis,
                  style: memoryText(context, 13, color: tk.textMuted, height: 1.35),
                ),
                SizedBox(height: 6 * k),
                if (host.busy)
                  Row(
                    children: [
                      LoadingIndicatorBox(size: 14 * k),
                      SizedBox(width: 10 * k),
                      Expanded(
                        child: Text(
                          t.assistant.memory.screen.status.asking,
                          style: memoryText(context, 15, color: tk.textMuted),
                        ),
                      ),
                    ],
                  )
                else if (text.isNotEmpty)
                  // Above a waiting card the first lines stay; the card keeps
                  // its buttons in view.
                  Text(
                    text,
                    maxLines: proposal == null ? null : 3,
                    overflow: proposal == null ? null : TextOverflow.ellipsis,
                    style: memoryText(context, 15.5, weight: FontWeight.w600, height: 1.4),
                  ),
              ],
            ),
          ),
          if (!host.busy && proposal == null && !widget.remote)
            MemoryPressable(
              shape: const CircleBorder(),
              semanticLabel: t.assistant.memory.screen.dismissAnswer,
              automationId: AutomationIds.settingsMemoryAction,
              automationInstance: 'dismiss',
              onPressed: model.dismissAnswer,
              child: SizedBox(
                width: 44,
                height: 44,
                child: Center(child: AppIcon(Symbols.close_rounded, size: 20, color: tk.textMuted)),
              ),
            )
          else
            SizedBox(width: 8 * k),
        ],
      ),
    );

    if (proposal == null) return SingleChildScrollView(child: answer);
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        answer,
        SizedBox(height: 10 * k),
        // The rows of the card scroll when room is short; its two buttons
        // never leave the screen.
        Flexible(
          child: DecoratedBox(
            decoration: BoxDecoration(color: tk.surfaceElevated, borderRadius: BorderRadius.circular(14 * k)),
            // The card of the conversation, at the size the balloon draws it
            // on a phone; on TV it takes the tvOS sizes by itself.
            child: _scaled(
              BigPMemoryCard(
                key: ObjectKey(proposal),
                proposal: proposal,
                embedded: true,
                remote: widget.remote,
                declineNode: _declineNode,
                onAccept: () => unawaited(host.answerProposal(proposal, accept: true)),
                onDecline: () => unawaited(host.answerProposal(proposal, accept: false)),
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _scaled(Widget card) => widget.remote ? card : BigPScale(pt: 0.53, child: card);
}

/// The field "Vraag of werk bij" (`.cfield`). What is typed here is the
/// user's own words: the one way in that can store a new fact at once.
class MemoryInputBar extends StatefulWidget {
  const MemoryInputBar({super.key, required this.model});

  final MemoryScreenModel model;

  @override
  State<MemoryInputBar> createState() => _MemoryInputBarState();
}

class _MemoryInputBarState extends State<MemoryInputBar> {
  final _text = TextEditingController();
  final _focus = FocusNode(debugLabel: 'memory.input');

  @override
  void initState() {
    super.initState();
    _text.addListener(_changed);
    _focus.addListener(_changed);
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _text.dispose();
    _focus.dispose();
    super.dispose();
  }

  bool get _open {
    final model = widget.model;
    return model.canAsk && !model.host.busy && model.host.proposal == null;
  }

  void _send() {
    final question = _text.text.trim();
    if (question.isEmpty || !_open) return;
    _text.clear();
    _focus.unfocus();
    // Typed by the user: `ask`, never the follow-up path.
    unawaited(widget.model.host.ask(question));
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final model = widget.model;
    final open = _open;
    final ready = open && _text.text.trim().isNotEmpty;
    final style = memoryText(context, 16, height: 1.35);
    // While Big P works or a card waits the field shows what was asked.
    final sent = !open && model.canAsk ? model.host.question : null;
    return Opacity(
      opacity: model.canAsk ? 1 : 0.38,
      child: Container(
        constraints: const BoxConstraints(minHeight: 52),
        padding: const EdgeInsets.fromLTRB(18, 7, 7, 7),
        decoration: BoxDecoration(
          color: tk.surface,
          borderRadius: BorderRadius.circular(26),
          border: Border.all(color: _focus.hasFocus ? tk.text.withValues(alpha: 0.55) : tk.outline),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 8),
                child: AutomationNode(
                  id: AutomationIds.settingsMemoryInput,
                  role: 'field',
                  focusNode: _focus,
                  state: () => {'enabled': open},
                  child: FocusableTextField(
                    controller: _text,
                    focusNode: _focus,
                    enabled: open,
                    minLines: 1,
                    maxLines: 4,
                    textInputAction: TextInputAction.send,
                    textCapitalization: TextCapitalization.sentences,
                    style: style,
                    decoration: InputDecoration(
                      isCollapsed: true,
                      filled: false,
                      border: InputBorder.none,
                      enabledBorder: InputBorder.none,
                      focusedBorder: InputBorder.none,
                      disabledBorder: InputBorder.none,
                      contentPadding: EdgeInsets.zero,
                      hintText: sent ?? t.assistant.memory.screen.ask,
                      hintMaxLines: 2,
                      hintStyle: style.copyWith(color: sent == null ? memoryFaint(context) : tk.textMuted),
                    ),
                    onSubmitted: (_) => _send(),
                  ),
                ),
              ),
            ),
            const SizedBox(width: 6),
            MemoryPressable(
              shape: const CircleBorder(),
              semanticLabel: t.assistant.memory.screen.send,
              automationId: AutomationIds.settingsMemoryAction,
              automationInstance: 'send',
              automationState: () => {'enabled': ready},
              onPressed: ready ? _send : null,
              child: Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? tk.text : tk.surfaceElevated),
                child: Center(
                  child: AppIcon(
                    Symbols.arrow_upward_rounded,
                    size: 19,
                    weight: 600,
                    color: ready ? tk.bg : tk.textMuted,
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
