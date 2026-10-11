import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/tv_hig.dart';
import '../big_p_scale.dart';
import 'big_p_assistant_widgets.dart';

String assistantMemoryCategoryLabel(MemoryCategory category) {
  final c = t.assistant.memory.categories;
  return switch (category) {
    MemoryCategory.preference => c.preference,
    MemoryCategory.dislike => c.dislike,
    MemoryCategory.household => c.household,
    MemoryCategory.habit => c.habit,
    MemoryCategory.other => c.other,
  };
}

/// The Pleya card under Big P's answer that asks whether to remember,
/// replace or forget a fact (43 K, 43 H). The text on it is the sentence
/// that would be stored and the fact that would go; nothing happened yet,
/// and nothing happens without [onAccept].
///
/// Focus opens on the safe button: the Select that closed the keyboard is
/// still in the viewer's thumb, and a second press must not store or remove
/// anything.
class BigPMemoryCard extends StatelessWidget {
  /// The longest sentence that still stands beside its label (43 K).
  static const int _besideMaxChars = 60;

  const BigPMemoryCard({
    super.key,
    required this.proposal,
    required this.onAccept,
    required this.onDecline,
    this.declineNode,
    this.embedded = false,
    this.remote = false,
    this.themed = false,
  });

  final AssistantMemoryProposal proposal;
  final VoidCallback onAccept;
  final VoidCallback onDecline;

  /// Gets the safe button, for the surface's initial focus.
  final FocusNode? declineNode;

  /// Inside Big P's balloon: an outlined card under the answer.
  final bool embedded;

  /// Driven by a remote (TV): the focus itself is the white button, so
  /// neither button is drawn white of its own and only one ever is.
  final bool remote;

  /// On a surface of the theme (the memory screen) instead of in the dark
  /// balloon: the box and the resting button take their tint from the ink
  /// of the theme, so they keep a shape in the light theme. In the dark
  /// theme that is the same white tint the balloon uses.
  final bool themed;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    final c = t.assistant.memory.card;
    final (title, accept, decline) = switch (proposal.kind) {
      AssistantMemoryProposalKind.remember => (c.rememberTitle, c.remember, c.notRemember),
      AssistantMemoryProposalKind.replace => (c.replaceTitle, c.replace, c.notReplace),
      AssistantMemoryProposalKind.forget => (c.forgetTitle, c.forget, c.notForget),
    };
    final label = TextStyle(color: tk.text.withValues(alpha: 0.6), fontSize: TvHig.caption1 * pt);
    final strong = TextStyle(color: tk.text, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w700, height: 1.3);
    final plain = TextStyle(color: tk.text.withValues(alpha: 0.75), fontSize: TvHig.caption1 * pt, height: 1.3);

    // Label left, value right, as the rows of 43 K.
    Widget beside(String name, String value) => Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(name, style: label),
        SizedBox(width: 20 * pt),
        Expanded(
          child: Text(value, textAlign: TextAlign.end, style: strong),
        ),
      ],
    );
    // Label over the sentence, as the rows of 43 H.
    Widget stacked(String name, String value, TextStyle style) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(name, style: label),
        SizedBox(height: 6 * pt),
        Text(value, style: style),
      ],
    );

    final value = proposal.value ?? '';
    final target = proposal.target;
    final rows = switch (proposal.kind) {
      AssistantMemoryProposalKind.remember => [
        // A long sentence reads as running text under its label, not as a
        // right-aligned column beside it.
        value.runes.length > _besideMaxChars ? stacked(c.memory, value, strong) : beside(c.memory, value),
        if (proposal.category case final category?) beside(c.category, assistantMemoryCategoryLabel(category)),
      ],
      AssistantMemoryProposalKind.replace => [
        stacked(c.disappears, target?.value ?? '', plain),
        stacked(c.fresh, value, strong),
      ],
      AssistantMemoryProposalKind.forget => [
        stacked(c.disappears, target?.value ?? '', strong),
        if (target != null) beside(c.category, assistantMemoryCategoryLabel(target.category)),
      ],
    };

    // Equally high: in a narrow balloon (iPhone SE) the longer label takes two
    // lines, and the other button grows with it.
    final buttons = IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: BigPButton(
              label: accept,
              restFill: themed ? tk.text.withValues(alpha: 0.15) : null,
              automationId: AutomationIds.assistantMemoryButton,
              automationInstance: 'accept',
              onPressed: onAccept,
            ),
          ),
          SizedBox(width: 12 * pt),
          Expanded(
            child: BigPButton(
              label: decline,
              // White in the balloon, as 43 K draws the safe choice.
              primary: embedded && !remote,
              focusNode: declineNode,
              automationId: AutomationIds.assistantMemoryButton,
              automationInstance: 'decline',
              onPressed: onDecline,
            ),
          ),
        ],
      ),
    );

    final body = Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          title,
          style: TextStyle(color: tk.text, fontSize: TvHig.title3 * pt * 0.8, fontWeight: FontWeight.w700),
        ),
        SizedBox(height: 18 * pt),
        DecoratedBox(
          decoration: BoxDecoration(
            color: themed ? tk.text.withValues(alpha: 0.08) : const Color(0x14FFFFFF),
            borderRadius: BorderRadius.circular(18 * pt),
          ),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: 22 * pt),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (final (i, row) in rows.indexed) ...[
                  if (i > 0) Divider(height: 1, thickness: 1, color: tk.outline),
                  Padding(
                    padding: EdgeInsets.symmetric(vertical: 16 * pt),
                    child: row,
                  ),
                ],
              ],
            ),
          ),
        ),
      ],
    );

    return AutomationNode(
      id: AutomationIds.assistantMemory,
      role: 'sheet',
      state: () => {'kind': proposal.kind.name},
      child: Container(
        padding: EdgeInsets.all((embedded ? 22 : 48) * pt),
        decoration: BoxDecoration(
          color: embedded ? null : tk.surface,
          border: embedded ? Border.all(color: tk.outline) : null,
          borderRadius: BorderRadius.circular((embedded ? 26 : 28) * pt),
        ),
        // In the balloon the rows scroll and the buttons stay put, so a long
        // sentence at a large text size never pushes the choice out of view.
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Flexible(child: SingleChildScrollView(child: body)),
            SizedBox(height: 22 * pt),
            buttons,
          ],
        ),
      ),
    );
  }
}

/// "Bekijk geheugen" under an answer that stored something (43 K).
class BigPMemoryLink extends StatelessWidget {
  const BigPMemoryLink({super.key, required this.onOpen});

  final VoidCallback onOpen;

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    final tk = tokens(context);
    return GestureDetector(
      // FocusableWrapper only answers keys; on a touch screen a tap is Select.
      onTap: onOpen,
      behavior: HitTestBehavior.opaque,
      child: BigPTouchTarget(
        child: FocusableWrapper(
          borderRadius: 12 * pt,
          disableScale: true,
          semanticLabel: t.assistant.memory.view,
          automationId: AutomationIds.assistantMemoryLink,
          automationRole: 'button',
          onSelect: () {
            SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
            onOpen();
          },
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                t.assistant.memory.view,
                style: TextStyle(
                  color: tk.text,
                  fontSize: TvHig.caption1 * pt,
                  fontWeight: FontWeight.w600,
                  decoration: TextDecoration.underline,
                  decorationColor: tk.text.withValues(alpha: 0.6),
                ),
              ),
              SizedBox(width: 8 * pt),
              Icon(Symbols.chevron_right_rounded, size: TvHig.caption1 * pt, color: tk.text.withValues(alpha: 0.75)),
            ],
          ),
        ),
      ),
    );
  }
}
