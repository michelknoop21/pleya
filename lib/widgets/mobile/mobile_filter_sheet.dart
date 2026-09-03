/// The unified catalogue's filter panel: two columns, five categories, and a
/// foot that is only Clear and Apply. iOS Unified 2026 fase 3, mockup
/// `04-filters-sheet.png`.
///
/// Two columns rather than the sub-page-per-category shape `FiltersBottomSheet`
/// uses for a single library. That sheet answers "narrow this library", where
/// one category at a time is the whole interaction; this one answers "narrow a
/// catalogue spanning every server", where the point is seeing at a glance
/// which of the five you have touched. Mockup 04 keeps the categories on
/// screen for exactly that reason, with their counts beside them.
///
/// Edits are local until Apply. The catalogue restarts its merge on every query
/// change and a restart scrolls the grid back to the top, so committing per tap
/// would make picking three genres three full reloads — and the middle two
/// would show results nobody asked to see.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../i18n/strings.g.dart';
import '../../services/unified_catalog/source_cursor.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../services/unified_catalog/unified_filter_options.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';
import '../overlay_sheet.dart';
import '../pressable.dart';
import 'mobile_filter_categories.dart';

/// Opens the panel and returns the selection the user applied, or null when
/// they dismissed it (drag, tap-outside, Back) — dismissal keeps the catalogue
/// exactly as it was, which is what makes Apply a real commit.
Future<UnifiedCatalogFilterSelection?> showMobileFilterSheet(
  BuildContext context, {
  required UnifiedCatalogFilterSelection selection,
  required UnifiedFilterCapabilities capabilities,
  required UnifiedFilterOptions options,
  required List<CatalogLibrary> eligibleLibraries,
  MobileFilterCategory initialCategory = MobileFilterCategory.status,
}) {
  return OverlaySheetController.of(context).show<UnifiedCatalogFilterSelection>(
    showDragHandle: true,
    builder: (sheetContext) => MobileFilterSheet(
      selection: selection,
      capabilities: capabilities,
      options: options,
      eligibleLibraries: eligibleLibraries,
      initialCategory: initialCategory,
      onApply: (applied) => OverlaySheetController.of(sheetContext).pop(applied),
    ),
  );
}

class MobileFilterSheet extends StatefulWidget {
  final UnifiedCatalogFilterSelection selection;
  final UnifiedFilterCapabilities capabilities;
  final UnifiedFilterOptions options;
  final List<CatalogLibrary> eligibleLibraries;

  /// Which category the left column opens on. The sources control opens the
  /// panel on [MobileFilterCategory.servers]; the filters control opens it on
  /// the first one (DEC-094).
  final MobileFilterCategory initialCategory;

  final ValueChanged<UnifiedCatalogFilterSelection> onApply;

  const MobileFilterSheet({
    super.key,
    required this.selection,
    required this.capabilities,
    required this.options,
    required this.eligibleLibraries,
    this.initialCategory = MobileFilterCategory.status,
    required this.onApply,
  });

  @override
  State<MobileFilterSheet> createState() => _MobileFilterSheetState();
}

class _MobileFilterSheetState extends State<MobileFilterSheet> {
  late UnifiedCatalogFilterSelection _draft = widget.selection;
  late MobileFilterCategory _open = widget.initialCategory;

  List<MobileFilterSection> get _sections => buildMobileFilterSections(
    selection: _draft,
    capabilities: widget.capabilities,
    options: widget.options,
    eligibleLibraries: widget.eligibleLibraries,
  );

  void _toggle(MobileFilterCategory category, String optionId) {
    setState(() {
      _draft = toggleMobileFilter(selection: _draft, category: category, optionId: optionId);
    });
  }

  @override
  Widget build(BuildContext context) {
    final sections = _sections;
    final open = sections.firstWhere((s) => s.category == _open, orElse: () => sections.first);
    final activeFields = _draft.constrainedTo(widget.capabilities).activeCount;

    return AutomationNode(
      id: AutomationIds.sheetCatalogFilters,
      role: 'sheet',
      child: Column(
        mainAxisSize: .min,
        children: [
          _Head(activeFields: activeFields),
          SizedBox(
            // The panel is as tall as its category column, capped at a little
            // under half the screen — mockup 04's proportion. Without a height
            // the `Row` takes everything the sheet will give it, and a
            // catalogue whose only filters are two watch states drew a
            // full-height panel with one line in it.
            height: _panelHeight(context, sections.length),
            child: Row(
              crossAxisAlignment: .stretch,
              children: [
                SizedBox(
                  width: _categoryColumnWidth,
                  child: _CategoryColumn(
                    sections: sections,
                    open: _open,
                    onOpen: (category) => setState(() => _open = category),
                  ),
                ),
                const VerticalDivider(width: 1, thickness: 1),
                Expanded(
                  child: _OptionColumn(section: open, onToggle: (id) => _toggle(open.category, id)),
                ),
              ],
            ),
          ),
          _Foot(
            onClear: () => setState(() => _draft = UnifiedCatalogFilterSelection.empty),
            onApply: () => widget.onApply(_draft),
          ),
        ],
      ),
    );
  }
}

/// Mockup 04's left column is a third of the sheet; on a 393pt phone that is
/// wide enough for "Bibliotheken" plus its count without wrapping.
const double _categoryColumnWidth = 132;

/// One category row at rest: 16pt text on 14pt of padding either side.
const double _categoryRowHeight = 52;

/// How tall the two columns are together.
///
/// Grows with the number of categories and with the text scale, so a larger
/// system size does not clip a row, and stops at 46% of the screen so the grid
/// behind it stays partly visible — the sheet is a panel over the catalogue,
/// not a page replacing it.
double _panelHeight(BuildContext context, int categoryCount) {
  final scaled = MediaQuery.textScalerOf(context).scale(_categoryRowHeight);
  final natural = categoryCount * scaled;
  return math.min(natural, MediaQuery.sizeOf(context).height * 0.46);
}

class _Head extends StatelessWidget {
  final int activeFields;

  const _Head({required this.activeFields});

  @override
  Widget build(BuildContext context) {
    final muted = tokens(context).textMuted;
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: Row(
        children: [
          Expanded(
            child: Text(
              t.unifiedCatalog.filters.title,
              style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w700),
            ),
          ),
          if (activeFields > 0)
            Text(
              activeFields == 1
                  ? t.unifiedCatalog.filters.activeOne
                  : t.unifiedCatalog.filters.activeCount(count: activeFields),
              style: TextStyle(color: muted, fontSize: 15),
            ),
        ],
      ),
    );
  }
}

/// The category list. The open one carries three marks at once — a leading
/// bar, a lifted band and full-ink bold text — because on this theme any one
/// of them alone is nearly invisible: `monoTheme` maps every container role
/// onto `surface`, so a band by itself is the same colour as the sheet behind
/// it (DEC-053).
class _CategoryColumn extends StatelessWidget {
  final List<MobileFilterSection> sections;
  final MobileFilterCategory open;
  final ValueChanged<MobileFilterCategory> onOpen;

  const _CategoryColumn({required this.sections, required this.open, required this.onOpen});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return ListView(
      padding: EdgeInsets.zero,
      children: [
        for (final section in sections)
          Pressable(
            onTap: () => onOpen(section.category),
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: section.category == open ? tk.surfaceElevated : null,
                border: Border(
                  left: BorderSide(color: section.category == open ? tk.text : Colors.transparent, width: 3),
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(13, 14, 12, 14),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        section.label,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 16,
                          fontWeight: section.category == open ? FontWeight.w700 : FontWeight.w400,
                          color: section.supported
                              ? (section.category == open ? tk.text : tk.textMuted)
                              : tk.textMuted.withValues(alpha: 0.5),
                        ),
                      ),
                    ),
                    if (section.activeCount > 0)
                      Text(
                        '${section.activeCount}',
                        style: TextStyle(fontSize: 15, fontWeight: FontWeight.w600, color: tk.text),
                      ),
                  ],
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _OptionColumn extends StatelessWidget {
  final MobileFilterSection section;
  final ValueChanged<String> onToggle;

  const _OptionColumn({required this.section, required this.onToggle});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    if (!section.supported) return _Notice(text: t.unifiedCatalog.filters.unsupported);
    if (!section.hasOptions) return _Notice(text: t.unifiedCatalog.filters.noValues);

    return ListView(
      padding: const EdgeInsets.symmetric(vertical: 4),
      children: [
        for (final option in section.options)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            child: Pressable(
              onTap: () => onToggle(option.id),
              child: DecoratedBox(
                decoration: BoxDecoration(
                  color: section.selected.contains(option.id) ? tk.surfaceElevated : null,
                  borderRadius: BorderRadius.circular(tk.radiusMd),
                ),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(12, 13, 12, 13),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          option.label,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 16),
                        ),
                      ),
                      if (section.selected.contains(option.id)) const AppIcon(Symbols.check_rounded, size: 20),
                    ],
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

class _Notice extends StatelessWidget {
  final String text;

  const _Notice({required this.text});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 24, 16, 24),
      child: Text(text, style: TextStyle(color: tokens(context).textMuted, fontSize: 15)),
    );
  }
}

/// Clear and Apply, and nothing else — hoofdstuk 33.7, and mockup 04. No
/// close button: the sheet's own drag handle, the barrier and system Back all
/// dismiss it already, and a third way out that looks like the other two
/// buttons would sit next to Apply meaning something different.
class _Foot extends StatelessWidget {
  final VoidCallback onClear;
  final VoidCallback onApply;

  const _Foot({required this.onClear, required this.onApply});

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: tokens(context).outline.withValues(alpha: 0.6))),
      ),
      child: Padding(
        padding: EdgeInsets.fromLTRB(8, 12, 16, 12 + MediaQuery.paddingOf(context).bottom),
        child: Row(
          children: [
            // Muted, not the theme's accent. `monoTheme` paints a bare
            // TextButton in kAccent, and hoofdstuk 34 reserves red for
            // progress, live and the active navigation mark — a red "Clear
            // all" reads as a destructive warning about the user's own
            // filters. Mockup 04 draws it in the same grey as the body text.
            TextButton(
              onPressed: onClear,
              style: TextButton.styleFrom(foregroundColor: tokens(context).textMuted),
              child: Text(t.unifiedCatalog.filters.clearAll),
            ),
            const Spacer(),
            FilledButton(onPressed: onApply, child: Text(t.unifiedCatalog.filters.apply)),
          ],
        ),
      ),
    );
  }
}
