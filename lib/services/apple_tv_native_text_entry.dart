import 'dart:async';

import 'package:flutter/services.dart';

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
      }
    });
  }

  static final AppleTvNativeTextEntry instance = AppleTvNativeTextEntry();

  /// Error code the plugin returns when a session is already on screen.
  static const busyCode = 'BUSY';

  final MethodChannel _channel;

  ValueChanged<String>? _activeOnTextChanged;

  /// Opens the native system-keyboard text entry (UIAlertController with a
  /// text field). While it is up, the Siri Remote mic button dictates into it
  /// and iPhone Continuity typing streams through [onTextChanged].
  ///
  /// The gamepad service is paused for the duration of the session so remote
  /// input can't leak into the Flutter UI underneath the alert.
  ///
  /// Throws [PlatformException] (including code [busyCode] when a session is
  /// already active) and [MissingPluginException] — callers own the fallback
  /// policy.
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
    _activeOnTextChanged = onTextChanged;
    // The tvOS pause() PlatformException is swallowed in gamepad_service.dart.
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
    } finally {
      _activeOnTextChanged = null;
      unawaited(GamepadService.setNativeTextInputFocused(false));
    }
  }
}
