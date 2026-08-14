import 'app_logger.dart';
import 'platform_detector.dart';

/// TV-only trace of the text-input path (focus, key events, gamepad). Rides on
/// the debug-logging setting: `SettingsService.enableDebugLogging` raises the
/// logger level and these lines start showing up.
class TextInputDiagnostics {
  /// [highFrequency] marks lines that fire per streamed input sample (analog
  /// axis drift, touch moves). Those go to trace so a resting thumbstick
  /// doesn't push the focus and key transitions out of the log buffer.
  static void log(String source, String message, {bool highFrequency = false}) {
    if (!PlatformDetector.isTV()) return;
    final line = 'TextInputDiag $source: $message';
    highFrequency ? appLogger.t(line) : appLogger.d(line);
  }
}
