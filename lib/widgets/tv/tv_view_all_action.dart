/// "Alle films ›" — the route from a fase-6 discovery landing to the fase-5
/// complete catalog (hoofdstuk 10.2a, [DEC-064] punt 3 of docs/DECISIONS.md,
/// amended by [DEC-068]).
///
/// DEC-064 states the requirement as a prohibition — "geen minuscuul
/// tekstlinkje waar focus moeilijk komt" — and three tvOS patterns satisfy it:
/// a compact header action, a tile parked at the end of a rail, or a
/// section-level row at the foot of the page.
///
/// The first build chose the third, on the argument that a full-width row is
/// the only shape a remote can hit without aiming: one DOWN from the last rail,
/// no horizontal travel. That reasoning was right about *aiming* and wrong
/// about *distance*. It optimised the path from the bottom of the page, which
/// is where a browsing user ends up, and ignored the path from the top, which
/// is where every user starts. A viewer who opens Films meaning to see all
/// their films had to walk every discovery rail to reach the one control that
/// does it. DEC-068 moves the action beside the page title: still a real
/// target, still no aiming, but now the first thing under the topnav instead of
/// the last thing on the page.
///
/// It is deliberately *quiet*. A pill, a filled button or a toolbar chip beside
/// the heading would read as chrome over the content, and hoofdstuk 10.2a
/// spends a paragraph clearing that band specifically — the landing is
/// content-first. So this is type beside type: secondary size, muted ink, a
/// small chevron, and no surface at all until focus lands on it. The page title
/// stays dominant; this reads as its sibling, not its rival.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../focus/card_focus_scope.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import 'tv_unified_layout.dart';

class TvViewAllAction extends StatefulWidget {
  const TvViewAllAction({
    super.key,
    required this.label,
    required this.onSelect,
    required this.semanticLabel,
    this.focusNode,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onFocusChange,
  });

  /// The visible text — "Alle films" / "Alle series". The chevron after it is
  /// drawn by this widget, not part of the string.
  final String label;

  final VoidCallback onSelect;

  /// Spoken form — "Alle films bekijken". The visible label is a noun phrase
  /// because it sits beside a heading and has to read as one; a screen reader
  /// gets the verb, because out of that visual context "Alle films" does not
  /// say it is a control.
  final String semanticLabel;

  final FocusNode? focusNode;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final ValueChanged<bool>? onFocusChange;

  @override
  State<TvViewAllAction> createState() => _TvViewAllActionState();
}

class _TvViewAllActionState extends State<TvViewAllAction> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = TvDiscoveryLayout.viewAllRadius * scale;
    // Muted at rest so the heading beside it stays the loudest thing in the
    // band; full white under focus, where the ring is already saying so.
    final ink = tk.text.withValues(alpha: _isFocused ? 1 : TvDiscoveryLayout.inkSecondary);

    return FocusableWrapper(
      focusNode: widget.focusNode,
      onSelect: widget.onSelect,
      onNavigateUp: widget.onNavigateUp,
      onNavigateDown: widget.onNavigateDown,
      onFocusChange: (focused) {
        if (mounted && focused != _isFocused) setState(() => _isFocused = focused);
        widget.onFocusChange?.call(focused);
      },
      // Sizing to content, in a Row beside the heading: growing on focus would
      // shift the text under the user's eye and, on a long locale, push the
      // action toward the page edge the layout keeps it away from.
      disableScale: true,
      mode: FocusIndicatorMode.delegated,
      semanticLabel: widget.semanticLabel,
      // Hoofdstuk 25's "geen dubbele semantiek": `FocusableWrapper` labels the
      // control but does not exclude what is under it, so without this the
      // visible "Alle films" would be announced again after the spoken "Alle
      // films bekijken" the label already gave.
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvDiscoveryLayout.viewAllFocusRingGap * scale),
          child: CardFocusBorder(
            borderRadius: radius,
            child: AnimatedContainer(
              duration: reduceMotion(context, FocusTheme.getAnimationDuration(context)),
              curve: Curves.easeOutCubic,
              padding: EdgeInsets.symmetric(
                horizontal: TvDiscoveryLayout.viewAllPaddingHorizontal * scale,
                vertical: TvDiscoveryLayout.viewAllPaddingVertical * scale,
              ),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(radius),
                // No surface at rest at all — it is type on the page. The faint
                // fill under focus sits behind the white ring and only stops the
                // text reading as a floating label while it is the target.
                color: tk.text.withValues(
                  alpha: _isFocused ? TvDiscoveryLayout.viewAllFocusedFill : TvDiscoveryLayout.viewAllFill,
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(
                      widget.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: ink,
                        fontSize: TvDiscoveryLayout.viewAllActionFontSize * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                  SizedBox(width: TvDiscoveryLayout.viewAllIconGap * scale),
                  Icon(Symbols.chevron_right_rounded, size: TvDiscoveryLayout.viewAllIconSize * scale, color: ink),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
