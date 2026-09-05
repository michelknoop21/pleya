/// The catalog's controls, in a rail left of the grid
/// (CAT5 / [DEC-093](../../../docs/DECISIONS.md#dec-093), mockup 28 D1/D2).
///
/// Until 4 September 2026 Bronnen, Filters and Sortering were three capsules
/// right of the page heading. On a physical Apple TV that position turned out
/// to be wrong in a way neither CAT3 (where the cluster sits) nor CAT4 (whether
/// it can be reached) could fix: it is far from the wall of posters the remote
/// is actually in, and one UP too many lands in the top navigation. Michel's
/// verdict was a rail, on two conditions: it must not stand in the picture the
/// whole time, and the chosen filters must stay visible in the grid.
///
/// So the rail has two states and this file draws both:
///
/// * **Closed** ([TvCatalogFilterRailStrip]) is a hairline in the page's own
///   left margin. It is the only thing that says LEFT from column 0 does
///   something, and it costs no column.
/// * **Open** ([TvCatalogFilterRailPanel]) is one panel in the tile language,
///   with icon, label and current value per row, the selection as tags, and
///   Wissen underneath. The grid re-columns from six to five around it.
///
/// The second condition is met by [TvCatalogSelectionTagStrip], which draws the
/// same tags beside the heading while the rail is closed.
///
/// **This file owns no state and no navigation.** Which row opens which panel,
/// what closes the rail and where the focus goes are the screen's business
/// (`tv_unified_catalog_screen.dart`), for the same reason the old header bar
/// did not know what sat beside it: the rail is drawn on two catalogs and a
/// watchlist, and each wires its own neighbours.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/focusable_wrapper.dart';
import '../../focus/dpad_navigator.dart';
import '../../i18n/strings.g.dart';
import '../../theme/mono_tokens.dart';
import 'tv_catalog_selection_tags.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

/// Finds the open rail. Public so a test can assert *which* state the rail is
/// in rather than merely that something is drawn on the left.
const Key tvCatalogFilterRailKey = ValueKey('tvCatalogFilterRail');

/// One row of the open rail: what it is, what it currently says, and the four
/// directions out of it.
class TvCatalogFilterRailRow {
  const TvCatalogFilterRailRow({
    required this.icon,
    required this.label,
    required this.value,
    required this.focusNode,
    required this.onPressed,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  final IconData icon;
  final String label;

  /// What the row is set to right now: "Alle · 3 servers", "2 actief", "Titel
  /// A–Z". Mockup 28 D2 puts it under the label rather than behind a chevron,
  /// so the rail answers the question without being opened.
  final String value;

  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onBack;
}

/// The closed rail: a quiet vertical line in hoofdstuk 8.1's left margin.
///
/// Sized and placed by the caller, which is the only thing that knows where the
/// grid's content box begins.
class TvCatalogFilterRailStrip extends StatelessWidget {
  const TvCatalogFilterRailStrip({super.key, required this.scale});

  final double scale;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    return Center(
      child: Container(
        width: TvCatalogLayout.railStripWidth * scale,
        height: TvCatalogLayout.railStripHeight * scale,
        decoration: BoxDecoration(
          color: tk.text.withValues(alpha: TvCatalogLayout.railStripAlpha),
          borderRadius: BorderRadius.circular(TvCatalogLayout.railStripWidth * scale / 2),
        ),
      ),
    );
  }
}

/// The open rail.
class TvCatalogFilterRailPanel extends StatelessWidget {
  const TvCatalogFilterRailPanel({
    super.key,
    required this.rows,
    required this.tags,
    required this.scale,
    this.onClear,
    this.clearFocusNode,
    this.onClearNavigateUp,
    this.onClearNavigateDown,
    this.onClearNavigateLeft,
    this.onClearNavigateRight,
    this.onClearBack,
  });

  final List<TvCatalogFilterRailRow> rows;

  /// The same tags the heading shows while the rail is closed, uncapped: the
  /// panel wraps, so it can afford to show everything.
  final List<TvCatalogSelectionTag> tags;

  final double scale;

  /// Null when there is nothing to clear, because a "Wissen" that clears nothing is a
  /// focus stop that does nothing, which on a remote costs a press to discover.
  final VoidCallback? onClear;
  final FocusNode? clearFocusNode;
  final VoidCallback? onClearNavigateUp;
  final VoidCallback? onClearNavigateDown;
  final VoidCallback? onClearNavigateLeft;
  final VoidCallback? onClearNavigateRight;
  final VoidCallback? onClearBack;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final padding = TvCatalogLayout.railPanelPadding * scale;

    return DecoratedBox(
      decoration: tvPanelDecoration(tk, TvCatalogLayout.railPanelRadius * scale),
      // Shrink-wrapped until it cannot be. The panel is as tall as its content
      // (mockup 28 D2 draws it that way), but [tags] is not capped here the way
      // the heading caps it, so a viewer with a dozen genres ticked can make it
      // taller than the page. A scroll view shrink-wraps under a loose height
      // constraint and clips under a tight one, which turns an overflow into a
      // list that the focus traversal scrolls as it walks.
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(padding),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              for (final row in rows) _RailRow(row: row, scale: scale),
              if (tags.isNotEmpty) ...[
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: TvCatalogLayout.railDividerInset * scale,
                    vertical: TvCatalogLayout.railDividerGap * scale,
                  ),
                  child: Container(height: 1, color: tk.outline),
                ),
                Padding(
                  padding: EdgeInsets.symmetric(
                    horizontal: TvCatalogLayout.railTagsPaddingHorizontal * scale,
                    vertical: TvCatalogLayout.railTagsPaddingVertical * scale,
                  ),
                  child: TvCatalogSelectionTagStrip(tags: tags, scale: scale, wrap: true),
                ),
              ],
              if (onClear != null)
                _ClearRow(
                  scale: scale,
                  focusNode: clearFocusNode,
                  onPressed: onClear!,
                  onNavigateUp: onClearNavigateUp,
                  onNavigateDown: onClearNavigateDown,
                  onNavigateLeft: onClearNavigateLeft,
                  onNavigateRight: onClearNavigateRight,
                  onBack: onClearBack,
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailRow extends StatefulWidget {
  const _RailRow({required this.row, required this.scale});

  final TvCatalogFilterRailRow row;
  final double scale;

  @override
  State<_RailRow> createState() => _RailRowState();
}

class _RailRowState extends State<_RailRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final row = widget.row;
    final scale = widget.scale;
    final tk = tokens(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TvCatalogLayout.railRowRadius * scale));

    return FocusableWrapper(
      focusNode: row.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      // Armed for the reason the tvOS gotcha in CLAUDE.md gives: this Select
      // opens an overlay that takes the focus, so the matching key-up would
      // otherwise land on whatever the overlay autofocuses.
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        row.onPressed();
      },
      onNavigateUp: row.onNavigateUp,
      onNavigateDown: row.onNavigateDown,
      onNavigateLeft: row.onNavigateLeft,
      onNavigateRight: row.onNavigateRight,
      onBack: row.onBack,
      // No scale. The rail sits against a grid that must hold still (hoofdstuk
      // 10.2b's "ruimtelijk stabiel"), and a row that grows on focus pushes the
      // rows under it while the eye is reading them.
      disableScale: true,
      focusShapeBorder: shape,
      semanticLabel: '${row.label}: ${row.value}',
      child: Padding(
        // The ring is held off the row for the reason `TvPanelButton`
        // documents: `FocusableWrapper` paints it on its child's bounds, and a
        // white ring flush against a filled row reads as a slightly fatter row.
        padding: EdgeInsets.all(TvCatalogLayout.railRowFocusRingGap * scale),
        child: Container(
          height: TvCatalogLayout.railRowHeight * scale,
          decoration: ShapeDecoration(
            shape: shape,
            color: _isFocused ? tk.text.withValues(alpha: TvCatalogLayout.railRowFocusedFill) : Colors.transparent,
          ),
          padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.railRowPaddingHorizontal * scale),
          child: Row(
            children: [
              Icon(
                row.icon,
                size: TvCatalogLayout.railIconSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      row.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TvCatalogLayout.railLabelFontSize * scale,
                        fontWeight: FontWeight.w500,
                        color: tk.text,
                        height: 1.1,
                      ),
                    ),
                    SizedBox(height: TvCatalogLayout.railValueGap * scale),
                    Text(
                      row.value,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: TvCatalogLayout.railValueFontSize * scale,
                        color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
                        height: 1.1,
                      ),
                    ),
                  ],
                ),
              ),
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              Icon(
                Symbols.chevron_right_rounded,
                size: TvCatalogLayout.railChevronSize * scale,
                color: tk.text.withValues(alpha: TvSourcePickerLayout.inkTertiary),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ClearRow extends StatefulWidget {
  const _ClearRow({
    required this.scale,
    required this.onPressed,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  final double scale;
  final VoidCallback onPressed;
  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onBack;

  @override
  State<_ClearRow> createState() => _ClearRowState();
}

class _ClearRowState extends State<_ClearRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final tk = tokens(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TvCatalogLayout.railRowRadius * scale));

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        widget.onPressed();
      },
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onBack: widget.onBack,
      disableScale: true,
      focusShapeBorder: shape,
      child: Padding(
        padding: EdgeInsets.all(TvCatalogLayout.railRowFocusRingGap * scale),
        child: Container(
          height: TvCatalogLayout.railClearHeight * scale,
          decoration: ShapeDecoration(
            shape: shape,
            color: _isFocused ? tk.text.withValues(alpha: TvCatalogLayout.railRowFocusedFill) : Colors.transparent,
          ),
          padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.railRowPaddingHorizontal * scale),
          child: Row(
            children: [
              Icon(
                Symbols.close_rounded,
                size: TvCatalogLayout.railClearIconSize * scale,
                color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
              ),
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              Expanded(
                child: Text(
                  t.unifiedCatalog.states.clearFilters,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvCatalogLayout.railClearFontSize * scale,
                    color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
                    height: 1.1,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
