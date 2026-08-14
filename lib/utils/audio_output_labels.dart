import '../i18n/strings.g.dart';
import '../services/apple_audio_session_service.dart';

/// Human label for what the system reports it is actually rendering.
///
/// Null when there is nothing worth showing: the route can't report a mode, or
/// the OS predates `AVAudioSession.renderingMode` (iOS/tvOS 17.2). Callers
/// hide the badge rather than print a placeholder — an empty spot reads better
/// than "Unknown" next to a track name.
String? audioRenderingLabel(AppleRenderingMode mode) => switch (mode) {
  AppleRenderingMode.monoStereo => t.videoSettings.audioOutputRendering.monoStereo,
  AppleRenderingMode.surround => t.videoSettings.audioOutputRendering.surround,
  AppleRenderingMode.spatialAudio => t.videoSettings.audioOutputRendering.spatialAudio,
  AppleRenderingMode.dolbyAudio => t.videoSettings.audioOutputRendering.dolbyAudio,
  AppleRenderingMode.dolbyAtmos => t.videoSettings.audioOutputRendering.dolbyAtmos,
  AppleRenderingMode.notApplicable || AppleRenderingMode.unknown => null,
};
