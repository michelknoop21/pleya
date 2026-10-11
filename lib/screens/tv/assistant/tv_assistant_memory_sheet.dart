import 'dart:async';

import 'package:flutter/material.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_memory.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/assistant/big_p_memory_card.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';
import 'tv_assistant_kids_sheet.dart';

/// The memory card on TV ("Zal ik dit onthouden?"), for the surface and the
/// summoned Big P alike. It rises in the shell's overlay host once per
/// proposal, with the focus on the safe button. Menu closes it, which is a
/// no: nothing is stored, replaced or forgotten.
class TvMemoryProposalSheet {
  final declineNode = FocusNode(debugLabel: 'assistant.memory.decline');
  AssistantMemoryProposal? _shown;
  BuildContext? _sheet;

  /// The card holds the remote: the owner leaves the focus alone.
  bool get open => _sheet != null;

  /// Raises the card for a new proposal; takes it away once the controller
  /// dropped it (a reset, a new ask). Call on every controller change.
  void sync(BuildContext context, AssistantController c) {
    final proposal = c.memoryProposal;
    if (proposal != null && !identical(proposal, _shown)) {
      // One card at a time: the next rises when this one closed.
      if (_sheet != null) return;
      _shown = proposal;
      unawaited(_show(context, c, proposal));
    } else if (proposal == null) {
      final sheet = _sheet;
      if (sheet != null && sheet.mounted) OverlaySheetController.closeAdaptive(sheet);
    }
  }

  Future<void> _show(BuildContext context, AssistantController c, AssistantMemoryProposal proposal) async {
    final accepted = await OverlaySheetController.showAdaptive<bool>(
      context,
      presentation: OverlaySheetPresentation.panel,
      restoreLauncherFocus: true,
      initialFocusNode: declineNode,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxWidth: 880 * TvHig.of(context)),
      builder: (sheetContext) {
        _sheet = sheetContext;
        return BigPMemoryCard(
          proposal: proposal,
          declineNode: declineNode,
          onAccept: () => OverlaySheetController.closeAdaptive(sheetContext, true),
          onDecline: () => OverlaySheetController.closeAdaptive(sheetContext, false),
        );
      },
    );
    _sheet = null;
    // A card the controller already dropped answers nothing.
    if (!identical(c.memoryProposal, proposal)) return;
    await c.answerMemoryProposal(proposal, accept: accepted ?? false);
    // A second proposal of the same answer rises now.
    if (context.mounted) sync(context, c);
  }

  void dispose() => declineNode.dispose();
}

/// Pleya's own cards under an answer on TV: the children's ages and the
/// memory proposal. One owner, so a surface syncs and guards them together.
class TvAssistantCardSheets {
  final _ages = TvKidsAgesSheet();
  final _memory = TvMemoryProposalSheet();

  /// A card holds the remote: the owner leaves the focus alone.
  bool get open => _ages.open || _memory.open;

  void sync(BuildContext context, AssistantController c) {
    _ages.sync(context, c);
    _memory.sync(context, c);
  }

  void dispose() {
    _ages.dispose();
    _memory.dispose();
  }
}
