import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';

/// Tells the tvOS engine fork whether Menu belongs to the system (leave the
/// app) or to the app (pop a route).
///
/// The engine answers an *enable* with `releaseAllSynthesizedPresses`: every
/// Siri Remote key it still holds down gets a synthetic keyup, and the
/// press's own `.ended` phase then re-taps that key as a fresh down/up pair
/// (`synthesizeRemotePressType:` with `tapIfMissingKeyDown:YES`). Enabling
/// while an arrow is held is therefore what turned one press into two steps
/// (NAV1, log `wa6v9`): the press that lands on the Home tab raises the
/// passthrough, the engine releases the arrow, and the release phase steps
/// again. An enable is only sent once every key is up. A disable releases
/// nothing on the engine side and goes out immediately.
///
/// `scripts/tvos_engine_source.sh` reconstructs the engine file this
/// describes; the contract is written up in
/// `docs/tvos-remote-press-pipeline.md`.
class TvosSystemNavigationService {
  static const BasicMessageChannel<Object?> _channel = BasicMessageChannel<Object?>(
    'flutter/tvos_system_navigation',
    JSONMessageCodec(),
  );

  /// The last value that actually went over the channel.
  static bool? _menuPassthroughEnabled;

  /// Whether an enable is parked until the last held key is released.
  static bool _enableDeferred = false;

  static Future<void> setMenuPassthroughEnabled(bool enabled) async {
    if (!PlatformDetector.isAppleTV()) return;

    if (enabled && HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) {
      _deferEnableUntilKeysReleased();
      return;
    }
    _cancelDeferredEnable();
    await _send(enabled);
  }

  static Future<void> _send(bool enabled) async {
    if (_menuPassthroughEnabled == enabled) return;

    _menuPassthroughEnabled = enabled;
    await _channel.send({'menuPassthroughEnabled': enabled});
  }

  static void _deferEnableUntilKeysReleased() {
    if (_enableDeferred) return;
    _enableDeferred = true;
    HardwareKeyboard.instance.addHandler(_flushDeferredEnableOnRelease);
  }

  static void _cancelDeferredEnable() {
    if (!_enableDeferred) return;
    _enableDeferred = false;
    HardwareKeyboard.instance.removeHandler(_flushDeferredEnableOnRelease);
  }

  /// Runs after [HardwareKeyboard] has already dropped the key from its
  /// pressed set, so an empty set on a key-up means the remote is idle.
  /// Never claims the event.
  static bool _flushDeferredEnableOnRelease(KeyEvent event) {
    if (event is KeyUpEvent && HardwareKeyboard.instance.physicalKeysPressed.isEmpty) {
      _cancelDeferredEnable();
      unawaited(_send(true));
    }
    return false;
  }

  /// Test-only: clears the last-sent cache and any parked enable so a test
  /// can assert on the next [setMenuPassthroughEnabled] call regardless of
  /// what an earlier test in the same isolate already sent (the cache is a
  /// static, so it otherwise survives across tests in one file).
  @visibleForTesting
  static void debugResetMenuPassthroughCache() {
    _cancelDeferredEnable();
    _menuPassthroughEnabled = null;
  }
}
