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
    // Auto never bitstreams. It used to, on the reasoning that real Atmos
    // beats a respatialized downmix — but that only holds if the far end
    // actually accepts the bitstream, and on an Apple TV over HDMI with an
    // E-AC3 track it does not: no sound, and the player stalls waiting on the
    // audio renderer. The setting this replaced said exactly that ("keep
    // opt-in everywhere, including Apple TV, until the AVFoundation EAC3 path
    // is verified across real receiver setups"), and auto switched it on
    // before that verification had happened.
    //
    // So bitstreaming stays something the user turns on deliberately, and the
    // default can only pick a path that decodes. Auto still earns its keep: it
    // widens to multichannel PCM wherever the route allows it.
    AudioOutputMode.auto => pcm,
  };
}
