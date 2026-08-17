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

/// Which of two incompatible properties [AudioOutputMode.auto] should protect.
///
/// They are incompatible because of where the levels sit, not because of taste.
/// A film mix puts dialogue around -30 LUFS with peaks near full scale, which is
/// cinema reference level and roughly 7 dB below what broadcast television is
/// held to. Lifting the dialogue to television level therefore means narrowing
/// the range, and on a compressed bitstream it cannot be done at all. So this is
/// a real choice: match the rest of the living room, or keep the object layer.
enum AudioPriority {
  /// Decode, so the loudness stage can run and Pleya lands where the rest of
  /// the television is.
  evenVolume,

  /// Bitstream Dolby untouched where the route can carry it, and accept that
  /// the receiver decides the level.
  originalDolby,
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
  AudioPriority priority = AudioPriority.evenVolume,
  Set<String> bitstreamCodecs = appleBitstreamCodecs,
  bool bitstreamBlocked = false,
}) {
  final codec = normalizeAudioCodec(audioCodec);
  // A route where bitstreaming was tried and failed is not a route to try it
  // on again: that is how you get the same silence every episode.
  final knownBitstreamable = !bitstreamBlocked && codec != null && bitstreamCodecs.contains(codec);

  final pcm = route.isMultichannelCapable ? AudioOutputDecision.pcmMultichannel : AudioOutputDecision.pcmStereo;

  return switch (mode) {
    AudioOutputMode.pcm => pcm,
    // An explicit request wins even when the codec is unreported: mpv's own
    // `audio-spdif` list still gates it per track, so this only forfeits the
    // one case where we could have known better. Silently ignoring the setting
    // because metadata was missing would be worse.
    AudioOutputMode.passthrough =>
      !bitstreamBlocked && (knownBitstreamable || codec == null) ? AudioOutputDecision.passthrough : pcm,
    // Auto follows the priority the user set once.
    //
    // Under evenVolume it never bitstreams, which is what it has done since
    // build 211: a bitstream cannot be levelled, and levelling is the whole
    // point of that choice. It still earns its keep by widening to multichannel
    // PCM wherever the route allows.
    //
    // Under originalDolby it may bitstream again, but only on a wired digital
    // port and only for a codec we know is bitstreamable — no `codec == null`
    // leniency, unlike the explicit passthrough mode. That narrowness is the
    // lesson of build 207, where auto sent a bitstream to an Apple TV over HDMI
    // that never agreed to take one: no sound, and the player stalled on the
    // audio renderer. What is different now is evidence rather than optimism —
    // a device log shows `spdif_eac3` reaching the avfoundation sink with
    // `JOC=yes` on that same hardware — plus the build 212 safety net
    // underneath: mpv's own failure line, a stall watchdog, and a per-route
    // memory of a bitstream that did not come up.
    AudioOutputMode.auto =>
      priority == AudioPriority.originalDolby && route.isDigitalPassthroughPort && knownBitstreamable
          ? AudioOutputDecision.passthrough
          : pcm,
  };
}
