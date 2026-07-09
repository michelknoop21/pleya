import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// Navigation glyph that renders a solid mockup SVG (via [SvgTheme.currentColor],
/// same pattern as the tracker logos) when [svgAsset] is set, and otherwise
/// falls back to a Material Symbol. Keeps size/color parity between both paths so
/// nav items look identical whichever glyph they use.
class NavGlyph extends StatelessWidget {
  final String? svgAsset;
  final IconData? icon;
  final double? size;
  final Color? color;

  const NavGlyph({super.key, this.svgAsset, this.icon, this.size, this.color});

  @override
  Widget build(BuildContext context) {
    if (svgAsset != null) {
      final c = color ?? IconTheme.of(context).color ?? Theme.of(context).colorScheme.onSurface;
      return SvgPicture.asset(
        svgAsset!,
        width: size,
        height: size,
        theme: SvgTheme(currentColor: c),
      );
    }
    return AppIcon(icon, fill: 1, size: size, color: color);
  }
}

/// Wrapper around [Icon] that centralizes our Material Symbols defaults.
/// Defaults: fill=1 (filled) and weight=700 (bold). Update [AppIconDefaults]
/// to tweak app-wide icon appearance from one place.
class AppIcon extends StatelessWidget {
  const AppIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.fill,
    this.weight,
    this.grade,
    this.opticalSize,
    this.shadows,
    this.semanticLabel,
    this.textDirection,
  });

  final IconData? icon;
  final double? size;
  final Color? color;
  final double? fill;
  final double? weight;
  final double? grade;
  final double? opticalSize;
  final List<Shadow>? shadows;
  final String? semanticLabel;
  final TextDirection? textDirection;

  @override
  Widget build(BuildContext context) {
    if (icon == null) return const SizedBox.shrink();
    return Icon(
      icon,
      size: size,
      color: color,
      fill: fill ?? AppIconDefaults.fill,
      weight: weight ?? AppIconDefaults.weight,
      grade: grade ?? AppIconDefaults.grade,
      opticalSize: opticalSize ?? AppIconDefaults.opticalSize,
      shadows: shadows ?? AppIconDefaults.shadows,
      semanticLabel: semanticLabel,
      textDirection: textDirection,
    );
  }
}

/// Central place to adjust default Material Symbol variations.
class AppIconDefaults {
  static double fill = 1;
  static double weight = 700;
  static double? grade;
  static double? opticalSize;
  static Color? color;
  static List<Shadow>? shadows;

  static void update({
    double? fill,
    double? weight,
    double? grade,
    double? opticalSize,
    Color? color,
    List<Shadow>? shadows,
  }) {
    if (fill != null) AppIconDefaults.fill = fill;
    if (weight != null) AppIconDefaults.weight = weight;
    if (grade != null) AppIconDefaults.grade = grade;
    if (opticalSize != null) AppIconDefaults.opticalSize = opticalSize;
    if (color != null) AppIconDefaults.color = color;
    if (shadows != null) AppIconDefaults.shadows = shadows;
  }
}
