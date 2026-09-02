import 'package:flutter/material.dart';
import '../services/device_performance.dart';
import '../theme/mono_tokens.dart';

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

  /// J10: whether this surface needs [contrastSeparatorShadows] alongside the
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

  /// The dark separator itself — a tight, low-blur shadow hugging the ring's
  /// own edge, in [MonoTokens.text] (the theme's own ink color, already
  /// near-black on the light palette; never a new brand color). Two shadows
  /// at increasing radius read as one crisp dark line rather than a soft
  /// halo, which is what actually separates a white ring from a white card —
  /// a soft glow would just look like white bleeding into white.
  static List<BoxShadow> contrastSeparatorShadows(BuildContext context) {
    final ink = Theme.of(context).extension<MonoTokens>()?.text ?? Colors.black;
    return [
      BoxShadow(color: ink.withValues(alpha: 0.55), blurRadius: 0, spreadRadius: 0.5),
      BoxShadow(color: ink.withValues(alpha: 0.28), blurRadius: 1.5, spreadRadius: 0),
    ];
  }

  static Duration getAnimationDuration(BuildContext context) {
    // Reduced tier: snap focus transitions (scale/border/glow) instead of
    // animating — each animation frame re-rasterizes the focused card.
    if (DevicePerformance.isReduced) return Duration.zero;
    return Theme.of(context).extension<MonoTokens>()?.fast ?? const Duration(milliseconds: 150);
  }

  static BoxDecoration focusDecoration(
    BuildContext context, {
    required bool isFocused,
    double borderRadius = defaultBorderRadius,
    double borderStrokeAlign = BorderSide.strokeAlignInside,
    Color? color,
    BoxShape shape = BoxShape.rectangle,
  }) {
    final focusColor = color ?? getFocusBorderColor(context);
    final separator = isFocused && needsContrastSeparator(context);

    return BoxDecoration(
      shape: shape,
      // Flutter asserts when a circle carries a borderRadius, so the radius is
      // meaningful for rectangles only. Circular children (round icon buttons,
      // avatars) would otherwise get a 6px-rounded *square* ring around them.
      borderRadius: shape == BoxShape.circle ? null : BorderRadius.circular(borderRadius),
      border: Border.all(
        color: isFocused ? focusColor : Colors.transparent,
        width: focusBorderWidth,
        strokeAlign: borderStrokeAlign,
      ),
      // J10: a dark separator alongside the white ring, only where the
      // surface itself needs it — see [needsContrastSeparator].
      boxShadow: separator ? contrastSeparatorShadows(context) : null,
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
  }) {
    final focusColor = color ?? getFocusBorderColor(context);
    final separator = isFocused && needsContrastSeparator(context);
    return ShapeDecoration(
      shape: shape.copyWith(
        side: BorderSide(
          color: isFocused ? focusColor : Colors.transparent,
          width: focusBorderWidth,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
      ),
      // J10: see [focusDecoration]'s own note on the same shadows.
      shadows: separator ? contrastSeparatorShadows(context) : null,
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
