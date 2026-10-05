import 'dart:math' as math;

import 'package:flutter/widgets.dart';

/// Big P's speech balloon (mockup 39, `.ball` and `tail()` in `bp39.js`): the
/// dark panel with a thin light rim and a tail, a turned square, pointing at
/// Big P on the [tail] side, [tailAt] of the way along that edge, or
/// [tailFromEnd] points before its end when he stands at a fixed height
/// beside a balloon that grows. [scale]
/// grows the corners, tail and shadow together (39 J draws it at 1.5x, times
/// the TV point scale); 1 is the iOS size.
class BigPBalloon extends StatelessWidget {
  const BigPBalloon({
    super.key,
    required this.child,
    this.tail = AxisDirection.down,
    this.tailAt = 0.8,
    this.tailFromEnd,
    this.padding = const EdgeInsets.fromLTRB(16, 18, 16, 16),
    this.scale = 1,
  });

  final Widget child;
  final AxisDirection tail;
  final double tailAt;
  final double? tailFromEnd;
  final EdgeInsets padding;
  final double scale;

  static const fill = Color(0xF71F2323);
  static const rim = Color(0x24FFFFFF);
  static const radius = 28.0;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _BalloonPainter(tail, tailAt, tailFromEnd, scale),
      child: Padding(padding: padding, child: child),
    );
  }
}

class _BalloonPainter extends CustomPainter {
  const _BalloonPainter(this.tail, this.tailAt, this.tailFromEnd, this.scale);

  final AxisDirection tail;
  final double tailAt;
  final double? tailFromEnd;
  final double scale;

  // Half the diagonal of the 22 pt square in bp39.css.
  static const _r22 = 22 / math.sqrt2;

  @override
  void paint(Canvas canvas, Size size) {
    final s = scale, r = _r22 * s, e = 2 * s;
    final body = RRect.fromRectAndRadius(Offset.zero & size, Radius.circular(BigPBalloon.radius * s));
    canvas.drawRRect(
      body.shift(Offset(0, 30 * s)),
      Paint()
        ..color = const Color(0x99000000)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, 35 * s),
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
    double along(double edge) => tailFromEnd == null ? edge * tailAt : edge - tailFromEnd!;
    final c = switch (tail) {
      AxisDirection.down => Offset(along(size.width), size.height - e),
      AxisDirection.up => Offset(along(size.width), e),
      AxisDirection.left => Offset(e, along(size.height)),
      AxisDirection.right => Offset(size.width - e, along(size.height)),
    };
    final top = c.translate(0, -r), right = c.translate(r, 0);
    final bottom = c.translate(0, r), left = c.translate(-r, 0);
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
  bool shouldRepaint(_BalloonPainter old) =>
      old.tail != tail || old.tailAt != tailAt || old.tailFromEnd != tailFromEnd || old.scale != scale;
}
