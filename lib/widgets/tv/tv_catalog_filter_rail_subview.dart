/// The catalog rail opened onto one question
/// ([DEC-108](../../../docs/DECISIONS.md#dec-108) (4), mockup 35 D), split out of
/// `tv_catalog_filter_rail.dart` when A-06c gave it a second look.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../theme/mono_tokens.dart';
import 'tv_catalog_filter_rail_rows.dart';
import 'tv_panel_primitives.dart';
import 'tv_unified_layout.dart';

export 'tv_catalog_filter_rail_rows.dart' show TvCatalogRailOption;

/// Finds the rail opened onto one question. Public for the same reason
/// [tvCatalogFilterRailKey] is: a test asserts *which* state the rail is in.
const Key tvCatalogFilterRailSubviewKey = ValueKey('tvCatalogFilterRailSubview');

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
    this.note,
    this.sheet = false,
    this.initialIndex,
    this.footer,
    this.onExitLeft,
  });

  /// LEFT, where it differs from [onBack]: on a first page there is no layer to
  /// go back to, so LEFT stays and only Menu leaves.
  final VoidCallback? onExitLeft;

  /// A-06c: the look of the side panel over a full-bleed catalog. The title is
  /// a heading instead of a back row, the rows are pills that turn white under
  /// the focus, and the panel around it is the caller's. Menu and LEFT go back
  /// exactly as they do from the back row; only a question without answers
  /// keeps the back row, because the focus needs somewhere to stand.
  final bool sheet;

  /// The row to open on, over the selected one. Coming back up a layer lands
  /// on the row that was left, which is not always a selected one.
  final int? initialIndex;

  /// Drawn under the answers: the selection tags on the overview page.
  final Widget? footer;

  /// One line under the answers, for something the list cannot say per row:
  /// why none of them carries a count, for instance.
  final String? note;

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
  State<TvCatalogFilterRailSubview> createState() => TvCatalogFilterRailSubviewState();
}

class TvCatalogFilterRailSubviewState extends State<TvCatalogFilterRailSubview> {
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
    final index = widget.initialIndex ?? widget.options.indexWhere((option) => option.isSelected);
    final node = index >= 0 && index < _optionFocus.length ? _optionFocus[index] : _optionFocus.firstOrNull;
    final target = node ?? _backFocus;
    if (target.canRequestFocus) target.requestFocus();
  }

  void _focusOption(int index) {
    if (index < 0 || index >= _optionFocus.length) return;
    final node = _optionFocus[index];
    if (node.canRequestFocus) node.requestFocus();
  }

  Widget _option(int i) {
    final options = widget.options;
    final option = options[i];
    final node = _optionFocus[i];
    VoidCallback? up() {
      if (i > 0) return () => _focusOption(i - 1);
      return widget.sheet ? widget.onExitUp : () => _backFocus.requestFocus();
    }

    final onNavigateDown = i == options.length - 1 ? widget.onExitDown : () => _focusOption(i + 1);
    return AutomationNode(
      id: option.automationInstance == null ? null : AutomationIds.tvCatalogRailRow,
      instance: option.automationInstance,
      role: 'list.item',
      label: option.label,
      focusNode: node,
      child: widget.sheet
          ? TvCatalogRailSheetRow(
              option: option,
              scale: widget.scale,
              focusNode: node,
              onNavigateUp: up(),
              onNavigateDown: onNavigateDown,
              onNavigateLeft: widget.onExitLeft ?? widget.onBack,
              onNavigateRight: widget.onExitRight,
              onBack: widget.onBack,
            )
          : TvCatalogRailOptionRow(
              option: option,
              scale: widget.scale,
              focusNode: node,
              onNavigateUp: up(),
              onNavigateDown: onNavigateDown,
              onNavigateLeft: widget.onBack,
              onNavigateRight: widget.onExitRight,
              onBack: widget.onBack,
            ),
    );
  }

  Widget _backRow() => TvCatalogRailBackRow(
    title: widget.title,
    scale: widget.scale,
    focusNode: _backFocus,
    onPressed: widget.onBack,
    onNavigateUp: widget.onExitUp,
    onNavigateDown: widget.options.isEmpty ? widget.onExitDown : () => _focusOption(0),
    onNavigateLeft: widget.onExitLeft ?? widget.onBack,
    onNavigateRight: widget.onExitRight,
  );

  Widget? _noteText(MonoTokens tk) {
    final note = widget.note;
    if (note == null) return null;
    final scale = widget.scale;
    return Padding(
      padding: EdgeInsets.fromLTRB(
        TvCatalogLayout.railRowPaddingHorizontal * scale,
        TvCatalogLayout.railDividerGap * scale,
        TvCatalogLayout.railRowPaddingHorizontal * scale,
        0,
      ),
      child: Text(
        note,
        style: TextStyle(
          fontSize: TvCatalogLayout.railOptionCountFontSize * scale,
          color: tk.text.withValues(alpha: TvCatalogLayout.railOptionCountInk),
          height: 1.25,
        ),
      ),
    );
  }

  Widget _buildSheet(MonoTokens tk) {
    final scale = widget.scale;
    final options = widget.options;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (options.isEmpty)
          _backRow()
        else
          Padding(
            padding: EdgeInsets.only(
              left: TvCatalogLayout.railRowPaddingHorizontal * scale,
              bottom: TvCatalogFullBleedLayout.sheetTitleGap * scale,
            ),
            child: Text(
              widget.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: TvCatalogFullBleedLayout.sheetTitleFontSize * scale,
                fontWeight: FontWeight.w700,
                color: tk.text,
              ),
            ),
          ),
        Expanded(
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (var i = 0; i < options.length; i++) _option(i), ?_noteText(tk), ?widget.footer],
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    if (widget.sheet) return _buildSheet(tk);
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
              _backRow(),
              Container(
                // Margin, not a Padding wrapper: same box, one widget shallower.
                margin: EdgeInsets.symmetric(
                  horizontal: TvCatalogLayout.railDividerInset * scale,
                  vertical: TvCatalogLayout.railDividerGap * scale,
                ),
                height: 1,
                color: tk.outline,
              ),
              for (var i = 0; i < options.length; i++) _option(i),
              ?_noteText(tk),
              ?widget.footer,
            ],
          ),
        ),
      ),
    );
  }
}
