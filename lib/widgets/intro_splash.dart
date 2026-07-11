import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../services/device_performance.dart';
import '../utils/platform_detector.dart';

/// Plays the Pleya startup intro (red wordmark zoom-in + sheen) once
/// per app process, then reveals [child]. Tap to skip. Honors reduced-motion
/// and the reduced performance tier by skipping the animation entirely.
class IntroGate extends StatefulWidget {
  final Widget child;
  const IntroGate({super.key, required this.child});

  /// Ensures the intro plays only on the first cold-start build.
  static bool _played = false;

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> with SingleTickerProviderStateMixin {
  late final bool _skip;
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    // The custom tvOS engine reports reduceMotion=true before accessibility
    // features are populated, which wrongly skipped the intro on Apple TV.
    // tvOS has no per-app reduce-motion toggle we need to honor here, and the
    // splash is brief + tap-to-skip, so ignore the flag on Apple TV.
    final reduceMotion =
        !PlatformDetector.isAppleTV() && WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;
    _skip = IntroGate._played || reduceMotion || DevicePerformance.isReduced;
    IntroGate._played = true;

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2800));
    if (_skip) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _skipIntro() {
    if (_controller.isAnimating) _controller.animateTo(1, duration: const Duration(milliseconds: 250));
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        widget.child,
        if (!_skip)
          AnimatedBuilder(
            animation: _controller,
            builder: (context, _) {
              final t = _controller.value;
              if (t >= 1) return const SizedBox.shrink();
              // Fade the whole overlay out over the last 12%.
              final overlayOpacity = t < 0.88 ? 1.0 : (1 - (t - 0.88) / 0.12).clamp(0.0, 1.0);
              return Positioned.fill(
                child: Opacity(
                  opacity: overlayOpacity,
                  child: GestureDetector(
                    onTap: _skipIntro,
                    child: ColoredBox(
                      color: Colors.black,
                      child: Center(child: _IntroMark(progress: t)),
                    ),
                  ),
                ),
              );
            },
          ),
      ],
    );
  }
}

class _IntroMark extends StatelessWidget {
  final double progress;
  const _IntroMark({required this.progress});

  @override
  Widget build(BuildContext context) {
    final t = progress;

    // Slam-in: 5x → 1x with a slight overshoot punch in the first ~45%,
    // then a slow cinematic push (1 → 1.08) toward the viewer until the end.
    final slamT = (t / 0.45).clamp(0.0, 1.0);
    final slam = 5.0 - 4.0 * Curves.easeOutBack.transform(slamT);
    final push = 1.0 + 0.08 * Curves.easeIn.transform(((t - 0.45) / 0.55).clamp(0.0, 1.0));
    final scale = slam * push;
    final markOpacity = (t / 0.12).clamp(0.0, 1.0);

    // Glow burst: spikes right after the slam lands, then settles to an ember.
    final burstT = ((t - 0.32) / 0.28).clamp(0.0, 1.0);
    final burst = math.sin(burstT * math.pi); // 0 → 1 → 0
    final glowAlpha = 0.20 + 0.55 * burst;
    final glowRadius = 60.0 + 90.0 * burst;

    // Sheen sweep left→right just after the burst.
    final sheenT = ((t - 0.42) / 0.34).clamp(0.0, 1.0);

    // Tagline: fades in late, letter-spacing expands as it appears.
    final tagT = Curves.easeOut.transform(((t - 0.55) / 0.3).clamp(0.0, 1.0));

    return Stack(
      alignment: Alignment.center,
      children: [
        // Rotating fan of red light beams behind the mark (Netflix-style ident).
        Positioned.fill(
          child: CustomPaint(painter: _LightRaysPainter(progress: t)),
        ),
        Transform.scale(
          scale: scale,
          child: Opacity(
            opacity: markOpacity,
            child: ShaderMask(
              blendMode: BlendMode.srcATop,
              shaderCallback: (rect) {
                final dx = (sheenT * 2 - 0.5) * rect.width;
                return LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [Colors.transparent, Colors.white.withValues(alpha: 0.95), Colors.transparent],
                  stops: const [0.3, 0.5, 0.7],
                  transform: GradientTranslation(dx, 0),
                ).createShader(rect);
              },
              // The "Pleya" wordmark lockup — the thick-P mark IS the word's P —
              // with the tagline below and a pulsing red glow behind it.
              child: Column(
                mainAxisSize: .min,
                children: [
                  Container(
                    decoration: BoxDecoration(
                      boxShadow: [
                        BoxShadow(
                          color: const Color(0xFFE5140F).withValues(alpha: glowAlpha),
                          blurRadius: glowRadius,
                          spreadRadius: 8 + 18 * burst,
                        ),
                      ],
                    ),
                    child: Image.asset(
                      'assets/branding/pleya_wordmark.png',
                      width: 340,
                      fit: BoxFit.contain,
                      filterQuality: FilterQuality.medium,
                    ),
                  ),
                  const SizedBox(height: 14),
                  Opacity(
                    opacity: tagT,
                    child: Text(
                      'YOUR MEDIA. YOUR WAY.',
                      style: TextStyle(
                        fontSize: 12,
                        letterSpacing: 1.8 + 1.8 * tagT,
                        color: Colors.white.withValues(alpha: 0.55 * tagT),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}

/// Fan of red light beams radiating from the mark: they bloom out with the
/// glow burst, slowly rotate, and die off before the overlay fades.
class _LightRaysPainter extends CustomPainter {
  final double progress;
  const _LightRaysPainter({required this.progress});

  @override
  void paint(Canvas canvas, Size size) {
    final raysT = ((progress - 0.30) / 0.55).clamp(0.0, 1.0);
    if (raysT <= 0 || raysT >= 1) return;
    final intensity = math.sin(raysT * math.pi); // bloom in, die out

    final center = size.center(Offset.zero);
    final maxLen = size.longestSide * (0.35 + 0.45 * Curves.easeOut.transform(raysT));
    final rotation = raysT * 0.35; // slow drift
    const rayCount = 14;

    for (var i = 0; i < rayCount; i++) {
      final angle = rotation + i * (2 * math.pi / rayCount);
      // Alternate long/short beams for a less mechanical look.
      final len = maxLen * (i.isEven ? 1.0 : 0.65);
      final width = i.isEven ? 0.030 : 0.018; // half-width in radians
      final alpha = intensity * (i.isEven ? 0.10 : 0.06);

      final paint = Paint()
        ..shader = RadialGradient(
          colors: [const Color(0xFFE5140F).withValues(alpha: alpha), Colors.transparent],
          stops: const [0.0, 1.0],
        ).createShader(Rect.fromCircle(center: center, radius: len));

      final path = Path()
        ..moveTo(center.dx, center.dy)
        ..lineTo(center.dx + len * math.cos(angle - width), center.dy + len * math.sin(angle - width))
        ..lineTo(center.dx + len * math.cos(angle + width), center.dy + len * math.sin(angle + width))
        ..close();
      canvas.drawPath(path, paint);
    }
  }

  @override
  bool shouldRepaint(_LightRaysPainter oldDelegate) => oldDelegate.progress != progress;
}

/// Horizontal shader translation for the intro sheen sweep.
class GradientTranslation extends GradientTransform {
  final double dx;
  final double dy;
  const GradientTranslation(this.dx, this.dy);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, dy, 0);
}
