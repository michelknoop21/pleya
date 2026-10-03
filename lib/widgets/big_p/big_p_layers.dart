import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'big_p_rig.dart';

/// One rendered frame of Big P: the layer stack in source coordinates, scaled
/// to [size] (height). Pure view; [BigPAvatar]'s engine supplies the values.
class BigPLayers extends StatelessWidget {
  const BigPLayers({
    super.key,
    required this.size,
    required this.pose,
    required this.mouth,
    required this.face,
    required this.rig,
    required this.browL,
    required this.browLRot,
    required this.browR,
    required this.browRRot,
    required this.blink,
    required this.waveRot,
    required this.aimRot,
    required this.shadowRx,
    required this.shadowOpacity,
  });

  final double size;
  final String pose, mouth, face;
  final Matrix4 rig;
  final double browL, browLRot, browR, browRRot, blink, waveRot, aimRot, shadowRx, shadowOpacity;

  static Widget _box(Rect r, Widget child) =>
      Positioned(left: r.left, top: r.top, width: r.width, height: r.height, child: child);

  static Widget _img(String asset, {Key? key}) =>
      Image.asset(asset, key: key, fit: BoxFit.fill, gaplessPlayback: true, filterQuality: FilterQuality.medium);

  static Matrix4 _rotAbout(Offset pivot, double deg) => Matrix4.identity()
    ..translateByDouble(pivot.dx, pivot.dy, 0, 1)
    ..rotateZ(deg * math.pi / 180)
    ..translateByDouble(-pivot.dx, -pivot.dy, 0, 1);

  Widget _brow(Rect box, String asset, double lift, double deg) => Positioned.fill(
    child: Transform(
      transform: Matrix4.identity()
        ..translateByDouble(0, lift, 0, 1)
        ..multiply(_rotAbout(box.center, deg)),
      child: Stack(children: [_box(box, _img(asset))]),
    ),
  );

  @override
  Widget build(BuildContext context) {
    const full = Rect.fromLTWH(0, 0, kBigPWidth, kBigPHeight);
    final layers = <Widget>[
      if (pose == 'wijzen') ...[
        Positioned(
          left: kAimPivot.dx - 26,
          top: kAimPivot.dy - 26,
          width: 52,
          height: 52,
          child: const DecoratedBox(
            decoration: BoxDecoration(color: kBigPLimb, shape: BoxShape.circle),
          ),
        ),
        Positioned.fill(
          child: Transform(
            key: const ValueKey('bigp-aim-arm'),
            transform: _rotAbout(kAimPivot, aimRot),
            child: Stack(children: [_box(kAimBox, _img(bigPAsset('aim-arm')))]),
          ),
        ),
      ],
      _box(full, _img(bigPPoseAsset(pose), key: ValueKey('bigp-pose-$pose'))),
      if (pose == 'zwaaien')
        Positioned.fill(
          child: Transform(
            key: const ValueKey('bigp-wave-arm'),
            transform: _rotAbout(kWavePivot, waveRot),
            child: Stack(children: [_box(kWaveBox, _img(bigPAsset('wave-arm')))]),
          ),
        ),
      if (!kOwnFacePoses.contains(pose))
        Positioned.fill(
          key: ValueKey('bigp-face-$face'),
          child: Stack(
            children: [
              _box(kMouthBox, _img(bigPAsset('mouth-$mouth'), key: ValueKey('bigp-mouth-$mouth'))),
              Positioned.fill(child: CustomPaint(painter: BigPLidPainter(blink))),
              _brow(kBrowLBox, bigPAsset('brow-l'), browL, browLRot),
              _brow(kBrowRBox, bigPAsset('brow-r'), browR, browRRot),
            ],
          ),
        ),
    ];
    return RepaintBoundary(
      child: SizedBox(
        height: size,
        width: size * kBigPWidth / kBigPHeight,
        child: FittedBox(
          child: SizedBox(
            width: kBigPWidth,
            height: kBigPHeight,
            child: Stack(
              clipBehavior: Clip.none,
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: BigPFloorPainter(shadowRx: shadowRx, shadowOpacity: shadowOpacity),
                  ),
                ),
                Positioned.fill(
                  child: Transform(
                    key: const ValueKey('bigp-rig'),
                    transform: rig,
                    child: Stack(clipBehavior: Clip.none, children: layers),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
