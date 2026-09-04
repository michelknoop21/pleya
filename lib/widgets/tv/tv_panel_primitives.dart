/// The two pieces every Pleya TV panel is built from: the surface it stands on
/// and the buttons along its bottom edge.
///
/// Both were written for the fase-4 source picker and both were private to it.
/// Fase 5 adds the filter and the sort panel, and hoofdstuk 21's instruction is
/// explicit: the picker is the visual reference the later panels adopt, not a
/// look they approximate. Two more copies of a top-lit gradient and a
/// focus-ringed capsule would have drifted within the phase — the second one
/// always gets a slightly different sheen — so the originals moved here
/// verbatim and the picker now imports them.
///
/// Nothing about the picker's appearance changes: this is a move, and
/// `test/goldens/tv_media_source_picker_golden_test.dart` is what says so.
library;

import 'package:flutter/material.dart';

import '../../focus/focusable_wrapper.dart';
import '../../focus/dpad_navigator.dart';
import '../../theme/mono_shapes.dart';
import '../../theme/mono_tokens.dart';
import 'tv_unified_layout.dart';

/// The panel surface: a hairline, the corner radius the host clips to, and a
/// top-lit wash.
///
/// The wash is not decoration. A 10-foot modal has to read as standing *in
/// front of* the page, and the host's cast shadow only says that at the edges;
/// with the panel flat and the rows lit, the rows read as stickers on a
/// rectangle. Lighting both from the same direction is what makes the whole
/// thing read as one object.
BoxDecoration tvPanelDecoration(MonoTokens mono, double radius) => BoxDecoration(
  border: Border.all(color: mono.outline, width: 1),
  borderRadius: BorderRadius.circular(radius),
  gradient: LinearGradient(
    begin: Alignment.topCenter,
    end: Alignment.bottomCenter,
    colors: [
      Color.alphaBlend(mono.text.withValues(alpha: TvSourcePickerLayout.panelSheen), mono.surface),
      mono.surface,
    ],
  ),
);

/// A panel button in Pleya's CTA language: [MonoShapes.cta]'s capsule, the
/// detail screen's tonal idle fill, and the same focused treatment the action
/// bar uses — the surface inverts and the white focus ring follows the shape
/// rather than boxing it.
///
/// The primary variant is white on dark. Hoofdstuk 34 pins that ("de primaire
/// Play-CTA is wit"), and 33.6 #2 records that the mockup's red button loses.
///
/// **The ring is held off the capsule by [TvSourcePickerLayout.buttonFocusRingGap].**
/// `FocusableWrapper` paints the ring on its child's bounds, so a white ring
/// around an already-white capsule merged into it and the primary action had no
/// visible focus state at all — the source picker's first render is exactly
/// that. Padding the capsule inside the wrapper puts a band of panel surface
/// between the two, which is the only way to keep both of hoofdstuk 34's pins
/// (white CTA, white ring) and still be able to tell them apart.
///
/// A secondary button carries no fill, only a hairline. That is what keeps a
/// standing-setting action quieter than the choices it sits under.
class TvPanelButton extends StatefulWidget {
  const TvPanelButton({
    super.key,
    required this.scale,
    required this.label,
    required this.onPressed,
    required this.primary,
    this.icon,
    this.focusNode,
    this.autofocus = false,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
  });

  final double scale;
  final String label;
  final VoidCallback onPressed;
  final bool primary;
  final IconData? icon;
  final FocusNode? focusNode;
  final bool autofocus;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateUp;

  @override
  State<TvPanelButton> createState() => _TvPanelButtonState();
}

class _TvPanelButtonState extends State<TvPanelButton> {
  bool _isFocused = false;

  @override
  Widget build(BuildContext context) {
    final scale = widget.scale;
    final mono = tokens(context);
    final colors = Theme.of(context).colorScheme;
    final filled = widget.primary || _isFocused;

    return FocusableWrapper(
      focusNode: widget.focusNode,
      autofocus: widget.autofocus,
      focusShapeBorder: MonoShapes.cta,
      // Scale stays on here, unlike on a row. A primary button is already
      // white, so a white ring on it has almost nothing to contrast against;
      // the lift is what makes "this is where I am" survive on the one control
      // whose fill cannot change. Buttons are small and sit in their own row,
      // so nothing is pushed around.
      semanticLabel: widget.label,
      onFocusChange: (focused) => setState(() => _isFocused = focused),
      onNavigateLeft: widget.onNavigateLeft,
      onNavigateRight: widget.onNavigateRight,
      onNavigateUp: widget.onNavigateUp,
      onSelect: () {
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        widget.onPressed();
      },
      child: Padding(
        padding: EdgeInsets.all(TvSourcePickerLayout.buttonFocusRingGap * scale),
        child: AnimatedContainer(
          duration: mono.fast,
          padding: EdgeInsets.symmetric(horizontal: 26 * scale, vertical: 11 * scale),
          decoration: ShapeDecoration(
            shape: MonoShapes.cta.copyWith(side: filled ? BorderSide.none : BorderSide(color: mono.outline, width: 1)),
            // Unfilled is, by the line above, always "secondary and not
            // focused". No tonal wash there: an outline-only capsule is what
            // keeps a footer from competing with the rows above it, and it is
            // the state both footer buttons are in while the user is still
            // reading the list.
            color: filled ? colors.inverseSurface : Colors.transparent,
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (widget.icon != null) ...[
                Icon(
                  widget.icon,
                  size: TvSourcePickerLayout.buttonFontSize * scale,
                  color: filled ? colors.onInverseSurface : mono.accentAlt,
                ),
                SizedBox(width: 8 * scale),
              ],
              Flexible(
                child: Text(
                  widget.label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: filled ? colors.onInverseSurface : mono.text,
                    fontSize: TvSourcePickerLayout.buttonFontSize * scale,
                    fontWeight: FontWeight.w700,
                    letterSpacing: 0.1,
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
