import 'dart:ui' as ui;

import 'package:flutter/widgets.dart';

/// Black at 72%: white70 over a pure-white frame needs 68% for 4.5:1.
const kTvTitleScrimColor = Color(0xB8000000);

/// The TV player's scrim behind the title block (PLR-SCRIM1): flat
/// [kTvTitleScrimColor] from the top edge to the bottom of [child], then a
/// fade to transparent over [fade] below it. One gradient in one rect, so no
/// seam shows where the flat part meets the fade on a fractional pixel row.
class TvTitleScrim extends StatelessWidget {
  final double fade;
  final Widget child;

  const TvTitleScrim({super.key, required this.fade, required this.child});

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _TvTitleScrimPainter(fade),
      child: Padding(
        padding: EdgeInsets.only(bottom: fade),
        child: child,
      ),
    );
  }
}

class _TvTitleScrimPainter extends CustomPainter {
  final double fade;

  const _TvTitleScrimPainter(this.fade);

  @override
  void paint(Canvas canvas, Size size) {
    final fadeStart = size.height - fade;
    final paint = Paint()
      ..shader = ui.Gradient.linear(Offset(0, fadeStart), Offset(0, size.height), const [
        kTvTitleScrimColor,
        Color(0x00000000),
      ]);
    canvas.drawRect(Offset.zero & size, paint);
  }

  @override
  bool shouldRepaint(_TvTitleScrimPainter oldDelegate) => oldDelegate.fade != fade;
}
