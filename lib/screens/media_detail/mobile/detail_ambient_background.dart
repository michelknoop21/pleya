import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

/// The glow behind the top of the detail page (D-01 `.ambient`): a blurred,
/// saturated copy of the poster, 160% wide and anchored below the poster,
/// fading out about 1500 pt down into the page ground under it. It scrolls
/// with [child]. Without [image] only the page ground shows.
class DetailAmbientBackground extends StatelessWidget {
  const DetailAmbientBackground({super.key, required this.image, required this.child});

  final ImageProvider? image;
  final Widget child;

  static const double _height = 1500;

  // Saturation 1.5, the mockup's `saturate(1.5)`.
  static const _saturate = ColorFilter.matrix([
    1.3936, -0.3576, -0.036, 0, 0, //
    -0.1064, 1.1424, -0.036, 0, 0, //
    -0.1064, -0.3576, 1.464, 0, 0, //
    0, 0, 0, 1, 0,
  ]);

  @override
  Widget build(BuildContext context) {
    final image = this.image;
    if (image == null) return child;
    // No clip: on a page shorter than the glow, the glow runs on below the
    // content instead of ending in a hard edge.
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Positioned(
          top: 0,
          left: 0,
          right: 0,
          height: _height,
          child: IgnorePointer(
            child: RepaintBoundary(
              // The glow fades out into the page ground below it (the fixed
              // dark gradient of the detail page), not into a flat colour.
              child: ShaderMask(
                blendMode: BlendMode.dstIn,
                shaderCallback: (bounds) => const LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Colors.black, Color(0xBF000000), Color(0x4D000000), Colors.transparent],
                  stops: [0, 0.45, 0.75, 1],
                ).createShader(bounds),
                child: ClipRect(
                  child: Stack(
                    children: [
                      // From the top: the band above the poster (status bar and
                      // back/more bar) takes the glow too, so the poster has no
                      // hard edge against a bare page.
                      Positioned(
                        top: 0,
                        left: 0,
                        right: 0,
                        height: _height,
                        child: FractionallySizedBox(
                          widthFactor: 1.6,
                          child: ImageFiltered(
                            imageFilter: ImageFilter.compose(
                              outer: ImageFilter.blur(sigmaX: 60, sigmaY: 60),
                              inner: _saturate,
                            ),
                            child: Image(
                              image: image,
                              fit: BoxFit.cover,
                              alignment: const Alignment(0, 0.7),
                              opacity: const AlwaysStoppedAnimation(0.6),
                              gaplessPlayback: true,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
        child,
      ],
    );
  }
}
