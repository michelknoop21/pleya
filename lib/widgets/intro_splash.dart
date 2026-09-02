import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../focus/dpad_navigator.dart';
import '../services/device_performance.dart';
import '../utils/platform_detector.dart';
import 'pleya_wordmark.dart';

/// The Pleya ident: plays once per app process on the first cold-start build,
/// then reveals [child]. Select, Enter, Escape, Space or a tap skips it.
///
/// ## What it is, and what it deliberately is not
///
/// The lockup settles in on [identGround], holds, and dissolves into the page
/// underneath — which is the same colour, so the hand-off is a dissolve into
/// the app rather than a step from black. Every duration and curve is one the
/// TV shell already uses: the settle is the focus curve, the fades are the
/// hero crossfade ("reads as a dissolve rather than a transition").
///
/// The version this replaced was a self-described Netflix-style ident — a
/// rotating fan of red light beams, a 5x slam with overshoot, a sheen sweep, a
/// rectangular red glow — on pure black, with a tagline at a spec of its own.
/// Chapter 31 #10 forbids the first outright, chapter 8.4/24.1 rule out the
/// continuous scaling, and chapter 34 keeps red off area fills. None of that
/// register exists anywhere in the frozen north star, so none of it is here.
///
/// The lockup is the same [PleyaBrandLockup] the boot splash draws underneath,
/// at the proportions the asset generator gives the Top Shelf ([DEC-074]).
class IntroGate extends StatefulWidget {
  const IntroGate({super.key, required this.child});

  final Widget child;

  /// Ensures the intro plays only on the first cold-start build.
  static bool _played = false;

  /// Lets a test see the ident more than once per process.
  @visibleForTesting
  static void debugResetForTesting() => _played = false;

  /// The whole run.
  static const Duration duration = Duration(milliseconds: 1800);

  /// The lockup settling in — the hero crossfade, so it reads as a dissolve.
  static const Duration fadeIn = Duration(milliseconds: 460);

  /// The tagline follows the mark rather than arriving with it.
  static const Duration taglineDelay = Duration(milliseconds: 300);

  /// The dissolve into the page. Same length as the way in.
  static const Duration fadeOut = Duration(milliseconds: 460);

  /// A skip fast-forwards the remainder rather than cutting.
  static const Duration skip = Duration(milliseconds: 250);

  @override
  State<IntroGate> createState() => _IntroGateState();
}

class _IntroGateState extends State<IntroGate> with SingleTickerProviderStateMixin {
  late final bool _skip;
  late final AnimationController _controller;
  bool _precached = false;

  @override
  void initState() {
    super.initState();
    // The custom tvOS engine reports reduceMotion=true before accessibility
    // features are populated, which wrongly skipped the intro on Apple TV.
    // tvOS has no per-app reduce-motion toggle we need to honor here, and the
    // ident is brief and skippable, so ignore the flag on Apple TV.
    final reduceMotion =
        !PlatformDetector.isAppleTV() && WidgetsBinding.instance.platformDispatcher.accessibilityFeatures.reduceMotion;
    _skip = IntroGate._played || reduceMotion || DevicePerformance.isReduced;
    IntroGate._played = true;

    _controller = AnimationController(vsync: this, duration: IntroGate.duration);
    if (_skip) {
      _controller.value = 1;
    } else {
      // A remote has no tap. The handler is global for exactly as long as the
      // ident is on screen, and it consumes the press so the page underneath
      // does not also act on it.
      HardwareKeyboard.instance.addHandler(_onKey);
      _controller.addStatusListener(_onStatus);
      _controller.forward();
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_skip || _precached) return;
    _precached = true;
    // Asset decoding is asynchronous. Without this the first frames of the
    // settle can show the ground with nothing on it.
    for (final asset in PleyaWordmark.assets) {
      precacheImage(AssetImage(asset), context);
    }
  }

  void _onStatus(AnimationStatus status) {
    if (status == AnimationStatus.completed) HardwareKeyboard.instance.removeHandler(_onKey);
  }

  bool _onKey(KeyEvent event) {
    // Once the run has reached its end the overlay is gone, whatever the
    // controller's status says about the exact last frame; the remote is the
    // page's again from that moment.
    if (_controller.value >= 1) return false;
    if (event is! KeyDownEvent) return false;
    final key = event.logicalKey;
    final skips =
        key.isSelectKey ||
        key == LogicalKeyboardKey.escape ||
        key == LogicalKeyboardKey.space ||
        key == LogicalKeyboardKey.enter;
    if (!skips) return false;
    _skipIntro();
    return true;
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    _controller.dispose();
    super.dispose();
  }

  void _skipIntro() {
    if (_controller.isAnimating) _controller.animateTo(1, duration: IntroGate.skip);
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
              return Positioned.fill(
                child: GestureDetector(
                  onTap: _skipIntro,
                  child: _IntroFrame(progress: t, ground: identGround(context)),
                ),
              );
            },
          ),
      ],
    );
  }
}

/// One frame of the ident at [progress] in `[0, 1)`.
class _IntroFrame extends StatelessWidget {
  const _IntroFrame({required this.progress, required this.ground});

  final double progress;
  final Color ground;

  @override
  Widget build(BuildContext context) {
    final ms = progress * IntroGate.duration.inMilliseconds;

    // In: opacity and a settle from 0.96, on the focus curve. The app's
    // largest scale anywhere is the 1.05 focus lift; the ident stays under it.
    final inT = Curves.easeOutCubic.transform((ms / IntroGate.fadeIn.inMilliseconds).clamp(0.0, 1.0));
    final tagT = Curves.easeOut.transform(
      ((ms - IntroGate.taglineDelay.inMilliseconds) / IntroGate.fadeIn.inMilliseconds).clamp(0.0, 1.0),
    );
    // Out: the whole overlay dissolves, ground included, so what is left is
    // the page — which is the same colour, so only the lockup is seen to go.
    final outStart = IntroGate.duration.inMilliseconds - IntroGate.fadeOut.inMilliseconds;
    final outT = Curves.easeInOut.transform(((ms - outStart) / IntroGate.fadeOut.inMilliseconds).clamp(0.0, 1.0));

    return Opacity(
      key: const ValueKey('introOverlay'),
      opacity: 1 - outT,
      child: ColoredBox(
        color: ground,
        child: Center(
          child: Opacity(
            opacity: inT,
            child: Transform.scale(
              scale: 0.96 + 0.04 * inT,
              child: PleyaBrandLockup(height: kIdentLockupHeight, taglineOpacity: tagT),
            ),
          ),
        ),
      ),
    );
  }
}
