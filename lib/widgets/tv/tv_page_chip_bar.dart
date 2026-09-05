/// A row of capsules on a nested TV page: page actions, and pickers.
///
/// The audit of 2 September 2026 found the same defect twice. Logs drew its
/// four actions as round desktop icon buttons in a `CustomAppBar`, and
/// Bibliotheken drew its tabs as text with a red rule under the active one.
/// Neither is what the rest of the TV product uses: the catalog header bar has
/// had a settled capsule language since hoofdstuk 10.6 — a stadium fill at
/// [TvCatalogLayout.actionFill], secondary ink while idle, an outline only
/// when the control is carrying a value, and the white focus ring drawn
/// outside the capsule's own shape.
///
/// So that language moves here and both pages use it, instead of each page
/// inventing an affordance. This is the same argument [TvMenuGrid] makes for
/// the tile, one level down: a viewer should not have to learn what "focused"
/// looks like twice on the way to a log line.
///
/// Traversal is the bar's own. LEFT and RIGHT walk the chips and stop at the
/// ends rather than wrapping, because a wrapping row of four in a page that
/// also scrolls vertically makes it impossible to tell where you are. UP and
/// DOWN hand back to the page.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/scroll_utils.dart';
import 'tv_unified_layout.dart';

/// One capsule in a [TvPageChipBar].
class TvPageChip {
  const TvPageChip({required this.key, required this.label, this.icon, this.selected = false, this.onSelect});

  /// Stable within the bar, and the focus key.
  final String key;
  final String label;
  final IconData? icon;

  /// Drawn as the chosen one of a set: full ink and an outline, the same way
  /// the catalog header marks an action that is carrying a value. A bar whose
  /// chips are actions rather than a choice leaves this false throughout.
  final bool selected;

  /// Null disables the chip. It keeps its place — an action that comes back
  /// when there is something to act on should not move the ones beside it.
  final VoidCallback? onSelect;
}

class TvPageChipBar extends StatelessWidget {
  const TvPageChipBar({
    super.key,
    required this.chips,
    required this.nodes,
    this.automationInstance,
    this.onExitUp,
    this.onExitDown,
    this.singleLine = false,
  });

  /// One row that scrolls sideways, instead of wrapping onto a second.
  ///
  /// For a bar that lives inside a `PreferredSize`, which cannot measure its
  /// child: a wrapping bar is one height with four chips and another with
  /// seven, and the app bar would reserve the wrong one. The chooser on
  /// Bibliotheken is that case. Ask [heightFor] for the number.
  final bool singleLine;

  /// The height [singleLine] occupies, for a caller that has to declare it.
  ///
  /// Every term is one of the things the capsule below actually draws, so a
  /// token change moves this with it. From the outside in: the halo
  /// [FocusableWrapper] reserves around a shaped focus ring, which is a border
  /// width rather than a layout token and therefore does not scale; the gap
  /// between capsule and ring; the capsule's own vertical padding; and the
  /// taller of the glyph and the label's line box.
  ///
  /// `tv_library_chooser_test.dart` measures a real bar against this. It has
  /// to: the library header reserves this number inside a `PreferredSize`,
  /// which cannot measure its child, and a number that drifts low clips the
  /// tab line underneath it.
  static double heightFor(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final line = TvCatalogLayout.actionIconSize > TvCatalogLayout.actionFontSize * 1.1
        ? TvCatalogLayout.actionIconSize
        : TvCatalogLayout.actionFontSize * 1.1;
    return FocusTheme.focusBorderWidth * 2 +
        (TvCatalogLayout.actionFocusRingGap * 2 + TvCatalogLayout.actionPaddingVertical * 2 + line) * scale;
  }

  final List<TvPageChip> chips;

  /// Owned by the page's State: a chip row rebuilds on every filter change and
  /// on every arriving log line, and a node rebuilt underneath the remote is a
  /// remote that lands nowhere.
  final FocusMemoryTracker nodes;

  final String? automationInstance;
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  void _focus(String key) {
    final node = nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  /// The next chip in [delta]'s direction that can actually take the focus.
  /// A disabled chip is skipped rather than swallowing the press.
  void _step(int from, int delta) {
    for (var i = from + delta; i >= 0 && i < chips.length; i += delta) {
      if (chips[i].onSelect != null) return _focus(chips[i].key);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final gap = TvCatalogLayout.actionGap * scale;

    final capsules = [
      for (var i = 0; i < chips.length; i++)
        _TvPageChipCapsule(
          chip: chips[i],
          scale: scale,
          node: nodes.get(chips[i].key, debugLabel: chips[i].key),
          automationInstance: automationInstance == null ? chips[i].key : '$automationInstance.${chips[i].key}',
          // A chip that scrolled off the edge is a chip the viewer cannot see
          // they are standing on. [FocusableWrapper]'s own scroll-into-view is
          // vertical only, so a sideways bar has to say so itself.
          centreOnFocus: singleLine,
          onNavigateLeft: () => _step(i, -1),
          onNavigateRight: () => _step(i, 1),
          onNavigateUp: onExitUp,
          onNavigateDown: onExitDown,
        ),
    ];

    if (!singleLine) return Wrap(spacing: gap, runSpacing: gap, children: capsules);

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (var i = 0; i < capsules.length; i++) ...[if (i > 0) SizedBox(width: gap), capsules[i]],
        ],
      ),
    );
  }
}

class _TvPageChipCapsule extends StatelessWidget {
  const _TvPageChipCapsule({
    required this.chip,
    required this.scale,
    required this.node,
    required this.automationInstance,
    this.centreOnFocus = false,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final TvPageChip chip;
  final double scale;
  final FocusNode node;
  final String automationInstance;
  final bool centreOnFocus;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final enabled = chip.onSelect != null;
    final shape = StadiumBorder(
      side: chip.selected
          ? BorderSide(color: tk.text.withValues(alpha: TvCatalogLayout.cardOutline), width: 1)
          : BorderSide.none,
    );
    final ink = !enabled
        ? TvCatalogLayout.inkSecondary * 0.5
        : chip.selected
        ? TvCatalogLayout.inkPrimary
        : TvCatalogLayout.inkSecondary;

    return FocusableWrapper(
      focusNode: node,
      onSelect: chip.onSelect,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      // The ring is the capsule's own shape, drawn outside it with a gap, for
      // the reason `_ActionCapsule` documents: a rectangular ring around a
      // stadium reads as a mistake.
      focusShapeBorder: shape,
      disableScale: true,
      canRequestFocus: enabled,
      automationId: AutomationIds.myPleyaChip,
      automationInstance: automationInstance,
      automationRole: 'button',
      // `selected` is always present, never conditional. A scenario asserting
      // that a filter is *off* has to be able to read false; a field that
      // simply disappears reads as null and fails the assertion it should
      // satisfy — which is exactly how this first ran.
      automationState: () => <String, Object?>{'label': chip.label, 'enabled': enabled, 'selected': chip.selected},
      semanticLabel: chip.label,
      onFocusChange: !centreOnFocus
          ? null
          : (focused) {
              if (focused) scrollContextToCenter(node.context);
            },
      child: ExcludeSemantics(
        child: Container(
          // Margin, not a Padding wrapper: a Container lays out margin, then
          // decoration, then padding, so this is the same picture one widget
          // shallower.
          margin: EdgeInsets.all(TvCatalogLayout.actionFocusRingGap * scale),
          decoration: ShapeDecoration(
            shape: shape,
            color: tk.text.withValues(alpha: TvCatalogLayout.actionFill),
          ),
          padding: EdgeInsets.symmetric(
            horizontal: TvCatalogLayout.actionPaddingHorizontal * scale,
            vertical: TvCatalogLayout.actionPaddingVertical * scale,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (chip.icon != null) ...[
                Icon(
                  chip.icon,
                  size: TvCatalogLayout.actionIconSize * scale,
                  color: tk.text.withValues(alpha: ink),
                ),
                SizedBox(width: TvCatalogLayout.actionIconGap * scale),
              ],
              Text(
                chip.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: TvCatalogLayout.actionFontSize * scale,
                  fontWeight: FontWeight.w600,
                  color: tk.text.withValues(alpha: ink),
                  height: 1.1,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
