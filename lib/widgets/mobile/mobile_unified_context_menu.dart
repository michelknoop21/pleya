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

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
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
    // AutomationNode wraps the sheet and, via `child:` (AppMenuItem's own
    // label-override slot, not a shared-widget change), each row's label —
    // AppMenuList/AppMenuItemTile stay untouched, so icon/trailing/styling
    // are exactly what they'd be without this. Needed because the sheet's
    // title is just the tapped item's own title: without an id naming the
    // sheet itself, a scenario can't tell "the context menu opened" apart
    // from any other overlay that happens to show the same title.
    builder: (sheetContext) => AutomationNode(
      id: AutomationIds.sheetContextMenu,
      role: 'sheet',
      child: AppMenuSheet<UnifiedGroupAction>(
        title: representative.displayTitle,
        entries: [
          for (var i = 0; i < actions.length; i++)
            AppMenuItem<UnifiedGroupAction>(
              value: actions[i],
              icon: iconForUnifiedGroupAction(actions[i]),
              label: labelForUnifiedGroupAction(actions[i]),
              child: AutomationNode(
                id: AutomationIds.sheetContextMenuItem,
                instance: '$i',
                role: 'list.item',
                child: Text(labelForUnifiedGroupAction(actions[i])),
              ),
            ),
        ],
      ),
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
