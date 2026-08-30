/// The sort panel of hoofdstuk 10.5, in the fase-4 panel language.
///
/// A single column of the seven sorts that set is fixed at, one focus stop
/// each, with the current one marked. Choosing applies immediately and closes —
/// unlike the filter panel, which batches behind Apply.
///
/// The asymmetry is deliberate and comes from hoofdstuk 10.6's own reason for
/// batching filters: "zodat de grid niet na elke remote-klik herlaadt en focus
/// steelt". A sort is one choice out of seven, so there is no second click to
/// protect against; making the user press Apply after picking one radio option
/// would add a step to the most common adjustment on the page.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../i18n/strings.g.dart';
import '../../services/unified_catalog/unified_catalog_filters.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../overlay_sheet.dart';
import '../overlay_sheet_geometry.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// The label for one sort, from the single translated set.
///
/// A free function rather than a member on the enum: the enum lives in the
/// services layer, which has no business reading `strings.g.dart`.
String sortLabel(UnifiedCatalogSort sort) => switch (sort) {
  UnifiedCatalogSort.titleAsc => t.unifiedCatalog.sort.titleAsc,
  UnifiedCatalogSort.titleDesc => t.unifiedCatalog.sort.titleDesc,
  UnifiedCatalogSort.recentlyAdded => t.unifiedCatalog.sort.recentlyAdded,
  UnifiedCatalogSort.oldestAdded => t.unifiedCatalog.sort.oldestAdded,
  UnifiedCatalogSort.newestRelease => t.unifiedCatalog.sort.newestRelease,
  UnifiedCatalogSort.oldestRelease => t.unifiedCatalog.sort.oldestRelease,
  UnifiedCatalogSort.recentlyWatched => t.unifiedCatalog.sort.recentlyWatched,
};

/// Opens the panel and returns the chosen sort, or null on Menu/Back/Close.
///
/// `restoreLauncherFocus` is what returns focus to the header action that
/// opened it — the shared mechanism fase 5A lifted out of the source picker, so
/// there is one focus-restore contract on this platform and not three.
Future<UnifiedCatalogSort?> showTvCatalogSortPanel(BuildContext context, {required UnifiedCatalogSort selected}) {
  final initialFocusNode = FocusNode(debugLabel: 'TvCatalogSortInitialFocus');
  return OverlaySheetController.showAdaptive<UnifiedCatalogSort>(
    context,
    presentation: OverlaySheetPresentation.panel,
    initialFocusNode: initialFocusNode,
    restoreLauncherFocus: true,
    builder: (sheetContext) => TvCatalogSortPanel(
      selected: selected,
      initialFocusNode: initialFocusNode,
      onSelect: (sort) => OverlaySheetController.closeAdaptive(sheetContext, sort),
      onClose: () => OverlaySheetController.closeAdaptive(sheetContext, null),
    ),
  );
}

class TvCatalogSortPanel extends StatefulWidget {
  const TvCatalogSortPanel({
    super.key,
    required this.selected,
    required this.onSelect,
    required this.onClose,
    this.initialFocusNode,
  });

  final UnifiedCatalogSort selected;
  final ValueChanged<UnifiedCatalogSort> onSelect;
  final VoidCallback onClose;

  /// Focused by the overlay host on open. Carried by the row that is already
  /// selected, so the panel opens on the answer the user currently has rather
  /// than at the top of a list they have to walk down.
  final FocusNode? initialFocusNode;

  @override
  State<TvCatalogSortPanel> createState() => _TvCatalogSortPanelState();
}

class _TvCatalogSortPanelState extends State<TvCatalogSortPanel> {
  @override
  void dispose() {
    widget.initialFocusNode?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = tvPanelBorderRadius(MediaQuery.sizeOf(context));

    return DecoratedBox(
      decoration: tvPanelDecoration(mono, radius),
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.panelPadding * scale),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              t.unifiedCatalog.sort.title,
              style: TextStyle(
                fontSize: TvSourcePickerLayout.titleFontSize * scale,
                fontWeight: FontWeight.w700,
                color: mono.text,
                letterSpacing: -0.3,
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.sectionGap * scale),
            Flexible(
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    for (var i = 0; i < UnifiedCatalogSort.values.length; i++) ...[
                      if (i > 0) SizedBox(height: TvCatalogLayout.optionRowGap * scale),
                      TvCatalogOptionRow(
                        label: sortLabel(UnifiedCatalogSort.values[i]),
                        isSelected: UnifiedCatalogSort.values[i] == widget.selected,
                        scale: scale,
                        focusNode: UnifiedCatalogSort.values[i] == widget.selected ? widget.initialFocusNode : null,
                        onPressed: () => widget.onSelect(UnifiedCatalogSort.values[i]),
                      ),
                    ],
                  ],
                ),
              ),
            ),
            SizedBox(height: TvSourcePickerLayout.footerGap * scale),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [TvPanelButton(scale: scale, label: t.common.close, onPressed: widget.onClose, primary: false)],
            ),
          ],
        ),
      ),
    );
  }
}

/// One selectable row in a TV panel: a label, and a mark when it is chosen.
///
/// Shared by the sort and the filter panel because a "chosen" state has to look
/// the same in both, and because [DEC-053] is specifically about this: in
/// `monoTheme` a bare Material control with a selection state is invisible —
/// `secondaryContainer`, `primaryContainer` and `surfaceContainerHighest` all
/// resolve to `surface`, the same colour as the panel behind it. So selection
/// is drawn with a glyph and a fill this widget sets explicitly, and never left
/// to a theme role.
///
/// Selected and focused stay two different states, which is the other half of
/// DEC-053: the tick says "this is the answer", the white ring says "this is
/// where I am", and a row can be either, both or neither.
class TvCatalogOptionRow extends StatelessWidget {
  const TvCatalogOptionRow({
    super.key,
    required this.label,
    required this.isSelected,
    required this.scale,
    required this.onPressed,
    this.secondary,
    this.enabled = true,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final String label;

  /// A quieter second line — the server a library belongs to, for instance.
  final String? secondary;

  final bool isSelected;
  final bool enabled;
  final double scale;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final mono = tokens(context);
    final ink = enabled ? TvSourcePickerLayout.inkPrimary : TvSourcePickerLayout.inkDisabledPrimary;

    return FocusableWrapper(
      focusNode: focusNode,
      canRequestFocus: enabled,
      onSelect: enabled ? onPressed : null,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      borderRadius: TvSourcePickerLayout.rowRadius * scale,
      disableScale: true,
      semanticLabel: label,
      child: Container(
        constraints: BoxConstraints(minHeight: TvCatalogLayout.optionRowMinHeight * scale),
        decoration: BoxDecoration(
          color: mono.text.withValues(alpha: TvSourcePickerLayout.idleRowFill),
          borderRadius: BorderRadius.circular(TvSourcePickerLayout.rowRadius * scale),
          border: Border.all(color: mono.text.withValues(alpha: TvSourcePickerLayout.idleRowOutline), width: 1),
        ),
        padding: EdgeInsets.symmetric(
          horizontal: TvCatalogLayout.optionRowPaddingHorizontal * scale,
          vertical: TvCatalogLayout.optionRowPaddingVertical * scale,
        ),
        child: Row(
          children: [
            Expanded(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      fontSize: TvSourcePickerLayout.rowPrimaryFontSize * scale,
                      fontWeight: FontWeight.w600,
                      color: mono.text.withValues(alpha: ink),
                    ),
                  ),
                  if (secondary != null) ...[
                    SizedBox(height: TvSourcePickerLayout.rowLineGap * scale),
                    Text(
                      secondary!,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TvSourcePickerLayout.rowSecondaryFontSize * scale,
                        color: mono.text.withValues(
                          alpha: enabled
                              ? TvSourcePickerLayout.inkSecondary
                              : TvSourcePickerLayout.inkDisabledSecondary,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            ),
            if (isSelected)
              Icon(
                Symbols.check_rounded,
                size: TvSourcePickerLayout.rowPrimaryFontSize * scale * 1.15,
                // White, not the accent. Hoofdstuk 34 keeps red and amber for
                // progress, status and brand moments; "this option is on" is
                // none of those, and a grid of red ticks would make a filter
                // panel look like an error report.
                color: mono.text,
              ),
          ],
        ),
      ),
    );
  }
}
