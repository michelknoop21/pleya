import 'dart:async';
import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';

/// Voice input for search, implemented per platform against native APIs rather
/// than a pub package — there is no Flutter speech plugin that covers tvOS,
/// which is exactly the platform that needs this most.
///
/// * **tvOS** reuses the existing `com.pleya/native_text_entry` channel. Its
///   `UIAlertController` text field gets Siri dictation and "type with your
///   iPhone" for free from the system, with no permissions to request.
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
  SpeechSearchService({MethodChannel? speechChannel, MethodChannel? textEntryChannel})
    : _speech = speechChannel ?? const MethodChannel('com.pleya/speech'),
      _textEntry = textEntryChannel ?? const MethodChannel('com.pleya/native_text_entry');

  static final SpeechSearchService instance = SpeechSearchService();

  final MethodChannel _speech;
  final MethodChannel _textEntry;

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
      // registered at all, dictation is available.
      supported = true;
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
  Future<String?> capture({String? prompt}) async {
    if (!await isSupported()) return null;

    if (PlatformDetector.isAppleTV()) {
      final result = await _invoke<Map<Object?, Object?>>(_textEntry, 'edit', {
        'text': '',
        'hint': prompt,
        'obscure': false,
        'keyboardType': 'text',
        'action': 'search',
        'autocorrect': true,
        'capitalization': 'none',
      });
      final text = (result?['text'] as String?)?.trim();
      return (text == null || text.isEmpty) ? null : text;
    }

    final spoken = (await _invoke<String>(_speech, 'capture', {'prompt': prompt}))?.trim();
    return (spoken == null || spoken.isEmpty) ? null : spoken;
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
