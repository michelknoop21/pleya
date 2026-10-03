import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../../theme/mono_tokens.dart';
import 'big_p_layers.dart';
import 'big_p_rig.dart';

export 'big_p_portrait.dart';

enum BigPMood { idle, listening, working, success, error, attentive }

/// Big P, the animated Pleya Assistant. One ticker drives every layer; the
/// behaviour is a port of the approved motion prototype (mockup 38, v2).
class BigPAvatar extends StatefulWidget {
  const BigPAvatar({
    super.key,
    required this.mood,
    this.size = 520,
    this.talkingText,
    this.nodSignal = 0,
    this.pointAt,
    this.entrance = true,
  });

  final BigPMood mood;

  /// Height in logical px.
  final double size;

  /// When non-null, the mouth talks through this text word by word.
  final String? talkingText;

  /// Increment to trigger one nod (working: finger up for a finished step).
  final int nodSignal;

  /// Working: the arm points toward this side. Alignment(1, 0) is straight
  /// right, Alignment(1, 1) 45° down; x < 0 switches to the left-pointing pose.
  final Alignment? pointAt;

  /// Hop with squash and stretch on first build.
  final bool entrance;

  @override
  State<BigPAvatar> createState() => BigPAvatarState();
}

class _Spring {
  _Spring([this.x = 0]);
  double x, v = 0;
  void step(double target, double dt, double k, {bool snap = false}) {
    if (snap) {
      x = target;
      v = 0;
      return;
    }
    // Slightly underdamped: overshoots a fraction, then rests (k 150, z 0.72).
    v += ((target - x) * k - v * 2 * math.sqrt(k) * 0.72) * dt;
    x += v * dt;
  }
}

class _Pulse {
  _Pulse(this.t0, this.dur, {this.dy = 0, this.rot = 0, this.brow = 0, this.fn});
  final double t0, dur, dy, rot, brow;
  final double Function(double x)? fn;
}

@visibleForTesting
class BigPAvatarState extends State<BigPAvatar> with SingleTickerProviderStateMixin {
  final _rand = math.Random();
  late final Ticker _ticker = createTicker(_onTick);
  Duration _lastElapsed = Duration.zero;
  bool _reduced = false;
  bool _precached = false;

  double _t = 0;
  late BigPState _s;
  final _lean = _Spring(), _dy = _Spring(), _aim = _Spring(20), _foot = _Spring();
  final _bl0 = _Spring(), _bl1 = _Spring(), _br0 = _Spring(), _br1 = _Spring(), _open = _Spring();
  final List<_Pulse> _pulses = [];
  final List<(double, double, double)> _hops = []; // t0, dur, height
  double _breathPhase = 0;

  BigPTalkPlan? _talk;
  double _talkStart = 0;
  double _prevTalkT = -1;

  double _ear = 1, _nextEar = 0;
  double _tiltTarget = 0, _nextTilt = 0;
  double _glanceUntil = -1, _nextGlance = 0, _nextWave = 0;
  double _nextBlink = 0, _blinkT = -1;
  bool _double = false;
  double? _waveAt;
  String? _gesturePose;
  double _gestureUntil = 0;
  String _poseFrom = 'rest', _poseTo = 'rest';
  double _poseT = kPoseSwitch;

  // Frame output, read by build().
  String _shownPose = 'rest';
  String _shownMouth = 'rest';
  Matrix4 _rig = Matrix4.identity();
  double _browL = 0, _browLRot = 0, _browR = 0, _browRRot = 0;
  double _blink = 0, _waveRot = 0, _aimRot = 0, _shadowRx = 300, _shadowOpacity = .55;

  @visibleForTesting
  String get shownPose => _shownPose;
  @visibleForTesting
  String get shownMouth => _shownMouth;
  @visibleForTesting
  String get expression => _s.name;
  @visibleForTesting
  int get activePulses => _pulses.length;
  @visibleForTesting
  int get activeHops => _hops.length;
  @visibleForTesting
  Matrix4 get rigTransform => _rig;

  double _r(double a, double b) => a + _rand.nextDouble() * (b - a);

  @override
  void initState() {
    super.initState();
    _s = _stateFor(widget.mood);
    _nextTilt = _r(1, 3);
    _nextGlance = _r(4, 7);
    _nextWave = _r(15, 25);
    _nextBlink = _r(1, 3);
    if (widget.entrance) {
      _hops.add((0, 0.72, 110));
      if (widget.mood == BigPMood.idle) _waveAt = 0.7; // greeting after landing
    }
    _enterMood(widget.mood, initial: true);
    if (widget.talkingText != null) _startTalk(widget.talkingText!);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _reduced = reduceMotion(context, const Duration(seconds: 1)) == Duration.zero;
    if (_reduced) {
      // No transient gestures without motion: straight to the state's pose.
      _gesturePose = null;
      _waveAt = null;
    }
    if (!_precached) {
      _precached = true;
      for (final p in kBigPPoses) {
        precacheImage(AssetImage(bigPPoseAsset(p)), context);
      }
      for (final m in kBigPMouths) {
        precacheImage(AssetImage(bigPAsset('mouth-$m')), context);
      }
    }
    _step(0);
    _syncTicker();
  }

  @override
  void didUpdateWidget(BigPAvatar oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.mood != widget.mood) _enterMood(widget.mood);
    if (oldWidget.nodSignal != widget.nodSignal) _nodFor(widget.mood);
    if (oldWidget.pointAt != widget.pointAt && widget.mood == BigPMood.working) {
      _pulses.add(_Pulse(_t, 0.45, dy: 6, rot: 2.5, brow: -10)); // head turns with the new step
    }
    if (oldWidget.talkingText != widget.talkingText) {
      final text = widget.talkingText;
      if (text == null) {
        _talk = null;
      } else {
        _startTalk(text);
      }
    }
    _step(0);
    _syncTicker();
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  BigPState _stateFor(BigPMood mood) => switch (mood) {
    BigPMood.idle => kStateIdle,
    BigPMood.listening => kStateListening,
    BigPMood.working => kStateWorking,
    BigPMood.success => kStateSuccess,
    BigPMood.error => kStateWorried,
    BigPMood.attentive => kStateAttentive,
  };

  void _enterMood(BigPMood mood, {bool initial = false}) {
    _s = _stateFor(mood);
    if (mood != BigPMood.idle) {
      _glanceUntil = -1;
      _waveAt = null;
    }
    if (mood == BigPMood.success) {
      // Cheer with a hop, then the state's thumbs-up pose.
      _gesture('juichen', 1.15);
      if (!initial || !widget.entrance) _hops.add((_t, 0.8, 150));
    } else if (mood == BigPMood.error) {
      // Head shake, 2.5 times in 1.3 s, fading out; plus a sag.
      _pulses
        ..add(_Pulse(_t, 1.3, fn: (x) => 5.5 * math.sin(2 * math.pi * 2.5 * x) * (1 - x)))
        ..add(_Pulse(_t, 1.1, dy: 22));
    }
  }

  void _nodFor(BigPMood mood) {
    switch (mood) {
      case BigPMood.working: // step done: finger up
        _gesture('vinger_presenteren', 0.85);
        _pulses.add(_Pulse(_t, 0.4, dy: -10, brow: -12));
      case BigPMood.listening: // end of a dictated phrase
        _pulses.add(_Pulse(_t, 0.56, dy: 16 * 0.9, rot: 2.2 * 0.9));
      default:
        _pulses.add(_Pulse(_t, 0.52, dy: 16, rot: 2.2));
    }
  }

  void _gesture(String pose, double seconds) {
    if (_reduced) return;
    _gesturePose = pose;
    _gestureUntil = _t + seconds;
  }

  void _startTalk(String text) {
    _talk = BigPTalkPlan.build(text, calm: widget.mood == BigPMood.error);
    _talkStart = _t;
    _prevTalkT = -1;
  }

  bool get _talkActive => _talk != null && _t - _talkStart < _talk!.end;

  void _syncTicker() {
    final needed = !_reduced || _talkActive;
    if (needed && !_ticker.isActive) {
      _lastElapsed = Duration.zero;
      _ticker.start();
    } else if (!needed && _ticker.isActive) {
      _ticker.stop();
    }
  }

  void _onTick(Duration elapsed) {
    final dt = math.min(0.05, (elapsed - _lastElapsed).inMicroseconds / 1e6);
    _lastElapsed = elapsed;
    setState(() => _step(dt));
    if (_reduced && !_talkActive) _ticker.stop();
  }

  void _autos() {
    final t = _t;
    if (t > _nextTilt) {
      _tiltTarget = _r(-2.6, 2.6);
      _nextTilt = t + _r(2.2, 4.5);
    }
    if (_waveAt != null && t >= _waveAt!) {
      _waveAt = null;
      _gesture('zwaaien', 2.2);
    }
    if (_s == kStateIdle && !_talkingNow && _gesturePose == null) {
      if (t > _nextGlance) {
        _glanceUntil = t + 1.7;
        _nextGlance = t + _r(6, 11);
      }
      if (t > _nextWave) {
        _gesture('zwaaien', 1.7);
        _nextWave = t + _r(15, 25);
      }
    }
    if (_s.ear && t > _nextEar) {
      _ear = -_ear;
      _nextEar = t + _r(2.5, 4);
    }
  }

  bool get _talkingNow => _talk != null && _talk!.talkingAt(_t - _talkStart);

  void _step(double dt) {
    _t += dt;
    final t = _t, s = _s, rm = _reduced;
    if (!rm) _autos();

    // Pose: a gesture beats the state's pose. Swap without crossfade at the midpoint.
    if (_gesturePose != null && t > _gestureUntil) _gesturePose = null;
    var want = _gesturePose ?? s.pose;
    if (want == 'point') want = (widget.pointAt?.x ?? 1) < 0 ? 'wijzen_links' : 'wijzen';
    if (want != _poseTo) {
      _poseFrom = _poseT < kPoseSwitch / 2 ? _poseFrom : _poseTo;
      _poseTo = want;
      _poseT = rm ? kPoseSwitch : 0;
    }
    _poseT = math.min(kPoseSwitch, _poseT + dt);
    final shown = _poseT < kPoseSwitch / 2 ? _poseFrom : _poseTo;
    final swapSquash = rm ? 0.0 : 0.06 * math.sin(math.pi * _poseT / kPoseSwitch);

    // Talking: stress pulses on keyframes crossed this frame.
    final talking = _talkingNow;
    var talkMouth = 'rest';
    if (_talk != null) {
      final tt = t - _talkStart;
      if (talking) talkMouth = _talk!.mouthAt(tt);
      if (!rm) {
        for (final e in _talk!.events) {
          if (e.stress && e.at > _prevTalkT && e.at <= tt) _pulses.add(_Pulse(t, 0.34, dy: 10, rot: 1.6, brow: -12));
        }
      }
      _prevTalkT = tt;
    }

    // Targets.
    final thinkFlip = s.think && (t / 1.4).floor() % 2 == 1;
    final bl = thinkFlip ? [s.br[0], -s.br[1]] : s.bl;
    final br = thinkFlip ? [s.bl[0], -s.bl[1]] : s.br;
    final gl = t < _glanceUntil ? 1.0 : 0.0;
    var aim = 20.0;
    final p = widget.pointAt;
    if (p != null && p.x >= 0) {
      aim = (math.atan2(p.y, p.x == 0 ? 0.001 : p.x) * 180 / math.pi).clamp(kAimMin, kAimMax);
    }
    final k = rm ? 0.0 : 150.0;
    _lean.step(
      s.lean * (s.ear ? _ear : 1) + (rm ? 0 : _tiltTarget) + gl * 5 + (shown == 'wijzen' ? 3.5 : 0),
      dt,
      k,
      snap: rm,
    );
    _dy.step(s.dy + gl * 8, dt, k, snap: rm);
    _bl0.step(bl[0] - gl * 8, dt, k, snap: rm);
    _bl1.step(bl[1], dt, k, snap: rm);
    _br0.step(br[0] - gl * 8, dt, k, snap: rm);
    _br1.step(br[1], dt, k, snap: rm);
    _open.step(talking ? kMouthLevel[talkMouth]! / 3 : 0, dt, 260, snap: rm);
    _foot.step(kPoseFeet.containsKey(shown) ? kBigPFeet.dy - kPoseFeet[shown]! : 0, dt, 400, snap: rm);
    _aim.step(aim, dt, k, snap: rm);

    // Continuous life: float, sway, breathe, pulses, hops.
    double lift = 0, rot = _lean.x, dy = _dy.x, sx = 1, sy = 1, browPulse = 0;
    if (!rm) {
      lift = s.float * 22 * (0.5 - 0.5 * math.cos(t * 2 * math.pi / 3.1));
      rot += s.float * 1.6 * math.sin(t * 2 * math.pi / 6.3);
      _breathPhase += dt / s.breathe;
      final breath = math.sin(2 * math.pi * _breathPhase);
      sy += 0.014 * breath;
      sx -= 0.006 * breath;
      dy += _open.x * 14;
      rot += _open.x * 1.2;
      _pulses.removeWhere((p) {
        final x = (t - p.t0) / p.dur;
        if (x >= 1) return true;
        if (p.fn != null) {
          rot += p.fn!(x);
          return false;
        }
        final f = math.sin(math.pi * (0.5 - math.cos(math.pi * x) / 2));
        dy += p.dy * f;
        rot += p.rot * f;
        browPulse += p.brow * f;
        return false;
      });
      _hops.removeWhere((h) {
        final x = (t - h.$1) / h.$2;
        if (x >= 1) return true;
        final (hl, hs) = bigPHopAt(math.max(0.0, x), h.$3);
        lift += hl;
        sy *= hs;
        sx *= 1 + (1 - hs) * 0.7;
        return false;
      });
      sy *= 1 - swapSquash;
      sx *= 1 + swapSquash * 0.5;
    } else {
      _pulses.clear();
      _hops.clear();
    }

    final f = kBigPFeet;
    _rig = Matrix4.identity()
      ..translateByDouble(f.dx, f.dy, 0, 1)
      ..rotateZ(rot * math.pi / 180)
      ..translateByDouble(-f.dx, -f.dy + dy - lift, 0, 1)
      ..translateByDouble(f.dx, f.dy, 0, 1)
      ..scaleByDouble(sx, sy, 1, 1)
      ..translateByDouble(-f.dx, -f.dy + _foot.x, 0, 1);
    _shadowRx = math.max(150, 300 - lift * 0.9 - dy * 0.4);
    _shadowOpacity = 0.55 * math.max(0.35, 1 - lift / 300);

    _shownPose = shown;
    _waveRot = shown == 'zwaaien' && !rm ? math.sin(t * 11) * 12 : 0;
    _aimRot = _aim.x - kAimBase + (rm ? 0 : math.sin(t * 1.4) * 1.5);

    // Mouth sprites swap hard (crossfading gives two mouths). Reduced: half open while talking.
    _shownMouth = talking ? (rm ? 'small' : talkMouth) : s.mouth;

    final talkBrow = rm ? 0.0 : -10 * _open.x + browPulse;
    _browL = _bl0.x + talkBrow;
    _browLRot = _bl1.x;
    _browR = _br0.x + talkBrow;
    _browRRot = _br1.x;

    // Blink: 150 ms every 1.8-4.5 s, one in five doubled.
    _blink = 0;
    if (!rm) {
      if (_blinkT < 0 && t > _nextBlink) _blinkT = 0;
      if (_blinkT >= 0) {
        _blinkT += dt;
        final x = _blinkT / 0.15;
        if (x >= 1) {
          _blinkT = -1;
          _double = !_double && _rand.nextDouble() < 0.2;
          _nextBlink = t + (_double ? 0.12 : _r(1.8, 4.5) * (s.ear ? 1.4 : 1));
        } else {
          _blink = math.sin(math.pi * x);
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) => BigPLayers(
    size: widget.size,
    pose: _shownPose,
    mouth: _shownMouth,
    face: _s.name,
    rig: _rig,
    browL: _browL,
    browLRot: _browLRot,
    browR: _browR,
    browRRot: _browRRot,
    blink: _blink,
    waveRot: _waveRot,
    aimRot: _aimRot,
    shadowRx: _shadowRx,
    shadowOpacity: _shadowOpacity,
  );
}
