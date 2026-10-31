/// Three staggered lines beside an arrow: the sort mark of the iPhone library
/// look, on the sort pill and on the chosen row of the sort sheet.
library;

import 'package:flutter/material.dart';

class LibrarySortGlyph extends StatelessWidget {
  const LibrarySortGlyph({super.key, required this.descending, required this.color, required this.size});

  final bool descending;
  final Color color;
  final double size;

  @override
  Widget build(BuildContext context) {
    return SizedBox.square(
      dimension: size,
      child: CustomPaint(
        painter: _SortGlyphPainter(descending: descending, color: color),
      ),
    );
  }
}

class _SortGlyphPainter extends CustomPainter {
  const _SortGlyphPainter({required this.descending, required this.color});

  final bool descending;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..strokeWidth = size.width * 0.06
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Reference 74ace49c: A to Z reads downward, so the arrow points down, with
    // the lines growing towards its head. Descending is the same mark flipped.
    double y(double fraction) => size.height * (descending ? 1 - fraction : fraction);

    const lengths = [0.2, 0.33, 0.47];
    const ys = [0.21, 0.41, 0.61];
    const linesEnd = 0.54;
    for (var i = 0; i < lengths.length; i++) {
      final from = size.width * (linesEnd - lengths[i]);
      canvas.drawLine(Offset(from, y(ys[i])), Offset(size.width * linesEnd, y(ys[i])), paint);
    }

    final x = size.width * 0.8;
    const wing = 0.16;
    canvas.drawPath(
      Path()
        ..moveTo(x, y(0.12))
        ..lineTo(x, y(0.88))
        ..moveTo(x - size.width * wing, y(0.88 - wing))
        ..lineTo(x, y(0.88))
        ..lineTo(x + size.width * wing, y(0.88 - wing)),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SortGlyphPainter oldDelegate) =>
      descending != oldDelegate.descending || color != oldDelegate.color;
}
