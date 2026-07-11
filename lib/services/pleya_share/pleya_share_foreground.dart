import 'dart:io';

import 'package:flutter/services.dart';

import '../../utils/app_logger.dart';

/// Android-only bridge to the native foreground service that keeps the
/// process (and thus the Dart HTTP server) alive while the app is
/// backgrounded — with a persistent notification, a partial wakelock, and a
/// high-perf wifi lock. No-op on every other platform (iOS suspends
/// backgrounded apps regardless; there the host screen stays open).
class PleyaShareForeground {
  PleyaShareForeground._();

  static const _channel = MethodChannel('com.pleya/share_service');

  static Future<void> start({required String title, required String text}) async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start', {'title': title, 'text': text});
    } catch (e) {
      appLogger.w('PleyaShare: foreground service start failed', error: e);
    }
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (e) {
      appLogger.w('PleyaShare: foreground service stop failed', error: e);
    }
  }
}
