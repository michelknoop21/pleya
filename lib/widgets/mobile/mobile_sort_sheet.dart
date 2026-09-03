/// The unified catalogue's sort picker. iOS Unified 2026 fase 3.
///
/// Mockup 03 draws the control but not what it opens, and the audit's own rule
/// for that case is the one it applies to the settings sub-pages: a screen
/// without its own composition takes the family's list pattern rather than
/// inventing one. So this is the same sheet body as the source picker — a
/// column of rows with a tick — over `UnifiedCatalogSort`'s seven entries.
///
/// Applies on tap and closes, unlike the filter panel. There is one value
/// here, so there is nothing to assemble before committing, and an Apply
/// button under a radio list would be a second tap for no decision.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../overlay_sheet.dart';
import '../pressable.dart';

/// The label for [sort] on the control and in the sheet.
String mobileSortLabel(UnifiedCatalogSort sort) => switch (sort) {
  UnifiedCatalogSort.titleAsc => t.unifiedCatalog.sort.titleAsc,
  UnifiedCatalogSort.titleDesc => t.unifiedCatalog.sort.titleDesc,
  UnifiedCatalogSort.recentlyAdded => t.unifiedCatalog.sort.recentlyAdded,
  UnifiedCatalogSort.oldestAdded => t.unifiedCatalog.sort.oldestAdded,
  UnifiedCatalogSort.newestRelease => t.unifiedCatalog.sort.newestRelease,
  UnifiedCatalogSort.oldestRelease => t.unifiedCatalog.sort.oldestRelease,
  UnifiedCatalogSort.recentlyWatched => t.unifiedCatalog.sort.recentlyWatched,
};

/// Opens the picker and returns the chosen sort, or null on dismiss.
Future<UnifiedCatalogSort?> showMobileSortSheet(BuildContext context, {required UnifiedCatalogSort current}) {
  return OverlaySheetController.of(context).show<UnifiedCatalogSort>(
    showDragHandle: true,
    builder: (sheetContext) =>
        MobileSortSheet(current: current, onChosen: (sort) => OverlaySheetController.of(sheetContext).pop(sort)),
  );
}

class MobileSortSheet extends StatelessWidget {
  final UnifiedCatalogSort current;
  final ValueChanged<UnifiedCatalogSort> onChosen;

  const MobileSortSheet({super.key, required this.current, required this.onChosen});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return AutomationNode(
      id: AutomationIds.sheetCatalogSort,
      role: 'sheet',
      child: Column(
        mainAxisSize: .min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                t.unifiedCatalog.sort.title,
                style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
              ),
            ),
          ),
          Flexible(
            child: ListView(
              padding: EdgeInsets.only(bottom: 8 + MediaQuery.paddingOf(context).bottom),
              shrinkWrap: true,
              children: [
                for (final sort in UnifiedCatalogSort.values)
                  Pressable(
                    onTap: () => onChosen(sort),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              mobileSortLabel(sort),
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: sort == current ? FontWeight.w600 : FontWeight.w400,
                                color: sort == current ? tk.text : tk.textMuted,
                              ),
                            ),
                          ),
                          if (sort == current) const AppIcon(Symbols.check_rounded, size: 20),
                        ],
                      ),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
