import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';

/// Presents the native iOS AirPlay route picker (`AVRoutePickerView`). iOS only;
/// tvOS/macOS route audio/video through the system already and desktop has no
/// equivalent, so [isAvailable] is false there. Flutter reports Apple TV as iOS,
/// so tvOS is excluded explicitly.
class AirPlayService {
  static const MethodChannel _channel = MethodChannel('com.pleya/airplay');

  /// Test seam: forces [isAvailable] on hosts that are not an iPhone.
  @visibleForTesting
  static bool? debugAvailableOverride;

  static bool get isAvailable => debugAvailableOverride ?? (Platform.isIOS && !PlatformDetector.isAppleTV());

  /// Opens the system AirPlay picker. No-op (returns false) off iOS.
  static Future<bool> showRoutePicker() async {
    if (!isAvailable) return false;
    try {
      final result = await _channel.invokeMethod<bool>('showRoutePicker');
      return result ?? false;
    } on PlatformException catch (e) {
      appLogger.w('AirPlay route picker failed: ${e.code} ${e.message}');
      return false;
    }
  }
}
