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

  static bool get isActive => _active;

  static void begin() => _active = true;

  static void end() => _active = false;

  @visibleForTesting
  static void debugReset() => _active = false;
}
