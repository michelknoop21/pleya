import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The ribbed roller of the phone alphabet scrubber, drawn like the side
/// crown of a watch: a short cylinder whose axis points into the screen edge.
///
/// [rotation] is the roller's angle in radians. The ribs sit at fixed angles
/// around the cylinder, so a rib facing the viewer is drawn full strength and
/// one turning away gets thinner and fainter as it nears the top or bottom.
/// The parent drives [rotation] from the drag distance, which makes the ribs
/// travel with the finger.
class AlphaScrollCrownPainter extends CustomPainter {
  final double rotation;
  final Brightness brightness;

  /// True while the user holds the roller: a deeper shadow lifts it a little.
  final bool active;

  /// Ribs around the full circumference; about half face the viewer.
  static const int ribCount = 22;

  const AlphaScrollCrownPainter({required this.rotation, required this.brightness, this.active = false});

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final shape = RRect.fromRectAndRadius(rect, Radius.circular(size.width * 0.38));
    final dark = brightness == Brightness.dark;

    canvas.drawShadow(Path()..addRRect(shape), Colors.black, active ? 5 : 2.5, true);

    // Titanium body, lit from slightly above the middle.
    final edge = dark ? const Color(0xFF2E2E31) : const Color(0xFF7C7C82);
    final mid = dark ? const Color(0xFF8D8D93) : const Color(0xFFD6D6DB);
    final shine = dark ? const Color(0xFFD9D9DE) : const Color(0xFFFFFFFF);

    canvas.save();
    canvas.clipRRect(shape);
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [edge, mid, shine, mid, edge],
          stops: const [0.0, 0.22, 0.4, 0.72, 1.0],
        ).createShader(rect),
    );

    // Ribs. A rib at angle theta projects to y = cy + r * sin(theta); only
    // the half with cos(theta) > 0 faces the viewer.
    final radius = size.height / 2;
    final cy = size.height / 2;
    const step = 2 * math.pi / ribCount;
    final groove = Paint()..strokeCap = StrokeCap.round;
    final bevel = Paint()..strokeCap = StrokeCap.round;
    for (var k = 0; k < ribCount; k++) {
      final theta = rotation + k * step;
      final facing = math.cos(theta);
      if (facing <= 0.08) continue;
      final y = cy + radius * math.sin(theta);
      groove
        ..strokeWidth = 0.4 + 1.3 * facing
        ..color = Colors.black.withValues(alpha: (dark ? 0.55 : 0.4) * facing);
      bevel
        ..strokeWidth = 0.4 + 0.6 * facing
        ..color = Colors.white.withValues(alpha: (dark ? 0.22 : 0.5) * facing);
      canvas.drawLine(Offset(2, y), Offset(size.width - 2, y), groove);
      canvas.drawLine(Offset(2, y + 1.1), Offset(size.width - 2, y + 1.1), bevel);
    }

    // Side shading: the free end (left) catches less light and the collar
    // where the roller meets the screen edge (right) sits in shadow.
    canvas.drawRect(
      rect,
      Paint()
        ..shader = LinearGradient(
          colors: [
            Colors.black.withValues(alpha: 0.22),
            Colors.transparent,
            Colors.transparent,
            Colors.black.withValues(alpha: 0.3),
          ],
          stops: const [0.0, 0.3, 0.7, 1.0],
        ).createShader(rect),
    );
    canvas.restore();

    canvas.drawRRect(
      shape,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 0.8
        ..color = dark ? Colors.white.withValues(alpha: 0.18) : Colors.black.withValues(alpha: 0.3),
    );
  }

  @override
  bool shouldRepaint(AlphaScrollCrownPainter oldDelegate) =>
      oldDelegate.rotation != rotation || oldDelegate.brightness != brightness || oldDelegate.active != active;
}
