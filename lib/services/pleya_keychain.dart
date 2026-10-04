import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';

/// Small strings in the iCloud keychain (`shared/apple/Keychain`), shared by
/// the user's iPhone, iPad and Apple TV. A missing item reads as null; every
/// other keychain failure throws, so a caller never mistakes an error for
/// "nothing stored".
class PleyaKeychain {
  const PleyaKeychain([this._channel = const MethodChannel('com.pleya/keychain')]);

  final MethodChannel _channel;

  /// Test-only override; nothing in the app sets this.
  static bool debugForceSupported = false;

  /// iOS and tvOS register the channel; every other platform keeps its own
  /// storage.
  static bool get supported => debugForceSupported || (!kIsWeb && (Platform.isIOS || PlatformDetector.isAppleTV()));

  Future<String?> read(String key) => _channel.invokeMethod<String>('read', {'key': key});

  /// True once the keychain accepted [value].
  Future<bool> write(String key, String value) async =>
      await _channel.invokeMethod<bool>('write', {'key': key, 'value': value}) ?? false;

  Future<void> delete(String key) => _channel.invokeMethod<void>('delete', {'key': key});
}
