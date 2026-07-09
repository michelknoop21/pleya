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

  const Pressable({super.key, required this.child, this.onTap, this.pressedScale = 0.97, this.haptic = true});

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
