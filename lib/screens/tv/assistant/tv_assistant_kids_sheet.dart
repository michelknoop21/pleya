import 'dart:async';

import 'package:flutter/material.dart';

import '../../../assistant/assistant_controller.dart';
import '../../../assistant/assistant_tools.dart';
import '../../../profiles/household_kids_store.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/big_p/assistant/big_p_household_kids_card.dart';
import '../../../widgets/big_p/assistant/big_p_kids_ages_card.dart';
import '../../../widgets/overlay_sheet.dart';
import '../../../widgets/overlay_sheet_geometry.dart';

/// The ages card on TV, for the surface and the summoned Big P alike. It
/// rises in the shell's overlay host as the confirmation card does, once
/// per ask, with the focus on the first age. Menu closes it: the answer
/// stays and the card goes ([AssistantController.dismissKidsAges]).
class TvKidsAgesSheet {
  final firstNode = FocusNode(debugLabel: 'assistant.kids.first');
  AssistantKidsAgesPrompt? _shown;
  BuildContext? _sheet;

  /// The card holds the remote: the owner leaves the focus alone.
  bool get open => _sheet != null;

  /// Raises the card for a new prompt; takes it away once the controller
  /// dropped it (a reset, a new ask). Call on every controller change.
  void sync(BuildContext context, AssistantController c) {
    final prompt = c.kidsAgesPrompt;
    if (prompt != null && !identical(prompt, _shown)) {
      _shown = prompt;
      unawaited(_show(context, c, prompt));
    } else if (prompt == null) {
      final sheet = _sheet;
      if (sheet != null && sheet.mounted) OverlaySheetController.closeAdaptive(sheet);
    }
  }

  Future<void> _show(BuildContext context, AssistantController c, AssistantKidsAgesPrompt prompt) async {
    // The ages to save, null for Menu. There is no way around the filter:
    // this card only shows on a children's profile.
    final result = await OverlaySheetController.showAdaptive<List<int>>(
      context,
      presentation: OverlaySheetPresentation.panel,
      restoreLauncherFocus: true,
      initialFocusNode: firstNode,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxWidth: 880 * TvHig.of(context)),
      builder: (sheetContext) {
        _sheet = sheetContext;
        return BigPKidsAgesCard(
          firstNode: firstNode,
          onSave: (ages) => OverlaySheetController.closeAdaptive(sheetContext, ages),
        );
      },
    );
    _sheet = null;
    if (!identical(c.kidsAgesPrompt, prompt)) return;
    if (result != null) {
      unawaited(c.saveKidsAgesAndRetry(result));
    } else {
      c.dismissKidsAges();
    }
  }

  void dispose() => firstNode.dispose();
}

/// The household card on TV (45 K, L), raised like [TvKidsAgesSheet]: the
/// focus opens on Naam, which opens the system keyboard; Menu closes it and
/// the answer stays ([AssistantController.dismissHouseholdKids]).
class TvHouseholdKidsSheet {
  final firstNode = FocusNode(debugLabel: 'assistant.household.first');
  AssistantHouseholdKidsPrompt? _shown;
  BuildContext? _sheet;

  bool get open => _sheet != null;

  void sync(BuildContext context, AssistantController c) {
    final prompt = c.householdKidsPrompt;
    if (prompt != null && !identical(prompt, _shown)) {
      _shown = prompt;
      unawaited(_show(context, c, prompt));
    } else if (prompt == null) {
      final sheet = _sheet;
      if (sheet != null && sheet.mounted) OverlaySheetController.closeAdaptive(sheet);
    }
  }

  Future<void> _show(BuildContext context, AssistantController c, AssistantHouseholdKidsPrompt prompt) async {
    final result = await OverlaySheetController.showAdaptive<List<HouseholdKid>>(
      context,
      presentation: OverlaySheetPresentation.panel,
      restoreLauncherFocus: true,
      initialFocusNode: firstNode,
      backgroundColor: Colors.transparent,
      constraints: BoxConstraints(maxWidth: 1000 * TvHig.of(context)),
      builder: (sheetContext) {
        _sheet = sheetContext;
        return BigPHouseholdKidsCard(
          firstNode: firstNode,
          onSave: (kids) => OverlaySheetController.closeAdaptive(sheetContext, kids),
          onClose: () => OverlaySheetController.closeAdaptive(sheetContext),
        );
      },
    );
    _sheet = null;
    if (!identical(c.householdKidsPrompt, prompt)) return;
    if (result != null) {
      unawaited(c.saveHouseholdKidsAndRetry(result));
    } else {
      c.dismissHouseholdKids();
    }
  }

  void dispose() => firstNode.dispose();
}
