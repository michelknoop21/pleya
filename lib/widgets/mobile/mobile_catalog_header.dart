/// The complete-catalogue header and its three controls. iOS Unified 2026
/// fase 3, mockup `03-alle-films.png`.
///
/// A different header from [MobilePageHeader], not a variant of it. That one
/// is a root destination's header: brand lockup, then actions. This one is a
/// pushed page's header: back, the page's own title, then one action. Folding
/// both into one widget would mean a lockup-or-title switch plus a
/// back-or-nothing switch, and the two shapes have no line in common.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/haptics.dart';
import '../app_icon.dart';
import '../focusable_filter_chip.dart';
import 'mobile_sort_sheet.dart';

class MobileCatalogHeader extends StatelessWidget {
  final String title;
  final VoidCallback onBack;

  /// Opens the global search destination — the same contract the search glyph
  /// carries on Home and on both landings (DEC-094). It deliberately does not
  /// search this catalogue: one glyph, one place, one meaning.
  final VoidCallback onSearch;

  const MobileCatalogHeader({super.key, required this.title, required this.onBack, required this.onSearch});

  /// Measured off the northstar, not chosen.
  ///
  /// Fase 3 shipped 26, and that turned out to be a drift rather than a
  /// contract: rendering "Alle films" in Inter Bold at 26 gives a 348 px ink
  /// box where `03-alle-films.png` has 237 px at the same 3× scale, so the
  /// title was some 47 % too wide. Fitting the three compact headers the
  /// northstar draws — `Alle films` (03), `Zoeken` (05) and `Aanvragen` (19) —
  /// jointly against the real Inter faces lands on 18, within 2,5 % on every
  /// one of the six ink dimensions. The method was calibrated first on the
  /// bottom bar's labels, which come out at the 12 Material paints.
  ///
  /// The large page title on a landing is a different heading and keeps its
  /// own size ([MobilePageTitleRow.titleFontSize]); only the compact
  /// back-and-title header is corrected here.
  static const double titleFontSize = 18;

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.viewPaddingOf(context).top;
    return AutomationNode(
      id: AutomationIds.catalogHeader,
      role: 'region',
      child: Padding(
        padding: EdgeInsets.only(left: 4, right: 8, top: topInset + 8, bottom: 8),
        child: Row(
          children: [
            IconButton(onPressed: onBack, icon: const AppIcon(Symbols.arrow_back_rounded), tooltip: t.common.back),
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(fontSize: titleFontSize, fontWeight: FontWeight.w700),
              ),
            ),
            IconButton(onPressed: onSearch, icon: const AppIcon(Symbols.search_rounded), tooltip: t.common.search),
          ],
        ),
      ),
    );
  }
}

/// The row of three: sources, filters, sort.
///
/// All three are [FilterChipVariant.control] rather than toggles. They are
/// never "off" — a catalogue always has a source scope and a sort — and the
/// audit calls them "de drie rustige controls" for that reason (rapport §5).
class MobileCatalogControls extends StatelessWidget {
  /// How many sources the catalogue is restricted to, or null for all of them.
  /// Drives the first control's label: "All sources" against "N sources".
  final int? restrictedSourceCount;

  /// Fields the filter panel is narrowing right now, after capabilities.
  final int activeFilterCount;

  final UnifiedCatalogSort sort;

  /// Opens the filter panel on the sources section.
  final VoidCallback onSources;

  /// Opens the filter panel on its first section.
  final VoidCallback onFilters;

  final VoidCallback onSort;

  const MobileCatalogControls({
    super.key,
    required this.restrictedSourceCount,
    required this.activeFilterCount,
    required this.sort,
    required this.onSources,
    required this.onFilters,
    required this.onSort,
  });

  @override
  Widget build(BuildContext context) {
    final count = restrictedSourceCount;
    final sourcesLabel = switch (count) {
      null => t.unifiedCatalog.allSources,
      1 => t.unifiedCatalog.oneSource,
      _ => t.unifiedCatalog.sources(count: count),
    };

    void tap(VoidCallback action) {
      Haptics.light();
      action();
    }

    return AutomationNode(
      id: AutomationIds.catalogControls,
      role: 'filter',
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        padding: const EdgeInsets.symmetric(horizontal: 16),
        child: Row(
          children: [
            AutomationNode(
              id: AutomationIds.catalogControlSources,
              role: 'button',
              child: FocusableFilterChip(
                variant: FilterChipVariant.control,
                icon: Symbols.dns_rounded,
                label: sourcesLabel,
                onPressed: () => tap(onSources),
              ),
            ),
            const SizedBox(width: 10),
            AutomationNode(
              id: AutomationIds.catalogControlFilters,
              role: 'button',
              child: FocusableFilterChip(
                variant: FilterChipVariant.control,
                icon: Symbols.filter_list_rounded,
                label: t.unifiedCatalog.filters.title,
                badgeCount: activeFilterCount,
                onPressed: () => tap(onFilters),
              ),
            ),
            const SizedBox(width: 10),
            AutomationNode(
              id: AutomationIds.catalogControlSort,
              role: 'button',
              child: FocusableFilterChip(
                variant: FilterChipVariant.control,
                icon: Symbols.swap_vert_rounded,
                label: mobileSortLabel(sort),
                onPressed: () => tap(onSort),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// "126 titles loaded" on the left, the active-filter summary on the right.
///
/// Never a total. `UnifiedCatalogSnapshot.totalGroupCount` is null until every
/// participating library is exhausted, and hoofdstuk 10.7 forbids adding up
/// per-server counts to fake one: two servers holding the same film would count
/// it twice, and the grid below deliberately shows it once.
class MobileCatalogStatusLine extends StatelessWidget {
  final int loadedCount;
  final String? filterSummary;

  const MobileCatalogStatusLine({super.key, required this.loadedCount, required this.filterSummary});

  @override
  Widget build(BuildContext context) {
    final muted = tokens(context).textMuted;
    final style = TextStyle(color: muted, fontSize: 15);
    final summary = filterSummary;
    return AutomationNode(
      id: AutomationIds.catalogStatus,
      role: 'region',
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 10),
        child: Row(
          children: [
            Text(
              loadedCount == 1 ? t.unifiedCatalog.oneTitle : t.unifiedCatalog.titlesLoaded(count: loadedCount),
              style: style,
            ),
            if (summary != null) ...[
              const SizedBox(width: 12),
              Expanded(
                child: Text(summary, textAlign: TextAlign.right, maxLines: 1, overflow: .ellipsis, style: style),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
