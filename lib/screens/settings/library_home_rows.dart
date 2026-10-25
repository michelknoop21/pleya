/// The Home aanpassen rows of Bibliotheek & Home (A-24b, series
/// `ios/03-bibliotheek-home-02`): each row starts an action Home aanpassen
/// already has, from the same code (`HomeRowActions`, the row wizard, the
/// confirmed remove, the hidden Verder kijken sheet).
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/ids.dart';
import '../../providers/continue_watching_hidden_provider.dart';
import '../../providers/home_custom_rows_provider.dart';
import '../../providers/multi_server_provider.dart';
import '../../services/unified_catalog/home_row_editing.dart';
import '../../widgets/continue_watching_hidden_items.dart';
import '../../utils/platform_detector.dart';
import '../../widgets/setting_tile.dart';
import '../../widgets/tv/tv_home_customize_controller.dart';
import '../home/customize/home_customize_row_menu.dart';
import '../home/customize/home_row_actions.dart';
import '../home/customize/home_row_wizard_page.dart';
import 'home_layout_screen.dart';
import 'settings_utils.dart';

/// Drag into order, show or hide, add an own row, remove one (only when there
/// is one) and the hidden Verder kijken titles (only when there are some).
List<Widget> buildHomeLayoutRows(BuildContext context) {
  final s = t.settingsStudio;
  final hasOwnRows = context.watch<HomeCustomRowsProvider?>()?.hasSavedRows ?? false;
  final hiddenCount = context.watch<ContinueWatchingHiddenProvider?>()?.count ?? 0;
  return [
    _row(
      'home_layout',
      SettingNavigationTile(
        icon: Symbols.drag_indicator_rounded,
        title: s.reorderRows,
        automationInstance: 'settings.home_layout',
        destinationBuilder: (_) => const HomeLayoutScreen(),
      ),
    ),
    _row(
      'home_visibility',
      SettingNavigationTile(
        icon: Symbols.visibility_rounded,
        title: s.rowVisibility,
        automationInstance: 'settings.home_visibility',
        destinationBuilder: (_) => const HomeLayoutScreen(),
      ),
    ),
    _row(
      'home_add_row',
      SettingNavigationTile(
        icon: Symbols.add_rounded,
        title: s.addOwnRow,
        automationInstance: 'settings.home_add_row',
        onTap: () => unawaited(_addRow(context)),
      ),
    ),
    if (hasOwnRows)
      _row(
        'home_remove_row',
        SettingNavigationTile(
          icon: Symbols.delete_outline_rounded,
          title: s.removeOwnRow,
          destructive: true,
          onTap: () => unawaited(_removeRow(context)),
        ),
      ),
    if (hiddenCount > 0)
      _row(
        'home_hidden_items',
        SettingNavigationTile(
          icon: Symbols.visibility_off_rounded,
          title: s.hiddenContinueWatching,
          trailingLabel: '$hiddenCount',
          onTap: () => unawaited(showContinueWatchingHiddenItems(context)),
        ),
      ),
  ];
}

Widget _row(String instance, Widget child) =>
    AutomationNode(id: AutomationIds.settingsTile, instance: instance, role: 'list.item', child: child);

/// The row wizard as Home aanpassen opens it, then the save: on a TV the
/// D-pad wizard Home's own panel runs, elsewhere the phone page.
Future<void> _addRow(BuildContext context) async {
  final servers = context.read<MultiServerProvider?>();
  if (PlatformDetector.isTV()) {
    final tv = TvHomeCustomizeController.maybeOf(context, clientFor: (id) => servers?.getClientForServer(ServerId(id)));
    if (tv != null) {
      await tv.runWizard(context);
      return;
    }
  }
  if (!context.mounted) return;
  final actions = HomeRowActions.of(context);
  final row = await showHomeRowWizardPage(
    context,
    editing: HomeRowEditing.of(context, clientFor: (id) => servers?.getClientForServer(ServerId(id))),
  );
  if (row != null) await actions.save(row);
}

/// Which own row, then the confirmation Home aanpassen asks, then the remove.
Future<void> _removeRow(BuildContext context) async {
  final actions = HomeRowActions.of(context);
  final own = [
    for (final entry in actions.entries())
      if (entry.isOwn) entry,
  ];
  if (own.isEmpty) return;
  final picked = await showSelectionDialog<int>(
    context: context,
    title: t.settingsStudio.chooseRowToRemove,
    options: [for (final (i, entry) in own.indexed) DialogOption(value: i, title: entry.title)],
    currentValue: -1,
  );
  if (picked == null || !context.mounted) return;
  final entry = own[picked];
  if (await confirmRemoveHomeRow(context, entry.title)) await actions.remove(entry);
}
