// Geometry, poses and timing for Big P, ported from the approved motion
// prototype (docs/assets/tvos-unified/src/prototype/38-big-p-motion/bigp.js).
// All coordinates are in the full source space of bigp-layers.json
// (1122 x 1402); the PNGs in assets/branding/bigp/ are half size and are
// stretched onto these boxes, exactly like the prototype does.
import 'dart:math' as math;

import 'package:flutter/rendering.dart';

const double kBigPWidth = 1122;
const double kBigPHeight = 1402;
const Offset kBigPFeet = Offset(545, 1184);
const String kBigPAssetDir = 'assets/branding/bigp';

const Rect kMouthBox = Rect.fromLTWH(386, 387, 257, 272);
const Rect kBrowLBox = Rect.fromLTWH(405, 225, 119, 62);
const Rect kBrowRBox = Rect.fromLTWH(696, 226, 102, 58);
const Rect kWaveBox = Rect.fromLTWH(28, 267, 240, 393);
const Offset kWavePivot = Offset(289, 566);
const Rect kAimBox = Rect.fromLTWH(690, 628, 388, 188);
const Offset kAimPivot = Offset(722, 658);
const Offset kAimTip = Offset(1068, 722);
const Color kBigPLimb = Color(0xFF1B0B09);
const Color kBigPLash = Color(0xFF2A0604);

class BigPEye {
  const BigPEye(this.cx, this.cy, this.rx, this.ry, this.lid);
  final double cx, cy, rx, ry;
  final Color lid;
}

const List<BigPEye> kBigPEyes = [
  BigPEye(460, 382, 62, 63, Color(0xFFFC2013)),
  BigPEye(768, 378, 47, 63, Color(0xFFFC5B2E)),
];

/// Full-figure poses. `rest` is body.png, `wijzen` is body-wijzen.png plus the
/// separate aim arm; the rest are pose-*.png.
const List<String> kBigPPoses = [
  'rest',
  'wijzen',
  'zwaaien',
  'juichen',
  'duim_presenteren',
  'vinger_presenteren',
  'wijzen_links',
];

/// Per-pose floor line; the figure shifts down by `feet - poseFeet`.
const Map<String, double> kPoseFeet = {
  'zwaaien': 1157,
  'juichen': 1238,
  'duim_presenteren': 1147,
  'vinger_presenteren': 1149,
  'wijzen_links': 1228,
};

/// Three-quarter view with its own baked face: no mouth, brow or lid layer.
const Set<String> kOwnFacePoses = {'wijzen_links'};

const List<String> kBigPMouths = ['rest', 'small', 'mid', 'big', 'o', 'e', 'laugh'];
const Map<String, int> kMouthLevel = {'rest': 0, 'small': 1, 'e': 1, 'o': 1, 'mid': 2, 'big': 3, 'laugh': 3};

final double kAimBase = math.atan2(kAimTip.dy - kAimPivot.dy, kAimTip.dx - kAimPivot.dx) * 180 / math.pi;
const double kAimMin = -12, kAimMax = 60;

/// Pose swap length in seconds; the image flips at the midpoint while the body squashes.
const double kPoseSwitch = 0.27;

String bigPAsset(String name) => '$kBigPAssetDir/$name.png';
String bigPPoseAsset(String pose) => switch (pose) {
  'rest' => bigPAsset('body'),
  'wijzen' => bigPAsset('body-wijzen'),
  _ => bigPAsset('pose-$pose'),
};

/// One expression/posture preset (STATES in the prototype). Brows are
/// `[lift, rotation°]`; lean in degrees around the feet; dy sags the figure.
class BigPState {
  const BigPState({
    required this.name,
    required this.bl,
    required this.br,
    required this.mouth,
    required this.lean,
    required this.dy,
    required this.float,
    required this.breathe,
    required this.pose,
    this.ear = false,
    this.think = false,
  });
  final String name;
  final List<double> bl, br;
  final String mouth;
  final double lean, dy, float, breathe;
  final String pose;
  final bool ear, think;
}

const kStateIdle = BigPState(
  name: 'idle',
  bl: [0, 0],
  br: [0, 0],
  mouth: 'rest',
  lean: 0,
  dy: 0,
  float: 1,
  breathe: 3.4,
  pose: 'rest',
);
const kStateListening = BigPState(
  name: 'listening',
  bl: [-20, -3],
  br: [-20, 3],
  mouth: 'o',
  lean: 4,
  dy: 10,
  float: .7,
  breathe: 4.2,
  pose: 'rest',
  ear: true,
);
const kStateWorking = BigPState(
  name: 'working',
  bl: [-16, 3],
  br: [4, 5],
  mouth: 'rest',
  lean: 3.5,
  dy: 4,
  float: .6,
  breathe: 3.4,
  pose: 'point',
  think: true,
);
const kStateSuccess = BigPState(
  name: 'success',
  bl: [-24, 0],
  br: [-24, 0],
  mouth: 'laugh',
  lean: 0,
  dy: 0,
  float: 1.2,
  breathe: 3.0,
  pose: 'duim_presenteren',
);
const kStateWorried = BigPState(
  name: 'worried',
  bl: [-14, -16],
  br: [-14, 16],
  mouth: 'o',
  lean: -1.5,
  dy: 18,
  float: .35,
  breathe: 5.0,
  pose: 'rest',
);
const kStateAttentive = BigPState(
  name: 'attentive',
  bl: [-10, 0],
  br: [-10, 0],
  mouth: 'rest',
  lean: 3,
  dy: 6,
  float: .5,
  breathe: 4.4,
  pose: 'rest',
);

/// Hop with squash and stretch at progress [x] in 0..1 for height [h]:
/// returns (lift, verticalScale).
(double, double) bigPHopAt(double x, double h) {
  const a = 0.16, b = 0.72;
  if (x < a) return (0, 1 - 0.12 * math.sin(math.pi / 2 * (x / a)));
  if (x < b) {
    final v = (x - a) / (b - a);
    return (h * 4 * v * (1 - v), 1 + 0.09 * math.pow(math.cos(math.pi * v), 2));
  }
  final w = (x - b) / (1 - b);
  return (0, 1 - 0.13 * math.sin(math.pi * w) * (1 - 0.4 * w));
}

class TalkEvent {
  const TalkEvent(this.at, this.mouth, {this.stress = false});
  final double at;
  final String mouth;
  final bool stress;
}

/// The whole spoken rhythm of a text, planned up front: mouth keyframes plus
/// the windows in which Big P is talking (mouth closed between sentences).
/// Port of `speak()` / `hush()` / `talk()` from the prototype.
class BigPTalkPlan {
  BigPTalkPlan._(this.events, this.windows);

  final List<TalkEvent> events;
  final List<(double, double)> windows;
  double get end => windows.isEmpty ? 0 : windows.last.$2;

  static final _vowels = RegExp('[aeiouyáéëïóöü]+');
  static final _oShape = RegExp(r'^(oe|oo|o|u|uu|ou|au|ui)$');
  static final _eShape = RegExp(r'^(i|ie|ee|e|ij|ei|y|eu)$');

  factory BigPTalkPlan.build(String text, {bool calm = false}) {
    final events = <TalkEvent>[];
    final windows = <(double, double)>[];
    double at = 0;
    double? windowStart;
    for (final word in text.trim().split(RegExp(r'\s+')).where((w) => w.isNotEmpty)) {
      windowStart ??= at;
      final groups = _vowels.allMatches(word.toLowerCase()).map((m) => m[0]!).toList();
      if (groups.isEmpty) groups.add('a');
      final dur = math.max(0.22, groups.length * (calm ? 0.2 : 0.17));
      final stress = !calm && (word.replaceAll(RegExp(r'\W'), '').length >= 7 || RegExp('^[A-Z0-9]').hasMatch(word));
      final step = dur / groups.length;
      var t = at;
      for (var i = 0; i < groups.length; i++) {
        final g = groups[i];
        var m = _oShape.hasMatch(g) ? 'o' : (_eShape.hasMatch(g) ? 'e' : (stress && i == 0 ? 'big' : 'mid'));
        if (calm && m == 'big') m = 'mid';
        events
          ..add(TalkEvent(t, 'small'))
          ..add(TalkEvent(t + step * 0.25, m, stress: stress && i == 0))
          ..add(TalkEvent(t + step * 0.75, 'small'));
        t += step;
      }
      final wordEnd = at + dur;
      if (RegExp(r'[.?!:]$').hasMatch(word)) {
        windows.add((windowStart, wordEnd + 0.12));
        windowStart = null;
        at = wordEnd + (calm ? 0.46 : 0.36);
      } else {
        at = RegExp(r',$').hasMatch(word) ? wordEnd + 0.16 : wordEnd;
      }
    }
    if (windowStart != null) windows.add((windowStart, at + 0.12));
    return BigPTalkPlan._(events, windows);
  }

  bool talkingAt(double t) => windows.any((w) => t >= w.$1 && t < w.$2);

  /// Mouth sprite at [t] while talking (`rest` before the first key of a window).
  String mouthAt(double t) {
    final window = windows.firstWhere((w) => t >= w.$1 && t < w.$2, orElse: () => (-1, -1));
    var m = 'rest';
    for (final e in events) {
      if (e.at > t) break;
      if (e.at >= window.$1) m = e.mouth;
    }
    return m;
  }
}

/// Upper lid in the face colour plus a small lower lid, clipped to each eye
/// ellipse; [blink] is 0 (open) to 1 (closed). Port of `lidPath()`.
class BigPLidPainter extends CustomPainter {
  const BigPLidPainter(this.blink);
  final double blink;

  @override
  void paint(Canvas canvas, Size size) {
    if (blink <= 0.02) return;
    canvas.scale(size.width / kBigPWidth, size.height / kBigPHeight);
    final b = blink;
    for (final e in kBigPEyes) {
      final x0 = e.cx - e.rx - 2, x1 = e.cx + e.rx + 2;
      final top = e.cy - e.ry - 30;
      final meet = e.cy + e.ry * 0.25;
      final edge = e.cy - e.ry + (meet - (e.cy - e.ry)) * b;
      final bulge = e.ry * 0.28 * math.min(1, b * 1.4);
      final low = e.cy + e.ry - (e.cy + e.ry - meet) * b;
      final lid = Path()
        ..moveTo(x0, top)
        ..lineTo(x1, top)
        ..lineTo(x1, edge)
        ..quadraticBezierTo(e.cx, edge + 2 * bulge, x0, edge)
        ..close()
        ..moveTo(x0, e.cy + e.ry + 6)
        ..lineTo(x1, e.cy + e.ry + 6)
        ..lineTo(x1, low)
        ..quadraticBezierTo(e.cx, low - e.ry * 0.12, x0, low)
        ..close();
      final lash = Path()
        ..moveTo(x0, edge)
        ..quadraticBezierTo(e.cx, edge + 2 * bulge, x1, edge);
      canvas
        ..save()
        ..clipPath(
          Path()..addOval(Rect.fromCenter(center: Offset(e.cx, e.cy), width: 2 * (e.rx + 3), height: 2 * (e.ry + 3))),
        );
      final bounds = lid.getBounds();
      canvas.drawPath(
        lid,
        Paint()
          ..shader = LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [e.lid, e.lid, const Color(0xFF7A0905)],
            stops: const [0, 0.7, 1],
          ).createShader(bounds),
      );
      canvas
        ..drawPath(
          lash,
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 7
            ..color = kBigPLash.withValues(alpha: math.min(1, b * 1.6)),
        )
        ..restore();
    }
  }

  @override
  bool shouldRepaint(BigPLidPainter oldDelegate) => oldDelegate.blink != blink;
}

/// Floor glow plus a contact shadow that shrinks while Big P floats.
class BigPFloorPainter extends CustomPainter {
  const BigPFloorPainter({required this.shadowRx, required this.shadowOpacity});
  final double shadowRx, shadowOpacity;

  @override
  void paint(Canvas canvas, Size size) {
    canvas.scale(size.width / kBigPWidth, size.height / kBigPHeight);
    // Elliptical glow (rx 470, ry 80): a circular gradient squashed vertically.
    final glow = Rect.fromCircle(center: Offset.zero, radius: 470);
    canvas
      ..save()
      ..translate(kBigPFeet.dx, kBigPFeet.dy + 6)
      ..scale(1, 80 / 470)
      ..drawOval(
        glow,
        Paint()
          ..shader = const RadialGradient(
            colors: [Color(0x6BE5140F), Color(0x24E5140F), Color(0x00E5140F)],
            stops: [0, .55, 1],
          ).createShader(glow),
      )
      ..restore()
      ..drawOval(
        Rect.fromCenter(center: kBigPFeet.translate(0, 4), width: 2 * shadowRx, height: 40),
        Paint()..color = Color.fromRGBO(0, 0, 0, shadowOpacity),
      );
  }

  @override
  bool shouldRepaint(BigPFloorPainter oldDelegate) =>
      oldDelegate.shadowRx != shadowRx || oldDelegate.shadowOpacity != shadowOpacity;
}
