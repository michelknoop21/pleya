import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// Alpha of the page-coloured glass tint under dark ink on the light theme.
/// Translucent: the artwork shows through the blur, as in `CatalogTopPanel`.
const double kLightInkPlateAlpha = 0.3;

/// Blur radius behind the glass tint, the same as `CatalogTopPanel`.
const double kLightInkPlateSigma = 18;

/// Light theme only: a rounded, translucent blurred `surface` glass plate behind dark ink
/// that sits over the poster or its glow, so the text brings its own contrast
/// whatever the artwork (DEC-140). Dark and OLED get [child] untouched.
class LightInkPlate extends StatelessWidget {
  const LightInkPlate({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
    this.radius = 16,
  });

  final Widget child;
  final EdgeInsets padding;
  final double radius;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    if (theme.brightness == Brightness.dark) return child;
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: BackdropFilter(
        filter: ImageFilter.blur(sigmaX: kLightInkPlateSigma, sigmaY: kLightInkPlateSigma),
        child: DecoratedBox(
          decoration: BoxDecoration(color: theme.colorScheme.surface.withValues(alpha: kLightInkPlateAlpha)),
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}
