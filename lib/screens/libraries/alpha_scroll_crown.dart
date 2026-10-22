import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The machined gear of the phone alphabet scrubber (CN09 prototype): a short
/// cylinder at the screen edge with [toothCount] teeth around it and a red
/// band through the middle.
///
/// A tooth at angle theta projects to `y = (sin(theta) + 1) * (h - 3) / 2`;
/// only teeth with `cos(theta) > 0` face the viewer, and they get thinner and
/// fainter as they turn away. The parent drives [phase] from the drag
/// distance, which makes the teeth travel with the finger.
class AlphaScrollCrownPainter extends CustomPainter {
  final double phase;

  static const int toothCount = 48;

  /// Angle between two teeth. The scrubber turns the gear by one tooth per
  /// ratchet step, so what you see and what you feel stay in step.
  static const double toothAngle = 2 * math.pi / toothCount;

  const AlphaScrollCrownPainter({required this.phase});

  static const _facets = [
    Color(0xFF16181B),
    Color(0xFF71716E),
    Color(0xFFD5D3CC),
    Color(0xFFA4A49F),
    Color(0xFF555957),
    Color(0xFFB5B5AE),
    Color(0xFF787B76),
    Color(0xFF3C403E),
    Color(0xFF202426),
  ];
  static const _facetStops = [0.0, 0.08, 0.16, 0.24, 0.31, 0.43, 0.64, 0.83, 1.0];

  static const _tooth = [
    Color(0xFF353A3B),
    Color(0xFFF5F0DE),
    Color(0xFF181D21),
    Color(0xFFA2A8A0),
    Color(0xFFE5E4D9),
    Color(0xFF3E4947),
    Color(0xFF0C1217),
  ];
  static const _toothStops = [0.0, 0.17, 0.22, 0.40, 0.52, 0.86, 1.0];

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, const Radius.circular(5));

    canvas.drawRRect(
      shape.shift(const Offset(-2, 1)),
      Paint()
        ..color = const Color(0x66000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 1.5),
    );

    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      rect,
      Paint()..shader = const LinearGradient(colors: _facets, stops: _facetStops).createShader(rect),
    );

    for (var i = 0; i < toothCount; i++) {
      final theta = i * toothAngle + phase;
      final front = math.cos(theta);
      if (front <= 0) continue;
      final opacity = 0.15 + front * 0.7;
      final y = (math.sin(theta) + 1) * (size.height - 3) / 2;
      final h = math.max(0.25, front);
      final toothRect = Rect.fromLTWH(0, y, size.width, h);
      canvas.drawRect(
        Rect.fromLTWH(0, y + h, size.width, 1),
        Paint()..color = const Color(0xFF080B0E).withValues(alpha: 0.75 * opacity),
      );
      canvas.drawRect(
        toothRect,
        Paint()
          ..shader = LinearGradient(
            colors: [for (final c in _tooth) c.withValues(alpha: opacity)],
            stops: _toothStops,
          ).createShader(toothRect),
      );
    }

    canvas.drawRect(
      rect,
      Paint()
        ..shader = const LinearGradient(
          colors: [
            Color(0x44080B0E),
            Color(0x00000000),
            Color(0x18FFFFED),
            Color(0x00000000),
            Color(0x22000000),
            Color(0x99080B0E),
          ],
          stops: [0.0, 0.16, 0.22, 0.30, 0.78, 1.0],
        ).createShader(rect),
    );

    // Red band through the middle, a dark edge above and a light one below.
    final bandTop = size.height / 2 - 1;
    canvas.drawRect(Rect.fromLTWH(0, bandTop - 1, size.width, 1), Paint()..color = const Color(0xFF191C1D));
    final band = Rect.fromLTWH(0, bandTop, size.width, 2);
    canvas.drawRect(
      band,
      Paint()
        ..shader = const LinearGradient(
          colors: [Color(0xFF611B24), Color(0xFFF15B64), Color(0xFFAE2937), Color(0xFF3E131B)],
          stops: [0.0, 0.25, 0.65, 1.0],
        ).createShader(band),
    );
    canvas.drawRect(Rect.fromLTWH(0, bandTop + 2, size.width, 1), Paint()..color = const Color(0x44B8B0A1));

    canvas.drawRect(Rect.fromLTWH(0, 0, size.width, 1), Paint()..color = const Color(0xFFE3DFD3));
    canvas.drawRect(Rect.fromLTWH(0, size.height - 1, size.width, 1), Paint()..color = const Color(0xFF6C706B));
    canvas.restore();

    // Edge highlight on the inner side.
    canvas.drawRect(Rect.fromLTWH(-1, 2, 1, size.height - 4), Paint()..color = const Color(0x66B0B0A6));
  }

  @override
  bool shouldRepaint(AlphaScrollCrownPainter oldDelegate) => oldDelegate.phase != phase;
}
