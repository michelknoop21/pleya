import 'apple_audio_session_service.dart';

/// What the user asked for. [auto] is the default and lets the route decide.
enum AudioOutputMode {
  /// Follow the route: bitstream Dolby where the far end can decode it,
  /// multichannel PCM where the route is wide enough, stereo otherwise.
  auto,

  /// Always bitstream when the codec allows it. For receivers that report
  /// their capabilities badly enough that [auto] gives up on them.
  passthrough,

  /// Never bitstream. Keeps mpv decoding, which is what filters (loudness
  /// normalization, downmix) and non-1.0 playback rates need.
  pcm,
}

/// What playback should actually do.
enum AudioOutputDecision {
  /// Hand the compressed stream to the system/receiver untouched. The only
  /// path that preserves Dolby Atmos: the JOC objects survive because nothing
  /// decodes and downmixes them on the way out.
  passthrough,

  /// mpv decodes and outputs more than two channels; the system spatializes.
  pcmMultichannel,

  /// mpv decodes down to stereo.
  pcmStereo,
}

/// Codecs the Apple system decoder accepts as a bitstream. DTS and TrueHD are
/// absent because it cannot decode them — the same limit other Apple clients
/// hit; those titles take the multichannel-PCM path instead.
const appleBitstreamCodecs = {'ac3', 'eac3'};

/// Desktop does real device passthrough, so the receiver decides — the full
/// list mpv is configured with there.
const desktopBitstreamCodecs = {'ac3', 'eac3', 'dts', 'dtshd', 'truehd'};

/// Normalizes the codec spellings the two backends and mpv each use
/// (`EAC3`, `ec-3`, `E-AC-3`, `a52`, `DTS-HD MA`, …) to a single token.
String? normalizeAudioCodec(String? codec) {
  if (codec == null || codec.trim().isEmpty) return null;
  final normalized = codec.toLowerCase().replaceAll(RegExp(r'[\s_-]'), '');
  if (normalized.startsWith('truehd') || normalized.startsWith('mlp')) return 'truehd';
  if (normalized.startsWith('dtshd') || normalized.startsWith('dtsma') || normalized.startsWith('dtsx')) {
    return 'dtshd';
  }
  // `dca` is what both backends and ffmpeg call plain DTS; missing it would
  // quietly drop desktop DTS passthrough. See CodecUtils.formatAudioCodec,
  // which maps the same alias.
  if (normalized.startsWith('dts') || normalized == 'dca') return 'dts';
  return switch (normalized) {
    'eac3' || 'ec3' || 'ddplus' || 'ddp' || 'dolbydigitalplus' => 'eac3',
    'ac3' || 'a52' || 'dd' || 'dolbydigital' => 'ac3',
    _ => normalized,
  };
}

/// Picks the audio output path for one track on one route.
///
/// Pure and side-effect free so the matrix of mode × route × codec can be
/// tested without a device.
///
/// Off Apple platforms callers pass [AppleAudioRoute.unknown], which reports
/// stereo and no spatial support. [auto] then resolves to [pcmStereo] — the
/// same thing those platforms did before this setting existed, so desktop and
/// Android TV keep their behaviour unless the user explicitly picks
/// [AudioOutputMode.passthrough].
AudioOutputDecision decideAudioOutput({
  required AudioOutputMode mode,
  required AppleAudioRoute route,
  required String? audioCodec,
  Set<String> bitstreamCodecs = appleBitstreamCodecs,
}) {
  final codec = normalizeAudioCodec(audioCodec);
  final knownBitstreamable = codec != null && bitstreamCodecs.contains(codec);

  final pcm = route.isMultichannelCapable ? AudioOutputDecision.pcmMultichannel : AudioOutputDecision.pcmStereo;

  return switch (mode) {
    AudioOutputMode.pcm => pcm,
    // An explicit request wins even when the codec is unreported: mpv's own
    // `audio-spdif` list still gates it per track, so this only forfeits the
    // one case where we could have known better. Silently ignoring the setting
    // because metadata was missing would be worse.
    AudioOutputMode.passthrough => knownBitstreamable || codec == null ? AudioOutputDecision.passthrough : pcm,
    // Bitstreaming beats PCM spatialization when both are on the table: real
    // Atmos keeps its height objects, where a decoded-then-respatialized mix
    // has already lost them. Unknown codecs stay on PCM here — auto should
    // never guess its way into a silent track.
    AudioOutputMode.auto =>
      knownBitstreamable && (route.isDigitalPassthroughPort || route.spatialAudioEnabled)
          ? AudioOutputDecision.passthrough
          : pcm,
  };
}
