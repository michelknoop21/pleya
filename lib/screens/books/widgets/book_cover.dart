import 'dart:math' as math;

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
    final titleStyle = TextStyle(
      color: artwork.ink,
      fontSize: (artwork.shape == BookArtworkShape.eye ? 26 : 15) * scale,
      height: 1.15,
      fontWeight: artwork.shape == BookArtworkShape.rings ? FontWeight.w500 : FontWeight.w700,
      letterSpacing: artwork.shape == BookArtworkShape.orb ? 2.4 * scale : 0,
    );
    final authorStyle = TextStyle(
      color: artwork.ink.withValues(alpha: 0.72),
      fontSize: 7 * scale,
      letterSpacing: 1.6 * scale,
      fontWeight: FontWeight.w600,
    );

    final titleText = Text(
      artwork.shape == BookArtworkShape.orb ? title.toUpperCase() : title,
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
