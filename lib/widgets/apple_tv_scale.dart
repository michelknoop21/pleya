import 'package:flutter/material.dart';

import '../utils/platform_detector.dart';

/// On Apple TV the system hands Flutter a 1920×1080 surface at
/// devicePixelRatio 1.0, the same logical pixel count as a phablet. That's
/// too dense for a 10ft viewing distance, so everything ends up tiny. We
/// shrink the effective logical size and scale the rendered output back up so
/// fonts, icons, and paddings end up visually ~2× larger — roughly matching
/// the UI feel of Android TV (which renders at lower logical DPI).
///
/// Everything the user sees belongs inside this, including overlays. A layer
/// mounted as a sibling renders at 1× against a UI drawn at 1.85×, and reads
/// its size from a 1920×1080 MediaQuery that nothing else uses — which is how
/// the notice cards ended up roughly half the size of the app behind them.
class AppleTvScale extends StatelessWidget {
  final Widget child;
  const AppleTvScale({super.key, required this.child});

  static const double scale = 1.85;

  @override
  Widget build(BuildContext context) {
    if (!PlatformDetector.isAppleTV()) return child;
    return LayoutBuilder(
      builder: (context, constraints) {
        final logicalSize = Size(constraints.maxWidth / scale, constraints.maxHeight / scale);
        final outerQ = MediaQuery.of(context);
        // tvOS reports conservative overscan insets (~60pt top/bottom,
        // ~90pt left/right). Modern TVs don't overscan, so treat them as
        // dead margin and zero them out — the UI can use the full surface.
        return Transform.scale(
          scale: scale,
          alignment: .topLeft,
          transformHitTests: true,
          child: SizedBox(
            width: logicalSize.width,
            height: logicalSize.height,
            child: MediaQuery(
              data: outerQ.copyWith(
                size: logicalSize,
                devicePixelRatio: outerQ.devicePixelRatio * scale,
                padding: .zero,
                viewPadding: .zero,
                viewInsets: .zero,
                systemGestureInsets: .zero,
              ),
              child: child,
            ),
          ),
        );
      },
    );
  }
}
