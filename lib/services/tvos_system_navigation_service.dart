import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

import '../utils/platform_detector.dart';

class TvosSystemNavigationService {
  static const BasicMessageChannel<Object?> _channel = BasicMessageChannel<Object?>(
    'flutter/tvos_system_navigation',
    JSONMessageCodec(),
  );

  static bool? _menuPassthroughEnabled;

  static Future<void> setMenuPassthroughEnabled(bool enabled) async {
    if (!PlatformDetector.isAppleTV()) return;
    if (_menuPassthroughEnabled == enabled) return;

    _menuPassthroughEnabled = enabled;
    await _channel.send({'menuPassthroughEnabled': enabled});
  }

  /// Test-only: clears the last-sent cache so a test can assert on the next
  /// [setMenuPassthroughEnabled] call regardless of what an earlier test in
  /// the same isolate already sent (the cache is a static, so it otherwise
  /// survives across tests in one file).
  @visibleForTesting
  static void debugResetMenuPassthroughCache() {
    _menuPassthroughEnabled = null;
  }
}
