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
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/unified/source_availability.dart';
import '../../media/unified/unified_media_group.dart';
import '../../media/unified/unified_media_source.dart';
import '../../providers/watchlist_provider.dart';
import '../../providers/watchlist_store.dart';
import '../../screens/tv/tv_unified_context_actions.dart';
import '../../screens/tv/tv_unified_context_menu.dart';
import '../../theme/mono_tokens.dart';
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
  final removal = actions.contains(UnifiedGroupAction.removeFromContinueWatching)
      ? continueWatchingRemovalPresentationFor(context, group, availabilityFor)
      : null;
  String labelFor(UnifiedGroupAction action) =>
      action == UnifiedGroupAction.removeFromContinueWatching && removal != null
      ? removal.label
      : labelForUnifiedGroupAction(action);

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
              icon: actions[i] == UnifiedGroupAction.removeFromContinueWatching && (removal?.hidesOnly ?? false)
                  ? Symbols.visibility_off_rounded
                  : iconForUnifiedGroupAction(actions[i]),
              label: labelFor(actions[i]),
              // Mockup 38 E: the reach of the removal sits on the row itself.
              subtitle: actions[i] == UnifiedGroupAction.removeFromContinueWatching ? removal?.scope : null,
              child: AutomationNode(
                id: AutomationIds.sheetContextMenuItem,
                instance: '$i',
                role: 'list.item',
                child: Text(labelFor(actions[i])),
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

/// The compact long-press menu of the catalogue grid (Dense Library, variant
/// 3): a small popup anchored at the pressed card instead of a sheet. Play
/// first, then the same [availableUnifiedGroupActions] the sheet offers,
/// dispatched through the same [runUnifiedGroupAction].
Future<void> showMobileUnifiedQuickMenu(
  BuildContext context, {
  required Rect anchor,
  required UnifiedMediaGroup group,
  required SourceAvailability Function(UnifiedMediaSource source) availabilityFor,
  required VoidCallback onPlay,
  bool isOffline = false,
  VoidCallback? onChanged,
}) async {
  final actions = availableUnifiedGroupActions(
    group: group,
    isInContinueWatching: false,
    isOffline: isOffline,
    watchlist: unifiedWatchlistState(
      store: context.read<WatchlistStore?>(),
      provider: context.read<WatchlistProvider?>(),
      item: group.representativeSource.item,
    ),
  );
  final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
  PopupMenuItem<UnifiedGroupAction?> item(int index, UnifiedGroupAction? value, IconData icon, String label) =>
      PopupMenuItem<UnifiedGroupAction?>(
        value: value,
        height: 44,
        child: AutomationNode(
          id: AutomationIds.sheetContextMenuItem,
          instance: '$index',
          role: 'list.item',
          child: Row(
            children: [
              Icon(icon, size: 20),
              const SizedBox(width: 12),
              Expanded(child: Text(label)),
            ],
          ),
        ),
      );

  // `null` is Play; a dismissed menu also returns null, so Play is told
  // apart by a flag set in its own onTap.
  var play = false;
  final chosen = await showMenu<UnifiedGroupAction?>(
    context: context,
    useRootNavigator: false,
    position: RelativeRect.fromRect(anchor, Offset.zero & overlay.size),
    shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(tokens(context).radiusMd)),
    items: [
      PopupMenuItem<UnifiedGroupAction?>(
        height: 44,
        onTap: () => play = true,
        // A popup has no single box around its items to hang the menu id on,
        // so the first row carries it alongside its own item id.
        child: AutomationNode(
          id: AutomationIds.sheetContextMenu,
          role: 'sheet',
          child: AutomationNode(
            id: AutomationIds.sheetContextMenuItem,
            instance: '0',
            role: 'list.item',
            child: Row(
              children: [
                const Icon(Symbols.play_arrow_rounded, size: 20),
                const SizedBox(width: 12),
                Expanded(child: Text(t.common.play)),
              ],
            ),
          ),
        ),
      ),
      for (var i = 0; i < actions.length; i++)
        item(i + 1, actions[i], iconForUnifiedGroupAction(actions[i]), labelForUnifiedGroupAction(actions[i])),
    ],
  );
  if (!context.mounted) return;
  if (play) return onPlay();
  if (chosen == null) return;

  await runUnifiedGroupAction(
    context,
    action: chosen,
    group: group,
    availabilityFor: availabilityFor,
    onChanged: onChanged,
  );
}
