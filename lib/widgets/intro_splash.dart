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
    final reduceMotion = !PlatformDetector.isAppleTV() &&
        WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;
    _skip = IntroGate._played || reduceMotion || DevicePerformance.isReduced;
    IntroGate._played = true;

    _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 2400));
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
    // Zoom from 3x → 1x over the first ~60%, hold, then handled by overlay fade.
    final zoomT = (progress / 0.6).clamp(0.0, 1.0);
    final scale = 3.0 - 2.0 * Curves.easeOutCubic.transform(zoomT);
    final markOpacity = (progress / 0.18).clamp(0.0, 1.0);

    // Sheen sweep left→right across the middle of the animation.
    final sheenT = ((progress - 0.35) / 0.4).clamp(0.0, 1.0);

    return Transform.scale(
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
              colors: const [Colors.transparent, Colors.white, Colors.transparent],
              stops: const [0.35, 0.5, 0.65],
              transform: GradientTranslation(dx, 0),
            ).createShader(rect);
          },
          // The new thick-P mark + PLEYA wordmark lockup, matching the setup
          // splash, with a warm red glow behind the mark.
          child: Column(
            mainAxisSize: .min,
            children: [
              DecoratedBox(
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(30),
                  boxShadow: const [BoxShadow(color: Color(0x66E5140F), blurRadius: 60, spreadRadius: 4)],
                ),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(30),
                  child: Image.asset(
                    'assets/branding/pleya_logo.png',
                    width: 148,
                    height: 148,
                    filterQuality: FilterQuality.medium,
                  ),
                ),
              ),
              const SizedBox(height: 22),
              const Text(
                'PLEYA',
                style: TextStyle(color: Colors.white, fontSize: 30, fontWeight: .w800, letterSpacing: 12),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Horizontal shader translation for the intro sheen sweep.
class GradientTranslation extends GradientTransform {
  final double dx;
  final double dy;
  const GradientTranslation(this.dx, this.dy);

  @override
  Matrix4 transform(Rect bounds, {TextDirection? textDirection}) => Matrix4.translationValues(dx, dy, 0);
}
