import 'dart:io' show Platform;

import 'package:flutter/services.dart';

import '../utils/app_logger.dart';

/// Presents the native iOS AirPlay route picker (`AVRoutePickerView`). iOS only;
/// tvOS/macOS route audio/video through the system already and desktop has no
/// equivalent, so [isAvailable] is false there.
class AirPlayService {
  static const MethodChannel _channel = MethodChannel('com.pleya/airplay');

  static bool get isAvailable => Platform.isIOS;

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
