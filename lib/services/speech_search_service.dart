import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'apple_tv_native_text_entry.dart';

/// What a voice/dictation session produced: the final text plus whether the
/// user explicitly submitted (Done/Search) rather than cancelling out.
typedef SpeechCaptureResult = ({String text, bool submitted});

/// Voice input for search, implemented per platform against native APIs rather
/// than a pub package — there is no Flutter speech plugin that covers tvOS,
/// which is exactly the platform that needs this most.
///
/// * **tvOS** reuses the existing `com.pleya/native_text_entry` channel. Its
///   text field raises the system keyboard, which gets Siri Remote dictation
///   and "type with your iPhone" for free, with no permissions to request.
/// * **Android (incl. Android TV)** uses `com.pleya/speech`, which fires the
///   system `RecognizerIntent`. That is an activity result, so no
///   `RECORD_AUDIO` permission is involved.
/// * **Everything else** reports [isSupported] as false. Phones and desktops
///   already have a dictation key on the system keyboard.
///
/// Every native call degrades to "unsupported" on [MissingPluginException],
/// so a build without the plugin registered (tests, other embedders) simply
/// hides the button instead of throwing.
class SpeechSearchService {
  SpeechSearchService({MethodChannel? speechChannel, AppleTvNativeTextEntry? textEntry})
    : _speech = speechChannel ?? const MethodChannel('com.pleya/speech'),
      _textEntry = textEntry;

  static final SpeechSearchService instance = SpeechSearchService();

  final MethodChannel _speech;
  final AppleTvNativeTextEntry? _textEntry;

  AppleTvNativeTextEntry get _nativeEntry => _textEntry ?? AppleTvNativeTextEntry.instance;

  bool? _cachedSupport;
  final _externalQueries = StreamController<String>.broadcast();
  bool _listening = false;

  /// Queries handed to the app from outside: the Android Assistant or the
  /// Android TV global-search row (`ACTION_SEARCH`). Subscribe once at app
  /// level and route into the search tab.
  Stream<String> get externalQueries => _externalQueries.stream;

  /// Starts listening for `ACTION_SEARCH` hand-offs and replays one that
  /// arrived before Dart was ready (cold launch from the Assistant).
  Future<void> startListeningForSearchIntents() async {
    if (_listening || !Platform.isAndroid) return;
    _listening = true;
    _speech.setMethodCallHandler((call) async {
      if (call.method == 'onSearchIntent') {
        final query = (call.arguments as String?)?.trim();
        if (query != null && query.isNotEmpty) _externalQueries.add(query);
      }
      return null;
    });
    final pending = (await _invoke<String>(_speech, 'drainPendingSearchIntent'))?.trim();
    if (pending != null && pending.isNotEmpty) _externalQueries.add(pending);
  }

  /// Whether a mic affordance should be offered at all. Cached after the first
  /// probe — the answer cannot change within a session.
  Future<bool> isSupported() async {
    final cached = _cachedSupport;
    if (cached != null) return cached;

    bool supported;
    if (PlatformDetector.isAppleTV()) {
      // The native text-entry plugin is the dictation surface here; if it is
      // registered and hasn't been written off by the watchdog, dictation is
      // available.
      supported = !_nativeEntry.isUnavailable;
    } else if (Platform.isAndroid) {
      supported = await _invoke<bool>(_speech, 'isSupported') ?? false;
    } else {
      supported = false;
    }
    _cachedSupport = supported;
    return supported;
  }

  /// Opens the platform's voice/dictation surface and returns what the user
  /// said. Returns `null` when they cancelled, said nothing, or the platform
  /// could not deliver — callers should simply do nothing in that case.
  ///
  /// On Apple TV the surface is the native system-keyboard alert: it is opened
  /// prefilled with [initialText] (dictation continues a query instead of
  /// restarting it) and streams every keystroke/dictated word through
  /// [onPartial] while the session is up, so a caller can run its live search
  /// during dictation. [SpeechCaptureResult.submitted] distinguishes an
  /// explicit Done/Search from cancelling out with text still in the field.
  Future<SpeechCaptureResult?> capture({
    String? prompt,
    String initialText = '',
    ValueChanged<String>? onPartial,
  }) async {
    if (!await isSupported()) return null;

    if (PlatformDetector.isAppleTV()) {
      try {
        final result = await _nativeEntry.edit(
          text: initialText,
          hint: prompt,
          action: 'search',
          onTextChanged: onPartial,
        );
        final text = result.text.trim();
        if (text.isEmpty) return null;
        return (text: text, submitted: result.submitted);
      } on MissingPluginException {
        _cachedSupport = false;
        return null;
      } on PlatformException catch (e) {
        if (e.code == AppleTvNativeTextEntry.busyCode) {
          // A session is already on screen — nothing to do.
          appLogger.d('Speech search: native edit busy', error: e);
          return null;
        }
        // Anything else means the surface failed, including the watchdog codes
        // for one that never became usable. Let the caller fall back rather
        // than silently doing nothing — that is how the dead dialog used to
        // look like a hang.
        _cachedSupport = false;
        appLogger.w('Speech search: native edit failed', error: e);
        rethrow;
      }
    }

    final spoken = (await _invoke<String>(_speech, 'capture', {'prompt': prompt}))?.trim();
    if (spoken == null || spoken.isEmpty) return null;
    return (text: spoken, submitted: true);
  }

  Future<T?> _invoke<T>(MethodChannel channel, String method, [Object? arguments]) async {
    try {
      return await channel.invokeMethod<T>(method, arguments);
    } on MissingPluginException {
      // Not registered on this embedder — treat as "no voice input here".
      _cachedSupport = false;
      return null;
    } on PlatformException catch (e) {
      appLogger.d('Speech search: $method failed', error: e);
      return null;
    }
  }
}
