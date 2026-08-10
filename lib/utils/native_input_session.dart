import 'package:flutter/foundation.dart';

/// Whether a native platform surface currently owns the remote.
///
/// On Apple TV the system keyboard runs in a presented view controller that
/// takes over the focus engine. Every synthetic-key path in this app — gamepad,
/// Siri Remote touch surface, companion remote — dispatches straight into the
/// Flutter focus tree, bypassing [HardwareKeyboard] entirely, so without a gate
/// they keep driving the UI hidden behind the keyboard and leave focus
/// somewhere unexpected when it closes.
///
/// Deliberately synchronous: the call that opens the native surface is awaited,
/// so an async flag would leave a window in which the keyboard is already up
/// and Dart is still armed.
class NativeInputSession {
  NativeInputSession._();

  static bool _active = false;
  static VoidCallback? _onRequestClose;

  static bool get isActive => _active;

  /// [onRequestClose] is the way back out. The gate below swallows every key
  /// that reaches Dart during a session, and that has to include the back key —
  /// otherwise it moves focus behind the keyboard. But swallowing it outright
  /// leaves the user with no exit whenever the native escape hatch misses the
  /// press: the first Menu does nothing and they have to press again. So the
  /// owner of the surface registers how to close itself, and a back key that
  /// lands in Dart ends the session instead of vanishing.
  static void begin({VoidCallback? onRequestClose}) {
    _onRequestClose = onRequestClose;
    _active = true;
  }

  static void end() {
    _onRequestClose = null;
    _active = false;
  }

  /// Asks the active surface to close. False when nothing is listening, so the
  /// caller can fall back to plain suppression rather than assume it worked.
  static bool requestClose() {
    final handler = _onRequestClose;
    if (handler == null) return false;
    handler();
    return true;
  }

  @visibleForTesting
  static void debugReset() {
    _onRequestClose = null;
    _active = false;
  }
}
