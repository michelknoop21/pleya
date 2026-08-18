import '../i18n/strings.g.dart';
import '../services/apple_audio_session_service.dart';
import '../services/audio_output_coordinator.dart';
import '../services/audio_output_decision.dart';
import 'codec_utils.dart';

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

/// The output path that was asked for, as opposed to the mode the user picked:
/// `auto` resolves to one of these before mpv sees anything.
String audioOutputDecisionLabel(AudioOutputDecision decision) => switch (decision) {
  AudioOutputDecision.passthrough => t.videoSettings.audioOutputDecisions.passthrough,
  AudioOutputDecision.pcmMultichannel => t.videoSettings.audioOutputDecisions.pcmMultichannel,
  AudioOutputDecision.pcmStereo => t.videoSettings.audioOutputDecisions.pcmStereo,
};

/// What mpv turned out to be doing, in one line.
///
/// Format first, because that is the half that settles the question: a
/// `spdif-` prefix is the only proof a bitstream is really running. A
/// passthrough that ended up decoded is marked as a fallback rather than
/// printed as plain PCM — the gap between what was asked and what happened is
/// the reason this line exists at all.
String verifiedAudioOutputLabel(VerifiedAudioOutput verified) {
  final parts = <String>[];
  if (verified.isBitstream) {
    // The format is where mpv names the codec on this route; `current-ao` only
    // ever says `avfoundation`.
    // Stripped with a pattern rather than a fixed offset. `isBitstream` only
    // tests the `spdif` prefix, so a bare `spdif` would make a slice at index 6
    // throw — inside a widget build, taking the whole overlay down mid-
    // playback. The separator is not dependable either: mpv writes
    // `spdif-eac3` on the output params and `spdif_eac3` on the decoder line.
    final codec = verified.format!.replaceFirst(RegExp(r'^spdif[-_]?'), '');
    parts.add(
      codec.isEmpty
          ? t.performanceOverlay.audioBitstream
          : '${CodecUtils.formatAudioCodec(codec)} ${t.performanceOverlay.audioBitstream}',
    );
  } else {
    parts.add(verified.channels == null ? 'PCM' : 'PCM ${verified.channels}');
    if (verified.intended == AudioOutputDecision.passthrough) {
      parts.add(t.performanceOverlay.audioFellBack);
    }
  }
  if (verified.ao != null) parts.add(verified.ao!);
  return parts.join(' · ');
}
