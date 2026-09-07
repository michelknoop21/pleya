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
/// [DEC-108](../../../docs/DECISIONS.md#dec-108) adds a third:
///
/// * **Opened onto one question** ([TvCatalogFilterRailSubview]) replaces the
///   panel in place with a back row and one row per answer. It is what the
///   kijklijst, Aanvragen and Zoeken use instead of an overlay panel, and it is
///   what closes TOK3.
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

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
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
    this.automationInstance,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onBack,
  });

  /// What a Pleya Verify scenario calls this row:
  /// `tv.catalog.rail.row[<surface>.<row>]`. Null leaves the row unaddressable,
  /// which is what a surface with no scenario yet gets.
  final String? automationInstance;

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
              for (final row in rows)
                AutomationNode(
                  id: row.automationInstance == null ? null : AutomationIds.tvCatalogRailRow,
                  instance: row.automationInstance,
                  role: 'list.item',
                  label: row.label,
                  focusNode: row.focusNode,
                  child: _RailRow(row: row, scale: scale),
                ),
              if (tags.isNotEmpty) ...[
                Container(
                  // Margin, not a Padding wrapper: same box, one widget shallower.
                  margin: EdgeInsets.symmetric(
                    horizontal: TvCatalogLayout.railDividerInset * scale,
                    vertical: TvCatalogLayout.railDividerGap * scale,
                  ),
                  height: 1,
                  color: tk.outline,
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
      child: Container(
        // The ring is held off the row for the reason `TvPanelButton`
        // documents: `FocusableWrapper` paints it on its child's bounds, and a
        // white ring flush against a filled row reads as a slightly fatter row.
        // Margin rather than a Padding wrapper: a Container lays out margin,
        // then decoration, then padding, so the bounds are the same.
        margin: EdgeInsets.all(TvCatalogLayout.railRowFocusRingGap * scale),
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
      child: Container(
        // Margin, not a Padding wrapper: same bounds for the focus ring.
        margin: EdgeInsets.all(TvCatalogLayout.railRowFocusRingGap * scale),
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
    );
  }
}

/// Finds the rail opened onto one question. Public for the same reason
/// [tvCatalogFilterRailKey] is: a test asserts *which* state the rail is in.
const Key tvCatalogFilterRailSubviewKey = ValueKey('tvCatalogFilterRailSubview');

/// One answer inside a rail subview: what it says, how many titles are behind
/// it, and what picking it does.
class TvCatalogRailOption {
  const TvCatalogRailOption({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.count,
    this.automationInstance,
  });

  /// What a scenario calls this answer: `tv.catalog.rail.row[<surface>.<key>]`,
  /// in the same family as the rows one layer up, because from the remote's
  /// point of view they are the same list.
  final String? automationInstance;

  final String label;
  final bool isSelected;
  final VoidCallback onPressed;

  /// Drawn on the right when the screen knows it. Null when it does not, which
  /// is honest: mockup 35 D shows counts because Seerr reports them, and a
  /// zero would claim there is nothing behind a choice that has simply not
  /// been counted.
  final int? count;
}

/// The rail opened onto one of its questions
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108) (4), mockup 35 D).
///
/// It replaces the panel in place rather than opening an overlay over it, and
/// that is the whole point of the shape. On the catalog a rail row opens
/// `showTvCatalogFilterPanel`, a sheet in front of the page, because that panel
/// is two zones wide and carries a multi-select behind an Apply. A kijklijst's
/// Soort and an aanvraag's Status are one column of radio options; putting
/// those behind an overlay costs a focus hand-off out of the rail and back into
/// it, for a list that already fits where the rail stands.
///
/// It also answers TOK3. The status choice used to be a `SegmentedTabGroup` —
/// the one segmented accent on TV that no other TV surface carries — and this
/// is what replaces it.
///
/// **The focus wiring is internal, unlike the panel's.** `TvCatalogFilterRailPanel`
/// hands every direction to the screen because each of its rows has a different
/// destination; here every row has the same three ([onNavigateLeft] back a
/// layer, [onNavigateRight] to the grid, Menu back a layer) and the fourth is
/// simply the row above or below. Wiring that in the screen would mean the
/// screen owning a focus node per genre, and a rail row left unwired falls
/// through to Flutter's directional traversal, which from a rail walks sideways
/// into the grid and leaves the rail standing open with the focus somewhere
/// else — the one state the whole rail contract exists to prevent.
class TvCatalogFilterRailSubview extends StatefulWidget {
  const TvCatalogFilterRailSubview({
    super.key,
    required this.title,
    required this.options,
    required this.scale,
    required this.onBack,
    this.onExitUp,
    this.onExitDown,
    this.onExitRight,
  });

  /// The question this subview answers — "Soort", "Status", "Sortering".
  final String title;

  final List<TvCatalogRailOption> options;
  final double scale;

  /// Back to the rail's own rows. Reached from the back row, from LEFT, and
  /// from Menu, which is [DEC-101](../../../docs/DECISIONS.md#dec-101) punt 3's
  /// "één laag terug" seen on a second surface.
  final VoidCallback onBack;

  /// UP off the back row and DOWN off the last option.
  ///
  /// Explicit rather than left null, for the reason the class doc gives: a null
  /// handler is a fall-through into the grid, not a dead end.
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  /// RIGHT out of the subview — the grid, with the rail closed behind it.
  final VoidCallback? onExitRight;

  @override
  State<TvCatalogFilterRailSubview> createState() => _TvCatalogFilterRailSubviewState();
}

class _TvCatalogFilterRailSubviewState extends State<TvCatalogFilterRailSubview> {
  final _backFocus = FocusNode(debugLabel: 'TvCatalogRailSubviewBack');
  List<FocusNode> _optionFocus = const [];

  @override
  void initState() {
    super.initState();
    _syncNodes();
    // The subview opens on the answer the viewer currently has, rather than at
    // the top of a list they then walk down — the same rule the sort panel
    // follows with its `initialFocusNode`, and the same one mockup 35 D draws
    // with the ring on "In afwachting".
    WidgetsBinding.instance.addPostFrameCallback((_) => focusSelected());
  }

  @override
  void didUpdateWidget(TvCatalogFilterRailSubview oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.options.length != widget.options.length) _syncNodes();
  }

  void _syncNodes() {
    final wanted = widget.options.length;
    final nodes = [..._optionFocus];
    while (nodes.length > wanted) {
      nodes.removeLast().dispose();
    }
    while (nodes.length < wanted) {
      nodes.add(FocusNode(debugLabel: 'TvCatalogRailSubviewOption${nodes.length}'));
    }
    _optionFocus = nodes;
  }

  @override
  void dispose() {
    _backFocus.dispose();
    for (final node in _optionFocus) {
      node.dispose();
    }
    super.dispose();
  }

  /// Puts the remote on the chosen answer, or on the back row when there is
  /// nothing to choose from. Called on open and reachable from the screen, which
  /// is what makes the subview a place the rail can hand the focus to.
  void focusSelected() {
    if (!mounted) return;
    final index = widget.options.indexWhere((option) => option.isSelected);
    final node = index >= 0 && index < _optionFocus.length ? _optionFocus[index] : _optionFocus.firstOrNull;
    final target = node ?? _backFocus;
    if (target.canRequestFocus) target.requestFocus();
  }

  void _focusOption(int index) {
    if (index < 0 || index >= _optionFocus.length) return;
    final node = _optionFocus[index];
    if (node.canRequestFocus) node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = widget.scale;
    final options = widget.options;

    return DecoratedBox(
      decoration: tvPanelDecoration(tk, TvCatalogLayout.railPanelRadius * scale),
      // Same reason the panel above scrolls: a question with a dozen answers —
      // every genre TMDB knows — can outgrow the page, and a scroll view
      // shrink-wraps under a loose height constraint and clips under a tight
      // one, which turns an overflow into a list the traversal scrolls as it
      // walks.
      child: SingleChildScrollView(
        child: Padding(
          padding: EdgeInsets.all(TvCatalogLayout.railPanelPadding * scale),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _RailBackRow(
                title: widget.title,
                scale: scale,
                focusNode: _backFocus,
                onPressed: widget.onBack,
                onNavigateUp: widget.onExitUp,
                onNavigateDown: options.isEmpty ? widget.onExitDown : () => _focusOption(0),
                onNavigateLeft: widget.onBack,
                onNavigateRight: widget.onExitRight,
              ),
              Container(
                // Margin, not a Padding wrapper: same box, one widget shallower.
                margin: EdgeInsets.symmetric(
                  horizontal: TvCatalogLayout.railDividerInset * scale,
                  vertical: TvCatalogLayout.railDividerGap * scale,
                ),
                height: 1,
                color: tk.outline,
              ),
              for (var i = 0; i < options.length; i++)
                AutomationNode(
                  id: options[i].automationInstance == null ? null : AutomationIds.tvCatalogRailRow,
                  instance: options[i].automationInstance,
                  role: 'list.item',
                  label: options[i].label,
                  focusNode: _optionFocus[i],
                  child: _RailOptionRow(
                    option: options[i],
                    scale: scale,
                    focusNode: _optionFocus[i],
                    onNavigateUp: i == 0 ? () => _backFocus.requestFocus() : () => _focusOption(i - 1),
                    onNavigateDown: i == options.length - 1 ? widget.onExitDown : () => _focusOption(i + 1),
                    onNavigateLeft: widget.onBack,
                    onNavigateRight: widget.onExitRight,
                    onBack: widget.onBack,
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _RailBackRow extends StatefulWidget {
  const _RailBackRow({
    required this.title,
    required this.scale,
    required this.onPressed,
    required this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
  });

  final String title;
  final double scale;
  final VoidCallback onPressed;
  final FocusNode focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  @override
  State<_RailBackRow> createState() => _RailBackRowState();
}

class _RailBackRowState extends State<_RailBackRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final tk = tokens(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TvCatalogLayout.railRowRadius * scale));

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onSelect: widget.onPressed,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onBack: widget.onPressed,
      disableScale: true,
      focusShapeBorder: shape,
      child: Container(
        // Margin, not a Padding wrapper: same bounds for the focus ring.
        margin: EdgeInsets.all(TvCatalogLayout.railRowFocusRingGap * scale),
        height: TvCatalogLayout.railBackHeight * scale,
        decoration: ShapeDecoration(
          shape: shape,
          color: _isFocused ? tk.text.withValues(alpha: TvCatalogLayout.railRowFocusedFill) : Colors.transparent,
        ),
        padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.railRowPaddingHorizontal * scale),
        child: Row(
          children: [
            Icon(
              Symbols.arrow_back_rounded,
              size: TvCatalogLayout.railBackIconSize * scale,
              color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
            ),
            SizedBox(width: TvCatalogLayout.railIconGap * scale),
            Expanded(
              child: Text(
                widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvCatalogLayout.railBackFontSize * scale,
                  color: tk.text.withValues(alpha: TvCatalogLayout.inkSecondary),
                  height: 1.1,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _RailOptionRow extends StatefulWidget {
  const _RailOptionRow({
    required this.option,
    required this.scale,
    required this.focusNode,
    required this.onBack,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
  });

  final TvCatalogRailOption option;
  final double scale;
  final FocusNode focusNode;
  final VoidCallback onBack;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  @override
  State<_RailOptionRow> createState() => _RailOptionRowState();
}

class _RailOptionRowState extends State<_RailOptionRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final scale = widget.scale;
    final tk = tokens(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TvCatalogLayout.railRowRadius * scale));
    final count = option.count;

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onSelect: option.onPressed,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onBack: widget.onBack,
      // No scale, for the reason `_RailRow` gives: the rail stands against a
      // grid that must hold still, and a row that grows on focus pushes the
      // rows under it while the eye is reading them.
      disableScale: true,
      focusShapeBorder: shape,
      semanticLabel: count == null ? option.label : '${option.label}, $count',
      child: Container(
        margin: EdgeInsets.all(TvCatalogLayout.railRowFocusRingGap * scale),
        height: TvCatalogLayout.railOptionHeight * scale,
        decoration: ShapeDecoration(
          shape: shape,
          color: _isFocused ? tk.text.withValues(alpha: TvCatalogLayout.railRowFocusedFill) : Colors.transparent,
        ),
        padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.railRowPaddingHorizontal * scale),
        child: Row(
          children: [
            // The tick sits in the column the rail rows one layer up put their
            // icon in, so the labels line up between the two layers. Reserved
            // whether it is drawn or not: a checked row that shifts sideways
            // under the eye is DEC-053's other half, where "this is the answer"
            // and "this is where I am" have to stay two different statements.
            SizedBox(
              width: TvCatalogLayout.railIconSize * scale,
              child: option.isSelected
                  ? Icon(Symbols.check_rounded, size: TvCatalogLayout.railOptionCheckSize * scale, color: tk.text)
                  : null,
            ),
            SizedBox(width: TvCatalogLayout.railIconGap * scale),
            Expanded(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvCatalogLayout.railOptionFontSize * scale,
                  fontWeight: option.isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: tk.text.withValues(
                    alpha: option.isSelected ? TvCatalogLayout.inkPrimary : TvCatalogLayout.railOptionIdleInk,
                  ),
                  height: 1.1,
                ),
              ),
            ),
            if (count != null) ...[
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              Text(
                '$count',
                maxLines: 1,
                style: TextStyle(
                  fontSize: TvCatalogLayout.railOptionCountFontSize * scale,
                  color: tk.text.withValues(alpha: TvCatalogLayout.railOptionCountInk),
                  height: 1.1,
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}
