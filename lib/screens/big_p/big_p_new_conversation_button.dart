import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/big_p/assistant/big_p_suggestions.dart';
import '../../widgets/big_p/big_p_scale.dart';
import 'big_p_mobile_session.dart';

/// "Nieuw gesprek" next to the question field (mockup 40 A): forgets the
/// answer on screen and Big P's memory of the conversation, at once, without
/// a card or an undo. Offered only once there is a conversation.
///
/// iPhone: a 46 pt pill of its own left of the field, short label "Nieuw".
/// iPad (inside the balloon's field, [inline]): the full label as a pill in
/// the field's left end. Either way a 44 pt touch area at least, centred on
/// the field's line.
class BigPNewConversationButton extends StatelessWidget {
  const BigPNewConversationButton({super.key, required this.session, this.inline = false});

  final BigPMobileSession session;
  final bool inline;

  void _start() {
    session.controller.newConversation();
    // Fresh examples for the empty stand, as at a summon.
    BigPSuggestions.of(session.controller).summoned();
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final label = inline ? t.assistant.mobile.newConversation : t.assistant.mobile.newConversationShort;
    final style = Theme.of(
      context,
    ).textTheme.bodyMedium!.copyWith(color: tk.text, fontSize: 15, fontWeight: FontWeight.w600);
    final pill = Container(
      // The iPhone pill is as tall as the field; the iPad pill sits inside it.
      constraints: BoxConstraints(minHeight: inline ? 34 : 46),
      padding: EdgeInsets.symmetric(horizontal: inline ? 12 : 16),
      decoration: BoxDecoration(
        color: inline ? const Color(0x14FFFFFF) : const Color(0xFF1C1C1E),
        borderRadius: BorderRadius.circular(inline ? 17 : 23),
        border: Border.all(color: const Color(0x24FFFFFF)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Symbols.edit_square_rounded, size: 20, color: tk.text),
          const SizedBox(width: 6),
          Text(label, style: style, maxLines: 1, softWrap: false),
        ],
      ),
    );
    return AutomationNode(
      id: AutomationIds.bigpNewConversation,
      role: 'button',
      child: GestureDetector(
        onTap: _start,
        behavior: HitTestBehavior.opaque,
        child: Semantics(
          button: true,
          label: t.assistant.mobile.newConversation,
          excludeSemantics: true,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: kBigPMinTouch, minWidth: kBigPMinTouch),
            child: Center(widthFactor: 1, child: pill),
          ),
        ),
      ),
    );
  }
}
