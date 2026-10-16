/// The ways into "Home aanpassen" from Home on iPhone, iPad and Mac (mockup 44
/// A, B and N): the line under the last row, and the quick menu of a row
/// header (long press, right click, or the button that appears on hover).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../automation/automation_node.dart';
import '../../../i18n/strings.g.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/platform_detector.dart';
import '../../../widgets/app_menu.dart';
import '../../../widgets/overlay_sheet.dart';
import 'home_customize_screen.dart';
import 'home_row_actions.dart';

/// Opens the screen: a full-height page on a phone, a dialog on iPad and Mac.
///
/// Both are pushed on the navigator the caller already sits under, so the
/// profile's providers reach them the way they reach every other pushed screen.
Future<void> openHomeCustomize(BuildContext context) {
  if (PlatformDetector.isPhone(context)) {
    return Navigator.of(
      context,
    ).push<void>(MaterialPageRoute(fullscreenDialog: true, builder: (_) => const HomeCustomizeScreen()));
  }
  final size = MediaQuery.sizeOf(context);
  return showDialog<void>(
    context: context,
    useRootNavigator: false,
    builder: (_) => Dialog(
      insetPadding: const EdgeInsets.all(24),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
      child: ConstrainedBox(
        constraints: BoxConstraints(maxWidth: 1180, maxHeight: size.height - 48),
        child: const HomeCustomizeScreen(presentation: HomeCustomizePresentation.dialog),
      ),
    ),
  );
}

/// "Home aanpassen" under the last row of Home.
class HomeCustomizeEntryTile extends StatelessWidget {
  const HomeCustomizeEntryTile({super.key});

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final home = t.unifiedCatalog.homeRows;
    return AutomationNode(
      id: AutomationIds.homeCustomizeEntry,
      role: 'button',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 20, 16, 8),
        child: Material(
          color: mono.surface,
          borderRadius: BorderRadius.circular(16),
          child: InkWell(
            borderRadius: BorderRadius.circular(16),
            onTap: () => openHomeCustomize(context),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
              child: Row(
                children: [
                  CircleAvatar(
                    backgroundColor: mono.surfaceElevated,
                    foregroundColor: mono.text,
                    child: const Icon(Symbols.tune_rounded),
                  ),
                  const SizedBox(width: 14),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          home.customize,
                          style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                        ),
                        Text(
                          home.customizeSubtitle,
                          style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: mono.textMuted),
                        ),
                      ],
                    ),
                  ),
                  Icon(Symbols.chevron_right_rounded, color: mono.textMuted),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

enum HomeRowQuickAction { up, down, hide, customize }

/// The quick menu of a row header (mockup 44 B and N): Omhoog, Omlaag,
/// Verbergen op Home and Home aanpassen. [ids] is the row's identity in the
/// layout; the menu looks the row up in the list Home draws, so it moves and
/// hides exactly what the full screen would.
///
/// [anchor] is where the pointer was, on Mac and iPad with a mouse: the menu is
/// then a popup at that spot, otherwise a sheet.
Future<void> showHomeRowQuickMenu(BuildContext context, {required List<String> ids, Offset? anchor}) async {
  final actions = HomeRowActions.of(context);
  final entries = actions.entries();
  final index = actions.indexOfIds(entries, ids);
  if (index < 0) return;
  final entry = entries[index];
  final home = t.unifiedCatalog.homeRows;
  final canUp = actions.neighbourIndex(entries, index, -1) >= 0;
  final canDown = actions.neighbourIndex(entries, index, 1) >= 0;

  // The label sits in an automation node, the way the card menu does it, so a
  // Verify scenario can pick an action by name.
  AppMenuItem<HomeRowQuickAction> item(
    HomeRowQuickAction action,
    IconData icon,
    String label, {
    bool enabled = true,
    Widget? trailing,
  }) => AppMenuItem(
    value: action,
    icon: icon,
    label: label,
    enabled: enabled,
    trailing: trailing,
    child: AutomationNode(
      id: AutomationIds.homeRowQuickMenuItem,
      instance: action.name,
      role: 'list.item',
      child: Text(label),
    ),
  );

  final HomeRowQuickAction? chosen;
  if (anchor != null) {
    final overlay = Overlay.of(context).context.findRenderObject()! as RenderBox;
    chosen = await showMenu<HomeRowQuickAction>(
      context: context,
      useRootNavigator: false,
      position: RelativeRect.fromRect(anchor & const Size(1, 1), Offset.zero & overlay.size),
      items: [
        PopupMenuItem(enabled: canUp, value: HomeRowQuickAction.up, child: Text(home.moveUp)),
        PopupMenuItem(enabled: canDown, value: HomeRowQuickAction.down, child: Text(home.moveDown)),
        PopupMenuItem(value: HomeRowQuickAction.hide, child: Text(home.hideOnHome)),
        const PopupMenuDivider(),
        PopupMenuItem(value: HomeRowQuickAction.customize, child: Text(home.customize)),
      ],
    );
  } else {
    chosen = await OverlaySheetController.showAdaptive<HomeRowQuickAction>(
      context,
      showDragHandle: true,
      builder: (sheetContext) => AutomationNode(
        id: AutomationIds.homeRowQuickMenu,
        role: 'sheet',
        state: () => {'title': entry.title, 'position': index + 1, 'total': entries.length},
        child: AppMenuSheet<HomeRowQuickAction>(
          title: '${entry.title} · ${home.rowPosition(position: index + 1, total: entries.length)}',
          entries: [
            item(HomeRowQuickAction.up, Symbols.arrow_upward_rounded, home.moveUp, enabled: canUp),
            item(HomeRowQuickAction.down, Symbols.arrow_downward_rounded, home.moveDown, enabled: canDown),
            item(HomeRowQuickAction.hide, Symbols.visibility_off_rounded, home.hideOnHome),
            const AppMenuDivider(),
            item(
              HomeRowQuickAction.customize,
              Symbols.tune_rounded,
              home.customize,
              trailing: const Icon(Symbols.chevron_right_rounded),
            ),
          ],
        ),
      ),
    );
  }
  if (chosen == null || !context.mounted) return;
  switch (chosen) {
    case HomeRowQuickAction.up:
      await actions.moveStep(entries, index, -1);
    case HomeRowQuickAction.down:
      await actions.moveStep(entries, index, 1);
    case HomeRowQuickAction.hide:
      await actions.setHidden(entry, true);
    case HomeRowQuickAction.customize:
      await openHomeCustomize(context);
  }
}
