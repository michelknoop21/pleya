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
    return ShapeDecoration(
      shape: shape.copyWith(
        side: BorderSide(
          color: isFocused ? focusColor : Colors.transparent,
          width: focusBorderWidth,
          strokeAlign: BorderSide.strokeAlignOutside,
        ),
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
