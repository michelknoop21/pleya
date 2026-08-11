import 'app_logger.dart';
import 'platform_detector.dart';

/// TV-only trace of the text-input path (focus, key events, gamepad). Rides on
/// the debug-logging setting: `SettingsService.enableDebugLogging` raises the
/// logger level and these lines start showing up.
class TextInputDiagnostics {
  static void log(String source, String message) {
    if (!PlatformDetector.isTV()) return;
    appLogger.d('TextInputDiag $source: $message');
  }
}
