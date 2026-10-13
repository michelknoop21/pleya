import 'package:flutter/material.dart';

import '../big_p_scale.dart';

/// Content that runs past an edge fades out there instead of being cut:
/// the fade is the sign that there is more, and it goes when the end is
/// reached.
class BigPEdgeFade extends StatefulWidget {
  const BigPEdgeFade({super.key, required this.builder, this.controller, this.extent});

  /// Builds the scroll view around the controller it is given.
  final Widget Function(ScrollController controller) builder;

  /// The owner's controller, when it scrolls the content itself.
  final ScrollController? controller;

  /// How far the fade reaches in from an edge; 44 pt when null.
  final double? extent;

  @override
  State<BigPEdgeFade> createState() => _BigPEdgeFadeState();
}

class _BigPEdgeFadeState extends State<BigPEdgeFade> {
  ScrollController? _own;
  ScrollController get _scroll => widget.controller ?? (_own ??= ScrollController());
  bool _above = false;
  bool _below = false;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_measure);
  }

  @override
  void dispose() {
    _scroll.removeListener(_measure);
    _own?.dispose();
    super.dispose();
  }

  void _measure() {
    if (!mounted || !_scroll.hasClients) return;
    final position = _scroll.position;
    final up = position.axisDirection == AxisDirection.up;
    final above = (up ? position.extentAfter : position.extentBefore) > 0.5;
    final below = (up ? position.extentBefore : position.extentAfter) > 0.5;
    if (above != _above || below != _below) {
      setState(() {
        _above = above;
        _below = below;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final pt = BigPScale.of(context);
    WidgetsBinding.instance.addPostFrameCallback((_) => _measure());
    return ShaderMask(
      blendMode: BlendMode.dstIn,
      shaderCallback: (rect) {
        final fade = ((widget.extent ?? 44 * pt) / rect.height).clamp(0.0, 0.5);
        return LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            _above ? const Color(0x00000000) : const Color(0xFF000000),
            const Color(0xFF000000),
            const Color(0xFF000000),
            _below ? const Color(0x00000000) : const Color(0xFF000000),
          ],
          stops: [0, fade, 1 - fade, 1],
        ).createShader(rect);
      },
      child: widget.builder(_scroll),
    );
  }
}
