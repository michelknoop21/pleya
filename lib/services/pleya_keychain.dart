import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';

/// Small strings in the iCloud keychain (`shared/apple/Keychain`), shared by
/// the user's iPhone, iPad and Apple TV. A missing item reads as null; every
/// other keychain failure throws, so a caller never mistakes an error for
/// "nothing stored".
///
/// [PleyaKeychain.deviceOnly] keeps its items out of iCloud: they stay in the
/// keychain of this device and are not part of a backup to another one.
class PleyaKeychain {
  const PleyaKeychain([this._channel = const MethodChannel('com.pleya/keychain')]) : _deviceOnly = false;
  const PleyaKeychain.deviceOnly([this._channel = const MethodChannel('com.pleya/keychain')]) : _deviceOnly = true;

  final MethodChannel _channel;
  final bool _deviceOnly;

  // The synced keychain sends no scope, as it did before the scope existed.
  Map<String, Object?> _args(String key, [String? value]) => {
    'key': key,
    'value': ?value,
    if (_deviceOnly) 'scope': 'device',
  };

  /// Test-only override; nothing in the app sets this.
  static bool debugForceSupported = false;

  /// iOS and tvOS register the channel; every other platform keeps its own
  /// storage.
  static bool get supported => debugForceSupported || (!kIsWeb && (Platform.isIOS || PlatformDetector.isAppleTV()));

  Future<String?> read(String key) => _channel.invokeMethod<String>('read', _args(key));

  /// True once the keychain accepted [value].
  Future<bool> write(String key, String value) async =>
      await _channel.invokeMethod<bool>('write', _args(key, value)) ?? false;

  Future<void> delete(String key) => _channel.invokeMethod<void>('delete', _args(key));
}
