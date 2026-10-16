/// The menu of one of the viewer's own rows (mockup 44 E and F), the delete
/// confirmation, and the way into the full catalog with the row's filter.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/media_kind.dart';
import '../../../services/unified_catalog/home_custom_row.dart';
import '../../../services/unified_catalog/home_layout_entries.dart';
import '../../../widgets/app_menu.dart';
import '../../../widgets/overlay_sheet.dart';
import '../mobile_catalog_screen.dart';
import 'home_customize_row_tile.dart';

/// Bewerken, Verbergen op Home, Alle in Films, Verwijderen. The count is left
/// out: the row only knows how many cards it loaded (capped at 20), not the
/// catalog's total. Offered where there is a catalog to open and
/// the row has loaded ([viewAllCount] non-null).
Future<HomeRowMenuAction?> showHomeCustomRowMenu(
  BuildContext context, {
  required HomeLayoutEntry entry,
  required bool hidden,
  required int? viewAllCount,
  required MediaKind? kind,
}) {
  final home = t.unifiedCatalog.homeRows;
  final catalog = kind == MediaKind.show ? t.unifiedCatalog.seriesTitle : t.unifiedCatalog.moviesTitle;
  return OverlaySheetController.showAdaptive<HomeRowMenuAction>(
    context,
    showDragHandle: true,
    builder: (sheetContext) => AppMenuSheet<HomeRowMenuAction>(
      title: entry.title,
      entries: [
        AppMenuItem(value: HomeRowMenuAction.edit, icon: Symbols.edit_rounded, label: home.edit),
        AppMenuItem(
          value: HomeRowMenuAction.toggleHidden,
          icon: hidden ? Symbols.visibility_rounded : Symbols.visibility_off_rounded,
          label: hidden ? home.showOnHome : home.hideOnHome,
        ),
        if (viewAllCount != null && viewAllCount > 0)
          AppMenuItem(
            value: HomeRowMenuAction.viewAll,
            icon: Symbols.movie_rounded,
            label: home.allInCatalogMenu(catalog: catalog),
            trailing: const Icon(Symbols.chevron_right_rounded),
          ),
        const AppMenuDivider(),
        AppMenuItem(
          value: HomeRowMenuAction.remove,
          icon: Symbols.delete_rounded,
          label: home.remove,
          destructive: true,
        ),
      ],
    ),
  );
}

/// Deleting an own row cannot be undone, and says that the titles themselves
/// stay (mockup 44 F).
Future<bool> confirmRemoveHomeRow(BuildContext context, String name) async {
  final home = t.unifiedCatalog.homeRows;
  final confirmed = await showDialog<bool>(
    context: context,
    useRootNavigator: false,
    builder: (dialogContext) => AlertDialog(
      title: Text(home.removeTitle),
      content: Text(home.removeBody(name: name)),
      actions: [
        TextButton(onPressed: () => Navigator.of(dialogContext).pop(false), child: Text(t.common.cancel)),
        TextButton(
          onPressed: () => Navigator.of(dialogContext).pop(true),
          style: TextButton.styleFrom(foregroundColor: Theme.of(dialogContext).colorScheme.error),
          child: Text(home.remove),
        ),
      ],
    ),
  );
  return confirmed ?? false;
}

/// The complete catalog of the row's kind, opened on the row's own filter and
/// sort for this visit only (ROW1c, the same mechanism the tvOS "Alle N" tile
/// uses).
Future<void> openHomeCustomRowCatalog(BuildContext context, HomeCustomRow row) {
  return Navigator.of(context).push<void>(
    MaterialPageRoute(
      builder: (_) => MobileCatalogScreen(
        kind: row.kind == MediaKind.show ? MobileCatalogKind.series : MobileCatalogKind.movies,
        initialFilterOverride: row.preferences,
      ),
    ),
  );
}
