/// The rows of the catalog rail's subview, split out with it. The plain rows
/// are the rail's own; [TvCatalogRailSheetRow] is the same answer in the side
/// panel over a full-bleed catalog (A-06c).
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/dpad_navigator.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import 'tv_unified_layout.dart';

/// One answer inside a rail subview: what it says, how many titles are behind
/// it, and what picking it does.
class TvCatalogRailOption {
  const TvCatalogRailOption({
    required this.label,
    required this.isSelected,
    required this.onPressed,
    this.count,
    this.countUnavailable = false,
    this.automationInstance,
    this.value,
    this.trailingIcon,
    this.dividerAbove = false,
  });

  /// Draws the line between the quick choices and the categories.
  final bool dividerAbove;

  /// Drawn at the right end of a side-panel row, in place of the tick. The
  /// sort page uses it for the direction arrow of the active field.
  final IconData? trailingIcon;

  /// What the row is set to, right-aligned: "All sources", "Title A-Z". Only
  /// the side panel's rows draw it.
  final String? value;

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

  /// The count was asked for and did not come. Drawn as a dash where the
  /// number would stand, which is neither a number nor the silence of a choice
  /// that is never counted.
  final bool countUnavailable;
}

class TvCatalogRailBackRow extends StatefulWidget {
  const TvCatalogRailBackRow({
    super.key,
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
  State<TvCatalogRailBackRow> createState() => _RailBackRowState();
}

class _RailBackRowState extends State<TvCatalogRailBackRow> {
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

class TvCatalogRailOptionRow extends StatefulWidget {
  const TvCatalogRailOptionRow({
    super.key,
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
  State<TvCatalogRailOptionRow> createState() => _RailOptionRowState();
}

class _RailOptionRowState extends State<TvCatalogRailOptionRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final scale = widget.scale;
    final tk = tokens(context);
    final shape = RoundedRectangleBorder(borderRadius: BorderRadius.circular(TvCatalogLayout.railRowRadius * scale));
    final count = option.count;
    final countText = count != null ? '$count' : (option.countUnavailable ? '–' : null);

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
            if (countText != null) ...[
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              Text(
                countText,
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

/// One row of the side panel: a pill that turns white under the focus, in the
/// language of `2026-10-30-set2/02.png`.
///
/// The white fill is the focus indicator, so the wrapper draws no ring: a ring
/// around a white pill on a dark panel says nothing the fill does not. Selected
/// stays its own state, a tick on the right, for the reason [DEC-053] gives.
class TvCatalogRailSheetRow extends StatefulWidget {
  const TvCatalogRailSheetRow({
    super.key,
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
  State<TvCatalogRailSheetRow> createState() => _RailSheetRowState();
}

class _RailSheetRowState extends State<TvCatalogRailSheetRow> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final option = widget.option;
    final scale = widget.scale;
    final tk = tokens(context);
    final ink = _isFocused ? tk.bg : tk.text;
    final count = option.count;
    final trailing = option.value ?? (count != null && count > 0 ? '$count' : null);

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      // Armed for the reason the rail's rows are: this Select swaps the page
      // the focus stands on, or closes the panel.
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        option.onPressed();
      },
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onBack: widget.onBack,
      disableScale: true,
      mode: FocusIndicatorMode.delegated,
      semanticLabel: trailing == null ? option.label : '${option.label}, $trailing',
      child: Container(
        height: TvCatalogFullBleedLayout.sheetRowHeight * scale,
        margin: EdgeInsets.only(bottom: TvCatalogFullBleedLayout.sheetRowGap * scale),
        decoration: BoxDecoration(
          color: _isFocused ? tk.text : Colors.transparent,
          borderRadius: BorderRadius.circular(TvCatalogFullBleedLayout.sheetRowHeight * scale / 2),
        ),
        padding: EdgeInsets.symmetric(horizontal: TvCatalogLayout.railRowPaddingHorizontal * scale),
        child: Row(
          children: [
            Expanded(
              child: Text(
                option.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvCatalogFullBleedLayout.sheetRowFontSize * scale,
                  fontWeight: option.isSelected ? FontWeight.w600 : FontWeight.w400,
                  color: ink,
                  height: 1.1,
                ),
              ),
            ),
            if (trailing != null) ...[
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              ConstrainedBox(
                constraints: BoxConstraints(maxWidth: TvCatalogFullBleedLayout.sheetValueMaxWidth * scale),
                child: Text(
                  trailing,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: TvCatalogFullBleedLayout.sheetValueFontSize * scale,
                    color: ink.withValues(alpha: TvCatalogLayout.inkSecondary),
                    height: 1.1,
                  ),
                ),
              ),
            ],
            if (option.trailingIcon != null || option.isSelected) ...[
              SizedBox(width: TvCatalogLayout.railIconGap * scale),
              Icon(
                option.trailingIcon ?? Symbols.check_rounded,
                size: TvCatalogLayout.railOptionCheckSize * scale,
                // The direction arrow is the one accent on the page.
                color: option.trailingIcon != null ? tokens(context).accent : ink,
              ),
            ],
          ],
        ),
      ),
    );
  }
}
