import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import 'big_p_rig.dart';

/// Still head-and-shoulders portrait for the Mijn Pleya tile. When [focused]
/// turns true it reacts once (brows up, small lift, 400 ms) and stays still.
class BigPPortrait extends StatefulWidget {
  const BigPPortrait({super.key, required this.focused, this.size = 96});

  final bool focused;
  final double size;

  @override
  State<BigPPortrait> createState() => _BigPPortraitState();
}

class _BigPPortraitState extends State<BigPPortrait> with SingleTickerProviderStateMixin {
  // Square crop around the head in source coordinates.
  static const _crop = Rect.fromLTWH(250, 130, 680, 680);

  late final AnimationController _react = AnimationController(vsync: this, duration: const Duration(milliseconds: 400));

  @override
  void didUpdateWidget(BigPPortrait oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.focused && !oldWidget.focused && reduceMotion(context, _react.duration!) != Duration.zero) {
      _react.forward(from: 0);
    }
  }

  @override
  void dispose() {
    _react.dispose();
    super.dispose();
  }

  Widget _layer(Rect r, String asset, {Key? key, double dy = 0}) => Positioned(
    key: key,
    left: r.left - _crop.left,
    top: r.top - _crop.top + dy,
    width: r.width,
    height: r.height,
    child: Image.asset(asset, fit: BoxFit.fill, filterQuality: FilterQuality.medium),
  );

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(
      child: SizedBox.square(
        dimension: widget.size,
        child: ClipRect(
          child: AnimatedBuilder(
            animation: _react,
            builder: (context, _) {
              final f = _react.isAnimating ? math.sin(math.pi * _react.value) : 0.0;
              return Transform.translate(
                offset: Offset(0, -4 * f),
                child: FittedBox(
                  child: SizedBox.fromSize(
                    size: _crop.size,
                    child: Stack(
                      clipBehavior: Clip.none,
                      children: [
                        _layer(const Rect.fromLTWH(0, 0, kBigPWidth, kBigPHeight), bigPPoseAsset('rest')),
                        _layer(kMouthBox, bigPAsset('mouth-rest')),
                        _layer(
                          kBrowLBox,
                          bigPAsset('brow-l'),
                          dy: -14 * f,
                          key: const ValueKey('bigp-portrait-brow-l'),
                        ),
                        _layer(kBrowRBox, bigPAsset('brow-r'), dy: -14 * f),
                      ],
                    ),
                  ),
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}
