import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../../../books/book.dart';

/// The colour field behind the top of the detail page (approved golden 05).
///
/// **Cover-derived ambience, not the cover a second time** — the rule golden
/// 01b set for the Verder-lezen card. Only colour and light come across: no
/// shape of the artwork survives the blur, so a pale, busy or purely
/// typographic cover cannot make the trick fall apart. The cover itself is
/// shown once, sharp, on top of this.
///
/// The scrim lands the field on the page before the stats row, so the lower
/// half of the screen is ordinary page background.
class BookDetailAmbience extends StatelessWidget {
  const BookDetailAmbience({super.key, required this.artwork});

  final BookArtwork artwork;

  /// The field's own box, measured on the golden: it starts 90 pt above the
  /// frame and bleeds 70 pt past both margins, so the blur never shows an edge.
  static const double fieldTop = -90;
  static const double fieldBleed = -70;
  static const double fieldHeight = 660;

  /// CSS `blur(72px)`, which is a Gaussian of half that standard deviation.
  static const double blurSigma = 36;

  @override
  Widget build(BuildContext context) {
    final ground = Theme.of(context).scaffoldBackgroundColor;
    return Stack(
      children: [
        Positioned(
          left: fieldBleed,
          right: fieldBleed,
          top: fieldTop,
          height: fieldHeight,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blurSigma, sigmaY: blurSigma, tileMode: TileMode.decal),
            child: Opacity(opacity: 0.92, child: _Field(artwork: artwork)),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          top: 0,
          height: fieldHeight,
          child: DecoratedBox(
            decoration: BoxDecoration(
              // The golden's own stops. It dips almost clear behind the cover
              // and closes to the page by the time the stats row starts.
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                stops: const [0, 0.24, 0.58, 0.84, 1],
                colors: [
                  ground.withValues(alpha: 0.34),
                  ground.withValues(alpha: 0.06),
                  ground.withValues(alpha: 0.30),
                  ground.withValues(alpha: 0.86),
                  ground,
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Three gradients, in the golden's own placement: a graded ground, a lit
/// upper-left and a warmer lower-right.
class _Field extends StatelessWidget {
  const _Field({required this.artwork});

  final BookArtwork artwork;

  @override
  Widget build(BuildContext context) {
    final base = HSLColor.fromColor(artwork.base);
    final deep = base.withLightness((base.lightness * 0.5).clamp(0.0, 1.0)).toColor();
    final lit = _shade(artwork.accent, -0.09);
    final warm = _shade(artwork.base, 0.14);
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [artwork.base, deep]),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(-0.52, -0.40),
                radius: 0.62,
                colors: [lit, lit.withValues(alpha: 0)],
              ),
            ),
          ),
          DecoratedBox(
            decoration: BoxDecoration(
              gradient: RadialGradient(
                center: const Alignment(0.48, 0.48),
                radius: 0.66,
                colors: [warm, warm.withValues(alpha: 0)],
              ),
            ),
          ),
        ],
      ),
    );
  }

  static Color _shade(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }
}
