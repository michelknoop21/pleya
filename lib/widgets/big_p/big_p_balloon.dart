import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Big P's speech balloon (mockup 39, `.ball` and `tail()` in `bp39.js`): the
/// dark panel with a thin light rim and a tail, a turned square, pointing at
/// Big P on the [tail] side, [tailAt] of the way along that edge.
class BigPBalloon extends StatelessWidget {
  const BigPBalloon({
    super.key,
    required this.child,
    this.tail = AxisDirection.down,
    this.tailAt = 0.8,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 16),
  });

  final Widget child;
  final AxisDirection tail;
  final double tailAt;
  final EdgeInsets padding;

  static const fill = Color(0xF71F2323);
  static const rim = Color(0x24FFFFFF);
  static const radius = 28.0;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BalloonPainter(tail, tailAt),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BalloonPainter extends CustomPainter {
  const _BalloonPainter(this.tail, this.tailAt);

  final AxisDirection tail;
  final double tailAt;

  // Half the diagonal of the 22 pt square in bp39.css.
  static const _r = 22 / math.sqrt2;

  @override
  void paint(Canvas canvas, Size size) {
    final body = RRect.fromRectAndRadius(Offset.zero & size, const Radius.circular(BigPBalloon.radius));
    canvas.drawRRect(
      body.shift(const Offset(0, 30)),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = const MaskFilter.blur(BlurStyle.normal, 35),
    );
    final fill = Paint()..color = BigPBalloon.fill;
    final rim = Paint()
      ..color = BigPBalloon.rim
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    canvas.drawRRect(body, fill);
    canvas.drawRRect(body.deflate(0.5), rim);

    // The square's centre sits just inside the edge, so its inner half
    // covers the rim there and its outer half is the tail.
    final c = switch (tail) {
      AxisDirection.down => Offset(size.width * tailAt, size.height - 2),
      AxisDirection.up => Offset(size.width * tailAt, 2),
      AxisDirection.left => Offset(2, size.height * tailAt),
      AxisDirection.right => Offset(size.width - 2, size.height * tailAt),
    };
    final top = c.translate(0, -_r), right = c.translate(_r, 0);
    final bottom = c.translate(0, _r), left = c.translate(-_r, 0);
    canvas.drawPath(Path()..addPolygon([top, right, bottom, left], true), fill);
    // Only the two outer sides get the rim.
    final (a, tip, b) = switch (tail) {
      AxisDirection.down => (left, bottom, right),
      AxisDirection.up => (left, top, right),
      AxisDirection.left => (top, left, bottom),
      AxisDirection.right => (top, right, bottom),
    };
    canvas.drawPath(Path()..addPolygon([a, tip, b], false), rim);
  }

  @override
  bool shouldRepaint(_BalloonPainter old) => old.tail != tail || old.tailAt != tailAt;
}
