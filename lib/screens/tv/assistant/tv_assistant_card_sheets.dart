import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_memory.dart';
import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../focus/key_event_utils.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/assistant/big_p_answer.dart';
import '../../../widgets/big_p/assistant/big_p_assistant_widgets.dart';
import '../../../widgets/big_p/assistant/big_p_labels.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart';
import 'tv_assistant_kids_sheet.dart';

/// The memory card on TV ("Zal ik dit onthouden?"). It stands in the balloon
/// under the answer it belongs to ([TvAssistantMemoryStand]), never over it;
/// this keeps the remote on it: a new card opens with the focus on the safe
/// button, also when the previous card was answered with yes.
class TvMemoryCardFocus {
  final declineNode = FocusNode(debugLabel: 'assistant.memory.decline');
  AssistantMemoryProposal? _shown;

  /// The card holds the remote: the owner leaves the focus alone.
  bool get open => _shown != null;

  /// Call on every controller change, before the rebuild. True when the last
  /// card went (answered, or dropped by a reset or the children's switch):
  /// the owner then puts the focus back on its default.
  bool sync(AssistantController c) {
    final proposal = c.memoryProposal;
    if (identical(proposal, _shown)) return false;
    _shown = proposal;
    if (proposal == null) return true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (identical(_shown, proposal) && declineNode.context != null) declineNode.requestFocus();
    });
    return false;
  }

  void dispose() => declineNode.dispose();
}

/// Pleya's own cards under an answer on TV: the children's ages (a sheet)
/// and the memory proposal (in the balloon). One owner, so a surface syncs
/// and guards them together.
class TvAssistantCardSheets {
  final _ages = TvKidsAgesSheet();
  final memory = TvMemoryCardFocus();

  /// A card holds the remote: the owner leaves the focus alone.
  bool get open => _ages.open || memory.open;

  /// True when the memory card went and the default focus is due again.
  bool sync(BuildContext context, AssistantController c) {
    _ages.sync(context, c);
    return memory.sync(c);
  }

  void dispose() {
    _ages.dispose();
    memory.dispose();
  }
}

/// The memory card on TV under the answer it belongs to (43 K), never over
/// it: the question and the first lines of the answer stay readable above
/// the card. The title cards, the follow-ups and the buttons wait until the
/// card is answered, so the remote has the two choices and nothing else.
/// Menu is a no.
class TvAssistantMemoryStand extends StatelessWidget {
  const TvAssistantMemoryStand({
    super.key,
    required this.controller,
    required this.proposal,
    required this.headlineStyle,
    this.declineNode,
    this.compact = false,
  });

  final AssistantController controller;
  final AssistantMemoryProposal proposal;
  final TextStyle headlineStyle;

  /// Gets the safe button, for the surface's focus.
  final FocusNode? declineNode;

  /// The summoned panel rather than the surface.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final c = controller;
    void answer(bool accept) => unawaited(c.answerMemoryProposal(proposal, accept: accept));
    final headline = assistantHeadline(c);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        if (c.prompt case final prompt?) ...[
          BigPQuestion(prompt: prompt, maxLines: compact ? 1 : 3),
          SizedBox(height: 16 * pt),
        ],
        if (headline.isNotEmpty) ...[
          Focus(
            canRequestFocus: false,
            skipTraversal: true,
            // The answer is a reading stop (Up). Down from its last line goes
            // to the safe button, not to whichever button lies nearest.
            onKeyEvent: (_, event) {
              final node = declineNode;
              if (event is KeyUpEvent || event.logicalKey != LogicalKeyboardKey.arrowDown || node == null) {
                return KeyEventResult.ignored;
              }
              node.requestFocus();
              return KeyEventResult.handled;
            },
            child: AutomationNode(
              id: AutomationIds.assistantMemoryAnswer,
              role: 'region',
              child: BigPAnswer(text: headline, style: headlineStyle, bodyLines: 3),
            ),
          ),
          SizedBox(height: 16 * pt),
        ],
        // The card shrinks before the answer does: its rows scroll, its
        // buttons stay in view.
        Flexible(
          child: Focus(
            canRequestFocus: false,
            skipTraversal: true,
            onKeyEvent: (_, event) => handleBackKeyAction(event, () => answer(false)),
            child: BigPMemoryCard(
              key: ObjectKey(proposal),
              proposal: proposal,
              embedded: true,
              remote: true,
              declineNode: declineNode,
              onAccept: () => answer(true),
              onDecline: () => answer(false),
            ),
          ),
        ),
      ],
    );
  }
}
