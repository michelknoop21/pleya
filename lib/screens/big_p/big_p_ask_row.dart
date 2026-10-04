import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../assistant/assistant_controller.dart';
import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../widgets/app_icon.dart';
import '../../widgets/big_p/big_p_portrait.dart';
import '../../widgets/focusable_list_tile.dart';
import 'big_p_mobile_session.dart';

/// The session to summon Big P from, or null where he is not offered: no
/// session (not iPhone or iPad) or hidden. Rebuilds the caller when the
/// availability changes, through the controller provided beside the session.
BigPMobileSession? summonableBigP(BuildContext context) {
  final session = context.watch<BigPMobileSession?>();
  // No session first: watching the controller would create it (lazy) on
  // Android and desktop, where Big P is not offered.
  if (session == null) return null;
  context.watch<AssistantController?>();
  if (session.controller.availability == AssistantAvailability.hidden) return null;
  return session;
}

/// Zoeken's "Vraag het Big P" over the results, the query under it. A tap
/// hands the query over; the host asks it at once.
class BigPAskRow extends StatelessWidget {
  const BigPAskRow({super.key, required this.session, required this.query});

  final BigPMobileSession session;
  final String query;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).textTheme.bodySmall?.color?.withValues(alpha: 0.7);
    return AutomationNode(
      id: AutomationIds.bigpSearchAsk,
      role: 'button',
      child: Padding(
        // As a result section's card: the same card, the same gap under it.
        padding: const EdgeInsets.only(bottom: 16),
        child: Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: FocusableListTile(
            leading: const SizedBox(width: 46, child: BigPPortrait(focused: false, size: 46)),
            title: Text(t.assistant.mobile.searchAsk, maxLines: 1, overflow: TextOverflow.ellipsis),
            subtitle: Text(query, maxLines: 1, overflow: TextOverflow.ellipsis),
            trailing: AppIcon(Symbols.chevron_right_rounded, color: muted),
            onTap: () => session.summon(question: query),
          ),
        ),
      ),
    );
  }
}
