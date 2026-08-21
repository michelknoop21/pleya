import 'package:flutter/material.dart';

import '../services/device_performance.dart';
import '../theme/mono_tokens.dart';
import '../utils/haptics.dart';

/// Wraps [child] with a subtle press-down scale (and optional haptic tick) for
/// tactile feedback on tap. No-op scale when [DevicePerformance.isReduced] so
/// low-end/TV hardware pays nothing. This is for pointer/touch surfaces; TV
/// focus feedback is handled separately by the focus system.
class Pressable extends StatefulWidget {
  final Widget child;
  final VoidCallback? onTap;
  final double pressedScale;
  final bool haptic;

  /// Hit-test behavior of the underlying [GestureDetector]. The default
  /// matches Flutter's: with a non-null child that is
  /// [HitTestBehavior.deferToChild], so only the child's own opaque area
  /// responds. Pass [HitTestBehavior.opaque] when the tappable area is
  /// deliberately larger than the glyph inside it, or the enlarged box is a
  /// lie — it lays out at 48 and still only hits on the 18px icon.
  final HitTestBehavior behavior;

  const Pressable({
    super.key,
    required this.child,
    this.onTap,
    this.pressedScale = 0.97,
    this.haptic = true,
    this.behavior = HitTestBehavior.deferToChild,
  });

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  void _set(bool v) {
    if (_down != v) setState(() => _down = v);
  }

  @override
  Widget build(BuildContext context) {
    final reduced = DevicePerformance.isReduced;
    final scale = _down && !reduced ? widget.pressedScale : 1.0;
    return GestureDetector(
      behavior: widget.behavior,
      onTapDown: widget.onTap == null ? null : (_) => _set(true),
      onTapCancel: () => _set(false),
      onTapUp: (_) => _set(false),
      onTap: widget.onTap == null
          ? null
          : () {
              if (widget.haptic) Haptics.light();
              widget.onTap!();
            },
      child: AnimatedScale(scale: scale, duration: tokens(context).fast, curve: Curves.easeOut, child: widget.child),
    );
  }
}
