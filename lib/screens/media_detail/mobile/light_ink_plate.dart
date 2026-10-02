import 'package:flutter/material.dart';

/// Alpha of the page-coloured backing under dark ink on the light theme, the
/// same as the back/Meer circles (`GlassCircleButton`).
const double kLightInkPlateAlpha = 0.92;

/// Light theme only: a rounded, near-opaque `surface` plate behind dark ink
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
    return DecoratedBox(
      decoration: BoxDecoration(
        color: theme.colorScheme.surface.withValues(alpha: kLightInkPlateAlpha),
        borderRadius: BorderRadius.circular(radius),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
