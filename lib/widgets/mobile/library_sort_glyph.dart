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
      ..strokeWidth = size.width * 0.09
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round
      ..style = PaintingStyle.stroke;

    // Ascending runs from the short line to the long one, whichever way the
    // arrow points. The arrow alone says which direction the list reads.
    const lengths = [0.25, 0.4, 0.55];
    const ys = [0.25, 0.5, 0.75];
    for (var i = 0; i < lengths.length; i++) {
      final y = size.height * ys[i];
      canvas.drawLine(Offset(size.width * 0.06, y), Offset(size.width * (0.06 + lengths[i]), y), paint);
    }

    final x = size.width * 0.8;
    final top = size.height * 0.12;
    final bottom = size.height * 0.88;
    final head = descending ? bottom : top;
    final tail = descending ? top : bottom;
    final wing = size.width * 0.16;
    final wingY = descending ? head - wing : head + wing;
    canvas.drawPath(
      Path()
        ..moveTo(x, tail)
        ..lineTo(x, head)
        ..moveTo(x - wing, wingY)
        ..lineTo(x, head)
        ..lineTo(x + wing, wingY),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _SortGlyphPainter oldDelegate) =>
      descending != oldDelegate.descending || color != oldDelegate.color;
}
