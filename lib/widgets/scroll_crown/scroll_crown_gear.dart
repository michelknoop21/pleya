import 'package:flutter/material.dart';

import 'scroll_crown_painter.dart';

/// The visible gear of the scroll crown: fades and slides in from the edge
/// when [visible], with a focus ring when [focused]. It never takes touches;
/// the rail around it does.
class ScrollCrownGear extends StatelessWidget {
  const ScrollCrownGear({
    super.key,
    required this.phase,
    required this.visible,
    required this.fade,
    this.focused = false,
    this.paintKey,
  });

  final double phase;
  final bool visible;
  final bool focused;
  final Duration fade;

  /// Key on the painted gear, for tests that read its phase.
  final Key? paintKey;

  static const double width = 22;
  static const double height = 96;

  /// Offset from the screen edge: the gear sits partly outside it.
  static const double right = -6;

  @override
  Widget build(BuildContext context) {
    return IgnorePointer(
      child: AnimatedOpacity(
        opacity: visible ? 1 : 0,
        duration: fade,
        child: AnimatedSlide(
          offset: visible ? Offset.zero : const Offset(8 / width, 0),
          duration: fade,
          child: DecoratedBox(
            position: DecorationPosition.foreground,
            decoration: BoxDecoration(
              border: focused ? Border.all(color: const Color(0xFFD9D6D0), width: 2) : null,
              borderRadius: BorderRadius.circular(7),
            ),
            child: Padding(
              padding: const EdgeInsets.all(2),
              child: CustomPaint(
                key: paintKey,
                size: const Size(width, height),
                painter: ScrollCrownPainter(phase: phase),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
