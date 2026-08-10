import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/native_input_session.dart';
import 'gamepad_service.dart';

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
      } else if (call.method == 'diagnostic') {
        // Info level on purpose: debug is filtered out in release, and
        // Instellingen > Logs is the only practical way to inspect this on a
        // TV. This path cannot be exercised off-device.
        appLogger.i('NativeTextEntry: ${call.arguments}');
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
  bool _unavailable = false;

  /// Whether the native surface has been written off *for this app run*. Set by
  /// the watchdog codes so a broken surface is never shown twice in a session;
  /// every caller then takes its existing fallback.
  ///
  /// Deliberately not persisted. The watchdog can only guess from a timeout,
  /// and a false positive — Siri stealing the moment, the app backgrounded —
  /// would otherwise cost the user dictation permanently, on this device and
  /// (via settings sync) on every other one.
  bool get isUnavailable => _unavailable;

  void _markUnavailable() {
    _unavailable = true;
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
  /// Second way out of a live session, for the back key that reached Dart
  /// instead of the native escape hatch.
  ///
  /// Fire-and-forget: the session ends through the normal `edit` completion, so
  /// there is nothing to await here. Cancelling twice is harmless — the plugin
  /// drops the call once the entry is gone — and a build whose plugin predates
  /// this method simply keeps the old behaviour instead of throwing.
  void _requestCancel() {
    unawaited(
      _channel.invokeMethod<void>('cancel').catchError((Object e) {
        appLogger.d('Native text entry cancel ignored: $e');
      }),
    );
  }

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
    NativeInputSession.begin(onRequestClose: _requestCancel);
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
        _markUnavailable();
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
