import 'dart:math' as math;

import 'package:characters/characters.dart';
import 'package:flutter/material.dart';

import '../../../books/book.dart';

/// Draws a cover from a [BookArtwork].
///
/// A stand-in until books carry cover images, and drawn rather than shipped as
/// assets for the same reason golden 01b is: a commercial cover has no place
/// in this repository. The shapes are the ones golden 01b uses, so the
/// simulator screenshot and the approved golden can be compared directly.
class BookCover extends StatelessWidget {
  const BookCover({super.key, required this.artwork, required this.title, this.author, this.borderRadius = 8});

  final BookArtwork artwork;
  final String title;
  final String? author;
  final double borderRadius;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(borderRadius),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // Type scales with the cover so a 58 pt inset and a 110 pt shelf
          // cover read as the same design rather than as two.
          final width = constraints.hasBoundedWidth ? constraints.maxWidth : 110.0;
          final scale = width / 110.0;
          return CustomPaint(
            painter: _BookCoverPainter(artwork),
            child: _CoverType(artwork: artwork, title: title, author: author, scale: scale),
          );
        },
      ),
    );
  }
}

class _CoverType extends StatelessWidget {
  const _CoverType({required this.artwork, required this.title, required this.author, required this.scale});

  final BookArtwork artwork;
  final String title;
  final String? author;
  final double scale;

  @override
  Widget build(BuildContext context) {
    // Where the title sits depends on the motif: over an orb it goes low, on a
    // plain or diagonal ground it goes high, because that is where the ground
    // is empty in each case.
    final titleAtTop = artwork.shape == BookArtworkShape.plain || artwork.shape == BookArtworkShape.diagonal;
    // Size follows the title's length, not its motif. Fixing it per shape put
    // 26 pt under `1984` and the same 26 pt under `Brave New World`, which then
    // broke mid-word into `Brave / New / World` across the artwork. Letter
    // spacing goes the same way: it is what makes a short title look printed
    // and a long one overflow.
    final glyphs = title.characters.length;
    final base = glyphs <= 6
        ? 24.0
        : glyphs <= 12
        ? 16.0
        : glyphs <= 15
        ? 12.0
        : glyphs <= 22
        ? 11.0
        : 10.0;
    final weight = artwork.shape == BookArtworkShape.rings ? FontWeight.w500 : FontWeight.w700;
    final spacing = artwork.shape == BookArtworkShape.orb && glyphs <= 12 ? 2.4 : 0.6;
    final drawn = artwork.shape == BookArtworkShape.orb ? title.toUpperCase() : title;
    // And then stepped down until the longest word fits one line.
    //
    // The table above answers how many **lines** a title needs; it cannot
    // answer whether a word fits one of them, and those are different
    // questions. `De Alchemist` is twelve glyphs, so it draws at 16 pt with the
    // wide letter-spacing an orb title gets, and `ALCHEMIST` is then wider than
    // the measure: it broke as `DE ALCH / EMIST` on the shelf. That is the same
    // mid-word break golden 02 rejected once for `CHILDRE / N OF / DUNE`, on a
    // title short enough that the length rule never reached it.
    //
    // Measured rather than tabled, and measured with the reader's own text
    // scaler, because that is the one thing a second table could not follow:
    // at iOS Larger Text the title grows and the measure does not.
    //
    // The measured style and the drawn style are one object, and it names its
    // own face. A `TextStyle` handed straight to a `TextPainter` carries no
    // family and falls back to the platform default, while the `Text` below
    // resolves whatever the surrounding `DefaultTextStyle` has: two faces, two
    // widths, and a fit computed for neither. Measured that way `DUNE` came out
    // 105 wide instead of Inter's 77, and a title with room to spare was shrunk.
    final metrics = TextStyle(
      fontFamily: DefaultTextStyle.of(context).style.fontFamily,
      fontSize: base,
      fontWeight: weight,
      letterSpacing: spacing,
    );
    final fit = _fitFactor(drawn, style: metrics, scaler: MediaQuery.textScalerOf(context));
    final titleStyle = metrics.copyWith(
      color: artwork.ink,
      fontSize: base * fit * scale,
      height: 1.15,
      letterSpacing: spacing * fit * scale,
    );
    final authorStyle = TextStyle(
      color: artwork.ink.withValues(alpha: 0.72),
      fontSize: 7 * scale,
      letterSpacing: 1.6 * scale,
      fontWeight: FontWeight.w600,
    );

    final titleText = Text(
      drawn,
      textAlign: TextAlign.center,
      maxLines: 3,
      overflow: TextOverflow.ellipsis,
      style: titleStyle,
    );

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: 8 * scale, vertical: 10 * scale),
      child: Column(
        mainAxisAlignment: titleAtTop ? MainAxisAlignment.start : MainAxisAlignment.end,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (titleAtTop) ...[
            titleText,
            const Spacer(),
            if (author case final name?)
              Text(name.toUpperCase(), textAlign: TextAlign.center, maxLines: 1, style: authorStyle),
          ] else ...[
            titleText,
            SizedBox(height: 4 * scale),
          ],
        ],
      ),
    );
  }
}

/// What the reference cover leaves for its lettering: 110 points less the 8 of
/// padding on each side. Everything on a cover is expressed against that 110
/// and multiplied by `scale`, so a factor found here holds at every cover size.
const double _titleMeasure = 110 - 16;

/// How far [text]'s longest word has to shrink to fit one line, as a factor of
/// 1.0 or less.
///
/// The **longest word** and not the whole string: a line break between words is
/// what `maxLines: 3` is for, and only a word that outruns the measure on its
/// own has nowhere to break. Letter-spacing is scaled with the size because it
/// is part of a word's set width; scaling both by one factor scales the width by
/// exactly that factor.
double _fitFactor(String text, {required TextStyle style, required TextScaler scaler}) {
  final longest = text.split(RegExp(r'\s+')).fold<String>('', (a, b) => b.length > a.length ? b : a);
  if (longest.isEmpty) return 1;
  final painter = TextPainter(
    text: TextSpan(text: longest, style: style),
    textDirection: TextDirection.ltr,
    textScaler: scaler,
  )..layout();
  final width = painter.width;
  painter.dispose();
  return width <= _titleMeasure ? 1 : _titleMeasure / width;
}

class _BookCoverPainter extends CustomPainter {
  const _BookCoverPainter(this.artwork);

  final BookArtwork artwork;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    // A printed cover is a flat ground with a motif on it, not a gradient
    // poster. The swing here is small on purpose: the first pass used a wide
    // one and the simulator screenshot came back with cream covers reading as
    // a wash from white to beige, which approved golden 01b does not have.
    final ground = LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [_shade(artwork.base, -0.06), artwork.base, _shade(artwork.base, 0.04)],
    );
    canvas.drawRect(rect, Paint()..shader = ground.createShader(rect));

    switch (artwork.shape) {
      case BookArtworkShape.orb:
        final centre = Offset(size.width * 0.5, size.height * 0.3);
        final radius = size.width * 0.28;
        canvas.drawCircle(
          centre,
          radius,
          Paint()
            ..shader = RadialGradient(
              colors: [_shade(artwork.accent, 0.35), artwork.accent, _shade(artwork.accent, -0.45)],
            ).createShader(Rect.fromCircle(center: centre, radius: radius)),
        );
      case BookArtworkShape.rings:
        final centre = Offset(size.width * 0.5, size.height * 0.32);
        final paint = Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = math.max(0.8, size.width * 0.008)
          ..color = artwork.accent.withValues(alpha: 0.8);
        for (var i = 1; i <= 6; i++) {
          canvas.drawCircle(centre, size.width * 0.035 * i, paint);
        }
      case BookArtworkShape.eye:
        final centre = Offset(size.width * 0.5, size.height * 0.34);
        final r = size.width * 0.3;
        canvas.drawCircle(centre, r, Paint()..color = artwork.accent);
        canvas.drawCircle(centre, r * 0.66, Paint()..color = artwork.base);
        canvas.drawCircle(
          centre,
          r * 0.46,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = r * 0.16
            ..color = artwork.ink,
        );
      case BookArtworkShape.diagonal:
        final path = Path()
          ..moveTo(0, 0)
          ..lineTo(size.width, 0)
          ..lineTo(size.width, size.height * 0.46)
          ..lineTo(0, size.height * 0.66)
          ..close();
        canvas.drawPath(path, Paint()..color = artwork.accent);
      case BookArtworkShape.plain:
        canvas.drawCircle(
          Offset(size.width * 0.5, size.height * 0.62),
          size.width * 0.055,
          Paint()..color = artwork.accent,
        );
    }
  }

  /// Lighten (positive) or darken (negative) without leaving the hue.
  static Color _shade(Color color, double amount) {
    final hsl = HSLColor.fromColor(color);
    return hsl.withLightness((hsl.lightness + amount).clamp(0.0, 1.0)).toColor();
  }

  @override
  bool shouldRepaint(_BookCoverPainter oldDelegate) => oldDelegate.artwork != artwork;
}
