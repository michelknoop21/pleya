import 'package:flutter/material.dart';
import '../services/device_performance.dart';
import '../theme/mono_tokens.dart';
import 'focus_ring_border.dart';

export 'focus_ring_border.dart';

class FocusTheme {
  FocusTheme._();

  static const double focusScale = 1.05;
  static const double fullCardFocusScale = 1.06;
  static const double focusBorderWidth = 2.5;
  static const double defaultBorderRadius = 6.0;
  static const double focusGlowInnerBlurRadius = 18;
  static const double focusGlowOuterBlurRadius = 34;
  static const double focusGlowSpreadRadius = 1.5;

  /// Netflix-TV focus ring is always crisp white, independent of the theme's
  /// (near-white) primary — pinned so it never drifts on palette changes.
  static Color getFocusBorderColor(BuildContext context) {
    return Colors.white;
  }

  /// J10: whether this surface needs the [contrastSeparatorColor] line alongside the
  /// white ring.
  ///
  /// Hoofdstuk 8's binding rule is that white stays the one TV focus
  /// identity everywhere — a bare `MonoTheme` maps `surface` to pure white on
  /// the light palette (`mono_theme.dart`), so a white ring painted there has
  /// almost no contrast against the card underneath it, and none at all
  /// against an already-white pill. The fix is not a second focus color: it
  /// is a dark separator that runs *alongside* the ring, so the ring itself
  /// never has to stop being white to stay visible.
  static bool needsContrastSeparator(BuildContext context) =>
      Theme.of(context).extension<MonoTokens>()?.isLight ?? false;

  /// The dark separator line itself: [MonoTokens.text] (the theme's own ink,
  /// near-black on the light palette; never a new brand color) at 55%, one
  /// [contrastSeparatorWidth] wide, drawn directly outside the white ring.
  ///
  /// VIS-0925-A: this used to be a pair of [BoxShadow]s. A BoxShadow is not a
  /// line: `BoxDecoration` paints it as a filled box under the whole
  /// decoration, so on a tile with a 13% fill the 55% ink shone through the
  /// fill and a focused tile in Light turned ~#555 with dark text on it
  /// (hardware photos of build 303). A stroke only covers its own band.
  static Color contrastSeparatorColor(BuildContext context) {
    final ink = Theme.of(context).extension<MonoTokens>()?.text ?? Colors.black;
    return ink.withValues(alpha: 0.55);
  }

  static const double contrastSeparatorWidth = 1;

  /// [ring] on [shape] plus the separator line hugging its outer edge. The
  /// separator is always present, transparent when not needed, so a focus
  /// animation lerps between two borders of the same structure.
  static FocusRingBorder _ringWithSeparator(
    BuildContext context,
    OutlinedBorder shape,
    BorderSide ring,
    bool separator,
  ) {
    return FocusRingBorder(
      shape: shape.copyWith(side: BorderSide.none),
      ring: ring,
      separator: BorderSide(
        color: separator ? contrastSeparatorColor(context) : Colors.transparent,
        width: contrastSeparatorWidth,
      ),
    );
  }

  /// Radius for a ring-mode [FocusableWrapper] around a child of
  /// [innerRadius] that sits [gap] inside the ring. The inside-aligned ring
  /// reserves its own width as padding, so the child is inset by both; a ring
  /// with the child's own radius has corners that do not follow it.
  static double ringRadiusAround(double innerRadius, {double gap = 0}) => innerRadius + gap + focusBorderWidth;

  static Duration getAnimationDuration(BuildContext context) {
    // Reduced tier: snap focus transitions (scale/border/glow) instead of
    // animating — each animation frame re-rasterizes the focused card.
    if (DevicePerformance.isReduced) return Duration.zero;
    return Theme.of(context).extension<MonoTokens>()?.fast ?? const Duration(milliseconds: 150);
  }

  /// The white focus ring for a box of [borderRadius] (or a circle), plus the
  /// Light separator from [contrastSeparatorColor]. Pass the radius of the
  /// shape the ring actually surrounds: a ring of 6 around a pill of 12 has
  /// corners that do not follow the pill (VIS-0925-A).
  static ShapeDecoration focusDecoration(
    BuildContext context, {
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
    double borderStrokeAlign = BorderSide.strokeAlignInside,
    Color? color,
    BoxShape shape = BoxShape.rectangle,
  }) {
    final focusColor = color ?? getFocusBorderColor(context);
    final OutlinedBorder outline = shape == BoxShape.circle
        ? const CircleBorder()
        : RoundedRectangleBorder(borderRadius: BorderRadius.circular(borderRadius));
    return ShapeDecoration(
      shape: _ringWithSeparator(
        context,
        outline,
        BorderSide(
          color: isFocused ? focusColor : Colors.transparent,
          width: focusBorderWidth,
          strokeAlign: borderStrokeAlign,
        ),
        isFocused && needsContrastSeparator(context),
      ),
    );
  }

  /// The focus glow as a list of [BoxShadow]s.
  ///
  /// Rendered by [FocusGlowOverlay] in the root overlay so the glow paints
  /// above sibling cards on all four sides (an in-tree background shadow is
  /// occluded by later-painted neighbours, which produced the one-sided halo).
  static List<BoxShadow> focusGlowShadows(Color color) {
    return [
      BoxShadow(
        color: color.withValues(alpha: 0.34),
        blurRadius: focusGlowInnerBlurRadius,
        spreadRadius: focusGlowSpreadRadius,
      ),
      BoxShadow(color: color.withValues(alpha: 0.2), blurRadius: focusGlowOuterBlurRadius),
    ];
  }

  /// How far the focus glow visibly reaches beyond the card edge. Used to size
  /// the overlay paint area so the blur is not clipped.
  static double get focusGlowExtent => focusGlowOuterBlurRadius * 2 + focusGlowSpreadRadius;

  /// Build focus decoration with background color instead of border.
  /// Useful for video controls where it should match the native hover style.
  static BoxDecoration focusBackgroundDecoration({
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
    BoxShape shape = BoxShape.rectangle,
  }) {
    return BoxDecoration(
      shape: shape,
      borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
      color: isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
    );
  }

  /// Shape-aware focus ring: the ring is the button's own [shape], carrying a
  /// [BorderSide] instead of a reconstructed geometry. Meant for
  /// [FocusableWrapper.focusShapeBorder] — painted in `foregroundDecoration`
  /// so it isn't occluded by an opaque Material child.
  static ShapeDecoration shapeFocusRing(
    BuildContext context, {
    required bool isFocused,
    required OutlinedBorder shape,
    Color? color,
    double gap = 0,
  }) {
    final focusColor = color ?? getFocusBorderColor(context);
    return ShapeDecoration(
      shape: _ringWithSeparator(
        context,
        shape,
        BorderSide(
          color: isFocused ? focusColor : Colors.transparent,
          width: focusBorderWidth,
          // [gap] of clear space between the shape and the ring: a white ring
          // directly on a white fill is no ring at all (VIS-0925 review D1).
          strokeAlign: BorderSide.strokeAlignOutside + 2 * gap / focusBorderWidth,
        ),
        isFocused && needsContrastSeparator(context),
      ),
    );
  }

  /// Shape-aware focus fill: the native hover-style background tint, clipped
  /// to [shape]. Carries [BorderSide.none] so it contributes no padding.
  static ShapeDecoration shapeFocusFill({required bool isFocused, required OutlinedBorder shape}) {
    return ShapeDecoration(
      shape: shape.copyWith(side: BorderSide.none),
      color: isFocused ? Colors.white.withValues(alpha: 0.2) : Colors.transparent,
    );
  }
}
