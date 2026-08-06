import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/native_input_session.dart';
import 'gamepad_service.dart';
import 'settings_service.dart';

/// Result of a native Apple TV text-entry session.
class AppleTvTextEntryResult {
  const AppleTvTextEntryResult(this.text, this.submitted);
  final String text;
  final bool submitted;
}

/// Client for the native tvOS text-entry plugin (see NativeTextEntryPlugin.swift).
///
/// A singleton, because Flutter routes incoming platform calls by channel
/// *name*: with one handler-owning instance per caller, whichever instance was
/// constructed last received every `textChanged` event — so a session started
/// elsewhere (e.g. voice search) streamed its keystrokes into a stale handler
/// whose callback had already been nulled. The single instance hands the
/// events to whichever session is currently active.
class AppleTvNativeTextEntry {
  AppleTvNativeTextEntry({MethodChannel? channel})
    : _channel = channel ?? const MethodChannel('com.pleya/native_text_entry') {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'textChanged') {
        _activeOnTextChanged?.call(call.arguments as String? ?? '');
      }
    });
  }

  static final AppleTvNativeTextEntry instance = AppleTvNativeTextEntry();

  /// Error code the plugin returns when a session is already on screen.
  static const busyCode = 'BUSY';

  /// Watchdog codes: the surface was presented but the system keyboard never
  /// took over — [deadCode] when the user was pressing buttons with nothing
  /// responding, [unavailableCode] when it never came up at all.
  static const deadCode = 'KEYBOARD_DEAD';
  static const unavailableCode = 'KEYBOARD_UNAVAILABLE';

  final MethodChannel _channel;

  ValueChanged<String>? _activeOnTextChanged;
  bool _sessionActive = false;
  bool? _unavailable;

  /// Whether the native surface has been written off. Latched by the watchdog
  /// codes so a device where this path is broken never shows the dead surface
  /// again — every caller goes straight to its fallback. Only [deadCode]
  /// survives a relaunch; see [_markUnavailable].
  bool get isUnavailable {
    final cached = _unavailable;
    if (cached != null) return cached;
    try {
      final stored = SettingsService.instance.read(SettingsService.nativeTextEntryUnavailable);
      _unavailable = stored;
      return stored;
    } on StateError {
      // Settings aren't up yet (tests, earliest startup). Assume usable and
      // re-read later rather than caching a guess.
      return false;
    }
  }

  void _markUnavailable({required bool persist}) {
    _unavailable = true;
    if (!persist) return;
    try {
      SettingsService.instance.write(SettingsService.nativeTextEntryUnavailable, true);
    } on StateError {
      // No persistence available — the in-memory latch still holds for this run.
    }
  }

  @visibleForTesting
  void debugResetAvailability() => _unavailable = false;

  /// Opens the native tvOS system keyboard. While it is up, the Siri Remote mic
  /// button dictates into it and iPhone Continuity typing streams through
  /// [onTextChanged].
  ///
  /// Synthetic key dispatch is gated for the duration of the session so remote
  /// input can't drive the Flutter UI hidden behind the keyboard.
  ///
  /// Throws [PlatformException] (including code [busyCode] when a session is
  /// already active) and [MissingPluginException] — callers own the fallback
  /// policy. Once the surface has been written off ([isUnavailable]) this
  /// throws [MissingPluginException] without going near the platform, so every
  /// caller takes the same fallback it already has for an unregistered plugin.
  Future<AppleTvTextEntryResult> edit({
    required String text,
    String? hint,
    bool obscure = false,
    String keyboardType = 'text',
    String action = 'done',
    bool autocorrect = true,
    String capitalization = 'none',
    ValueChanged<String>? onTextChanged,
  }) async {
    if (isUnavailable) {
      throw MissingPluginException('Native text entry was written off by the watchdog');
    }
    // Reject a second session here rather than letting the platform answer
    // BUSY: by then this call would already have opened — and its `finally`
    // would close — the gate belonging to the session that is still on screen,
    // handing the remote back to Flutter underneath a live keyboard.
    if (_sessionActive) {
      throw PlatformException(code: busyCode, message: 'A text entry session is already active');
    }

    _sessionActive = true;
    _activeOnTextChanged = onTextChanged;
    // Synchronous, before the await: an async flag would leave a window in
    // which the keyboard is already up and Dart is still dispatching keys.
    NativeInputSession.begin();
    unawaited(GamepadService.setNativeTextInputFocused(true));
    try {
      final result = await _channel.invokeMapMethod<String, dynamic>('edit', {
        'text': text,
        'hint': hint,
        'obscure': obscure,
        'keyboardType': keyboardType,
        'action': action,
        'autocorrect': autocorrect,
        'capitalization': capitalization,
      });
      return AppleTvTextEntryResult((result?['text'] as String?) ?? text, (result?['submitted'] as bool?) ?? false);
    } on PlatformException catch (e) {
      if (e.code == deadCode || e.code == unavailableCode) {
        // Only a dead surface is written off for good: presses arrived and
        // nothing responded, which is structural. "Never came up" can just as
        // well be a backgrounded app or Siri stealing the moment, so that one
        // is retried on the next launch.
        _markUnavailable(persist: e.code == deadCode);
      }
      rethrow;
    } finally {
      _sessionActive = false;
      _activeOnTextChanged = null;
      NativeInputSession.end();
      unawaited(GamepadService.setNativeTextInputFocused(false));
    }
  }
}
