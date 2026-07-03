import 'package:flutter/services.dart';

import 'platform_detector.dart';

/// Thin wrapper over [HapticFeedback] that no-ops on TV and desktop, where
/// there is no haptic engine (and a d-pad focus-heavy UI would fire far too
/// often). Call the intent-named helpers at discrete user actions only —
/// never on every focus change.
class Haptics {
  Haptics._();

  static bool get _enabled => !PlatformDetector.isTV() && !PlatformDetector.isDesktopOS();

  /// Discrete selection change: toggles, seek ticks, mark watched/unwatched.
  static void selection() {
    if (_enabled) HapticFeedback.selectionClick();
  }

  /// Confirming a primary action: play/pause, watchlist add/remove, rating,
  /// pull-to-refresh, speed-boost start/stop.
  static void light() {
    if (_enabled) HapticFeedback.lightImpact();
  }
}
