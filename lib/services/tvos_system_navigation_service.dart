import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../automation/automation_ids.dart';
import '../automation/automation_registry.dart';
import '../utils/app_logger.dart';
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

  /// Enables that waited for a key-up before going out. The signature of the
  /// fix, and what `tvos.nav.held-press-lands-once` asserts on.
  static int _parkedFlushes = 0;

  /// Enables that went out while a key was down. Stays zero with the
  /// deferral in place; the negative control of the scenario makes it one.
  /// A disable while held is fine and is not counted: it releases nothing.
  static int _enablesSentWhileKeysHeld = 0;

  static int? _automationToken;

  /// What `/v1/ui_tree` reports under [AutomationIds.tvosMenuPassthrough].
  @visibleForTesting
  static Map<String, Object?> automationState() => {
    'enabled': _menuPassthroughEnabled,
    'parked': _enableDeferred,
    'parkedFlushes': _parkedFlushes,
    'enablesSentWhileKeysHeld': _enablesSentWhileKeysHeld,
  };

  static void _ensureAutomationNode() {
    if (_automationToken != null) return;
    _automationToken = AutomationRegistry.instance.register(
      AutomationDeclaredNode(id: AutomationIds.tvosMenuPassthrough, role: 'service', state: automationState),
    );
  }

  static Future<void> setMenuPassthroughEnabled(bool enabled) async {
    if (!PlatformDetector.isAppleTV()) return;
    _ensureAutomationNode();

    final held = HardwareKeyboard.instance.physicalKeysPressed;
    if (enabled && held.isNotEmpty) {
      _log('enable parked, keys held: ${held.map((k) => k.debugName).join(',')}');
      _deferEnableUntilKeysReleased();
      return;
    }
    _cancelDeferredEnable();
    await _send(enabled);
  }

  static Future<void> _send(bool enabled) async {
    if (_menuPassthroughEnabled == enabled) return;

    _menuPassthroughEnabled = enabled;
    if (enabled && HardwareKeyboard.instance.physicalKeysPressed.isNotEmpty) _enablesSentWhileKeysHeld++;
    _log('send menuPassthroughEnabled=$enabled');
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
      _log('keys released, sending the parked enable');
      _cancelDeferredEnable();
      _parkedFlushes++;
      unawaited(_send(true));
    }
    return false;
  }

  /// Debug level, like the key events in `AppleTvRemoteTouchService`, so a
  /// device log shows this message *between* a keydown and a stray keyup.
  /// That is the third signal the NAV1 logs lacked
  /// (docs/tvos-remote-press-pipeline.md, meetprotocol).
  static void _log(String message) => appLogger.d('TvosSystemNavigationService: $message');

  /// Test-only: clears the last-sent cache and any parked enable so a test
  /// can assert on the next [setMenuPassthroughEnabled] call regardless of
  /// what an earlier test in the same isolate already sent (the cache is a
  /// static, so it otherwise survives across tests in one file).
  @visibleForTesting
  static void debugResetMenuPassthroughCache() {
    _cancelDeferredEnable();
    _menuPassthroughEnabled = null;
    _parkedFlushes = 0;
    _enablesSentWhileKeysHeld = 0;
  }
}
