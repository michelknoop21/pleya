/// The mobile long-press menu on a unified card (mockup 09,
/// `docs/assets/ios-unified/northstar/09-contextmenu-sheet.png`). iOS Unified
/// 2026 workitem 4 (I5), `docs/unified-2026-closure.md` §5 row 4.
///
/// This is presentation only. What the menu may offer and what a write does
/// is `tv_unified_context_actions.dart` and `tv_unified_context_menu.dart`'s
/// `runUnifiedGroupAction` — both platform-neutral despite their folder, and
/// reused here unchanged rather than duplicated (hoofdstuk 23's group
/// semantics: markeer bekeken/onbekeken reaches every membership, never just
/// `representativeSource`).
library;

import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/watchlist_store.dart';
import '../../screens/tv/tv_unified_context_actions.dart';
import '../../screens/tv/tv_unified_context_menu.dart';
import '../app_menu.dart';
import '../overlay_sheet.dart';

/// Opens the sheet, then dispatches the chosen [UnifiedGroupAction] through
/// [runUnifiedGroupAction] exactly as the TV menu does. Returns after the
/// write (or the cancel) completes.
Future<void> showMobileUnifiedContextMenu(
  BuildContext context, {
  required UnifiedMediaGroup group,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  bool isInContinueWatching = false,
  bool isOffline = false,
  VoidCallback? onChanged,
}) async {
  final representative = group.representativeSource.item;
  final actions = availableUnifiedGroupActions(
    group: group,
    isInContinueWatching: isInContinueWatching,
    isOffline: isOffline,
    watchlist: unifiedWatchlistState(
      store: context.read<WatchlistStore?>(),
      provider: context.read<WatchlistProvider?>(),
      item: representative,
    ),
  );
  if (actions.isEmpty) return;

  final chosen = await OverlaySheetController.showAdaptive<UnifiedGroupAction>(
    context,
    showDragHandle: true,
    builder: (sheetContext) => AppMenuSheet<UnifiedGroupAction>(
      title: representative.displayTitle,
      automationId: AutomationIds.sheetContextMenu,
      entries: [
        for (final action in actions)
          AppMenuItem<UnifiedGroupAction>(
            value: action,
            icon: _iconForUnifiedGroupAction(action),
            label: labelForUnifiedGroupAction(action),
            automationId: AutomationIds.sheetContextMenuItem,
            automationInstance: action.name,
          ),
      ],
    ),
  );
  if (chosen == null || !context.mounted) return;

  await runUnifiedGroupAction(
    context,
    action: chosen,
    group: group,
    availabilityFor: availabilityFor,
    onChanged: onChanged,
  );
}

IconData _iconForUnifiedGroupAction(UnifiedGroupAction action) => switch (action) {
  UnifiedGroupAction.markWatched => Symbols.check_circle_outline_rounded,
  UnifiedGroupAction.markUnwatched => Symbols.remove_circle_outline_rounded,
  UnifiedGroupAction.addToWatchlist => Symbols.bookmark_add_rounded,
  UnifiedGroupAction.removeFromWatchlist => Symbols.bookmark_remove_rounded,
  UnifiedGroupAction.rate => Symbols.star_rounded,
  UnifiedGroupAction.removeFromContinueWatching => Symbols.close_rounded,
};
