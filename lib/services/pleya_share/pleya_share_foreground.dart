import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/app_logger.dart';

/// Bridge to the native keepalive that keeps the process (and thus the Dart
/// HTTP server) alive while the app is backgrounded. Android: a foreground
/// service with a persistent notification, partial wakelock, and high-perf
/// wifi lock. iOS: a silent audio loop under the background-audio
/// entitlement, so a hosting iPhone keeps serving guests when it locks.
/// No-op elsewhere (desktop doesn't suspend backgrounded apps).
class PleyaShareForeground {
  PleyaShareForeground._();

  static const _channel = MethodChannel('com.pleya/share_service');

  static bool get _supported => Platform.isAndroid || Platform.isIOS;

  static Future<void> start({required String title, required String text}) async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('start', {'title': title, 'text': text});
    } catch (e) {
      appLogger.w('PleyaShare: foreground service start failed', error: e);
    }
  }

  static Future<void> stop() async {
    if (!_supported) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      appLogger.w('PleyaShare: foreground service stop failed', error: e);
    }
  }
}
