/// Ask which order Alle films/Alle series should be in (iOS Unified 2026
/// fase 3, `docs/ios-unified-2026-fase3-plan.md`).
///
/// Modelled on `WatchlistSortSheet`'s content (a short list, no
/// draft/Apply split, a sort has no capability question and no cost to
/// reorder immediately, unlike the filter sheet's item predicates) and on
/// `MobileSourcePickerSheet`'s presentation: `OverlaySheetController.show`
/// rather than `showAdaptive`, because this sheet only ever opens from
/// `MobileCatalogScreen`, which is itself phone-only (DEC-104).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../media/library_menu_definition.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../app_icon.dart';
import '../bottom_sheet_header.dart';
import '../focusable_list_tile.dart';
import '../overlay_sheet.dart';

Future<UnifiedCatalogSort?> showMobileCatalogSortSheet(
  BuildContext context, {
  required UnifiedCatalogSort current,
  required UnifiedFilterCapabilities capabilities,
}) {
  return OverlaySheetController.of(context).show<UnifiedCatalogSort>(
    showDragHandle: true,
    builder: (sheetContext) => MobileCatalogSortSheet(
      current: current,
      capabilities: capabilities,
      onChosen: (sort) => OverlaySheetController.of(sheetContext).pop(sort),
    ),
  );
}

class MobileCatalogSortSheet extends StatelessWidget {
  const MobileCatalogSortSheet({super.key, required this.current, required this.capabilities, required this.onChosen});

  final UnifiedCatalogSort current;

  /// Leaves out what a source taking part cannot run: choosing it would land on
  /// Title A-Z anyway.
  final UnifiedFilterCapabilities capabilities;
  final ValueChanged<UnifiedCatalogSort> onChosen;

  @override
  Widget build(BuildContext context) {
    return AutomationNode(
      id: AutomationIds.sheetCatalogSort,
      role: 'sheet',
      child: SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            BottomSheetHeader(title: t.unifiedCatalog.sort.title),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (final option in UnifiedCatalogSort.named.where(
                      (sort) => capabilities.supportsSort(sort.field),
                    ))
                      AutomationNode(
                        id: AutomationIds.sheetCatalogSortOption,
                        instance: option.name,
                        role: 'list.item',
                        child: FocusableListTile(
                          autofocus: option == current,
                          selected: option == current,
                          leading: AppIcon(
                            option == current
                                ? Symbols.radio_button_checked_rounded
                                : Symbols.radio_button_unchecked_rounded,
                            fill: 1,
                          ),
                          title: Text(mobileCatalogSortLabel(option)),
                          onTap: () => onChosen(option),
                        ),
                      ),
                  ],
                ),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}

String mobileCatalogSortLabel(UnifiedCatalogSort sort) => switch (sort) {
  UnifiedCatalogSort.titleAsc => t.unifiedCatalog.sort.titleAsc,
  UnifiedCatalogSort.titleDesc => t.unifiedCatalog.sort.titleDesc,
  UnifiedCatalogSort.recentlyAdded => t.unifiedCatalog.sort.recentlyAdded,
  UnifiedCatalogSort.oldestAdded => t.unifiedCatalog.sort.oldestAdded,
  UnifiedCatalogSort.newestRelease => t.unifiedCatalog.sort.newestRelease,
  UnifiedCatalogSort.oldestRelease => t.unifiedCatalog.sort.oldestRelease,
  UnifiedCatalogSort.yearNewest => t.unifiedCatalog.sort.yearNewest,
  UnifiedCatalogSort.yearOldest => t.unifiedCatalog.sort.yearOldest,
  UnifiedCatalogSort.recentlyWatched => t.unifiedCatalog.sort.recentlyWatched,
  _ => librarySortFieldLabel(sort.field),
};
