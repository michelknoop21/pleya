import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';

import 'glass_settings.dart';

/// A single glass plate. Renders [legacy] (or [child] if [legacy] is null)
/// when glass is [GlassTier.off]; real `liquid_glass_renderer` glass inside a
/// [GlassLayer] on [GlassTier.real]; a hand-rolled `BackdropFilter` stack,
/// never a package widget, on [GlassTier.fake].
class GlassSurface extends StatelessWidget {
  const GlassSurface({
    super.key,
    required this.shape,
    required this.child,
    this.tokens,
    this.prominent = false,
    this.legacy,
  });

  final ShapeBorder shape;
  final Widget child;
  final GlassTokens? tokens;
  final bool prominent;
  final Widget? legacy;

  /// Fixed rim width for the fake-tier light edge ([GlassTokens.tv] and
  /// [GlassTokens.control] have a non-zero [GlassTokens.edge]).
  static const double _edgeWidth = 1.5;

  @override
  Widget build(BuildContext context) {
    final tier = glassTierFor(context);
    if (tier == GlassTier.off) return legacy ?? child;

    final t = tokens ?? (prominent ? const GlassTokens.prominent() : const GlassTokens.phone());

    if (tier == GlassTier.real) {
      return LiquidGlass(shape: _asLiquidShape(shape), child: child);
    }

    // The blur and the saturate/dim matrix are composed into one ImageFilter
    // and handed to BackdropFilter itself: the Flutter equivalent of CSS's
    // chained `backdrop-filter: blur() saturate() brightness()`: so they
    // apply to the real backdrop (the poster/scene behind the plate), not to
    // [child]. A ColorFiltered *wrapping* [child] (a literal reading of "> ")
    // would desaturate/dim the plate's own text and icons along with it,
    // which breaks the drop shadow's whole job of keeping them legible; see
    // the task report for this deviation from the brief's widget listing.
    final backdropFilter = ImageFilter.compose(
      outer: ColorFilter.matrix(_saturationDimMatrix(t.saturation, t.dim)),
      inner: ImageFilter.blur(sigmaX: t.blur, sigmaY: t.blur),
    );
    return ClipPath(
      clipper: ShapeBorderClipper(shape: shape),
      child: BackdropFilter(
        filter: backdropFilter,
        child: DecoratedBox(decoration: _fakeGlassDecoration(shape, t), child: child),
      ),
    );
  }
}

/// Groups the plates of one section (tab bar, player controls, action row)
/// under a shared `LiquidGlassLayer`. Off/fake tiers pass [child] through
/// unchanged; each [GlassSurface] inside decides its own rendering.
class GlassLayer extends StatelessWidget {
  const GlassLayer({super.key, required this.child, this.tokens});

  final Widget child;
  final GlassTokens? tokens;

  @override
  Widget build(BuildContext context) {
    if (glassTierFor(context) != GlassTier.real) return child;
    final t = tokens ?? const GlassTokens.phone();
    return LiquidGlassLayer(
      settings: LiquidGlassSettings(
        blur: t.blur,
        glassColor: t.tint,
        saturation: t.saturation,
        thickness: 18,
        refractiveIndex: 1.3,
      ),
      child: child,
    );
  }
}

/// A touch of white blended into [GlassTokens.tint] for the plate's top edge,
/// independent of whether the tint itself is dark (phone/tv, Fixronde 1) or
/// white (prominent). This, plus the rim, is what still reads as glass rather
/// than a flat tinted chip.
const _kTopHighlight = Color(0x1AFFFFFF);

/// Tint fill + top highlight + light rim for the fake-tier plate. Arbitrary
/// [ShapeBorder]s render without a rim (a rim needs an [OutlinedBorder.side]);
/// every shape used by this module today (`StadiumBorder`, rounded rects,
/// circles) is one.
Decoration _fakeGlassDecoration(ShapeBorder shape, GlassTokens t) {
  final highlighted = Color.alphaBlend(_kTopHighlight, t.tint);
  final rimmed = shape is OutlinedBorder && t.edge > 0
      ? shape.copyWith(
          side: BorderSide(color: Color.fromRGBO(255, 255, 255, t.edge), width: GlassSurface._edgeWidth),
        )
      : shape;
  return ShapeDecoration(
    shape: rimmed,
    gradient: LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [highlighted, t.tint, t.tint],
      stops: const [0, 0.45, 1],
    ),
  );
}

/// Standard-luminance (0.213/0.715/0.072) saturation matrix, then its RGB
/// rows are scaled by [dim]: the fake-tier stand-in for `backdrop-filter:
/// saturate() brightness()` (De CSS-recepten in `docs/liquid-glass-mockups-2026-09.md`).
List<double> _saturationDimMatrix(double saturation, double dim) {
  const lumR = 0.213, lumG = 0.715, lumB = 0.072;
  final sr = (1 - saturation) * lumR;
  final sg = (1 - saturation) * lumG;
  final sb = (1 - saturation) * lumB;
  return <double>[
    (sr + saturation) * dim,
    sg * dim,
    sb * dim,
    0,
    0,
    sr * dim,
    (sg + saturation) * dim,
    sb * dim,
    0,
    0,
    sr * dim,
    sg * dim,
    (sb + saturation) * dim,
    0,
    0,
    0,
    0,
    0,
    1,
    0,
  ];
}

/// Maps an arbitrary [ShapeBorder] to a package [LiquidShape] for the real
/// tier. The package has no stadium/capsule shape (checked via Context7,
/// 2026-09-24): a [StadiumBorder] is approximated with a
/// [LiquidRoundedSuperellipse] whose radius is large enough to read as a full
/// capsule once Flutter clamps it to the shape's own bounds.
LiquidShape _asLiquidShape(ShapeBorder shape) {
  if (shape is LiquidShape) return shape;
  if (shape is CircleBorder) return const LiquidOval();
  if (shape is StadiumBorder) return const LiquidRoundedSuperellipse(borderRadius: 9999);
  if (shape is RoundedRectangleBorder) {
    final radius = shape.borderRadius.resolve(TextDirection.ltr).topLeft.x;
    return LiquidRoundedSuperellipse(borderRadius: radius);
  }
  return const LiquidRoundedSuperellipse(borderRadius: 24);
}
