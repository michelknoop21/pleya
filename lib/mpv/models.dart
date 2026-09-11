// ignore_for_file: invalid_annotation_target
import 'package:freezed_annotation/freezed_annotation.dart';

part 'models.freezed.dart';

@freezed
sealed class BufferRange with _$BufferRange {
  const factory BufferRange({required Duration start, required Duration end}) = _BufferRange;
}

/// [cause] is an optional machine-readable tag (e.g. `server-http-500`),
/// letting the UI branch without parsing [message].
@Freezed(toStringOverride: false)
sealed class PlayerError with _$PlayerError {
  const PlayerError._();

  const factory PlayerError(String message, {String? cause}) = _PlayerError;

  /// Cause tag for a server-side HTTP 500 — shared-user bandwidth or
  /// transcoding limit rejection set by the server owner.
  static const String serverHttp500 = 'server-http-500';

  @override
  String toString() => message;
}

enum PlayerLogLevel { none, fatal, error, warn, info, verbose, debug, trace }

/// Legacy single-axis loudness setting, superseded by [AudioLoudness].
///
/// Kept only because it is still the stored value of the `audio_normalization_mode`
/// pref, which seeds the defaults of the two switches that replaced it. It
/// carries no behaviour any more.
enum AudioNormalizationMode { off, normalize, night }

/// How the loudness stage is running.
///
/// [programme] applies one fixed gain from stored evidence and is identical on
/// every client; [realtime] is the fallback that guesses while it plays, and is
/// named that way so nobody mistakes it for the real thing.
enum LoudnessMode { off, programme, realtime }

/// The two independent loudness choices, the programme gain the planner
/// derived from evidence, and the mpv filter chain that makes of them.
///
/// The numbers are measured, not chosen; `scripts/loudness/prove.sh` renders
/// every chain here and measures it with an independent meter. The target is
/// EBU R128's -22 area, where broadcasters are held, so Pleya ends up where the
/// rest of the television is instead of 5 dB above it (the old `I=-14`) or
/// 7 dB below it (an untouched Dolby bitstream).
class AudioLoudness {
  const AudioLoudness({this.levelVolume = false, this.reduceLoudSounds = false, this.programmeGainDb});

  /// Bring every title to the same average level.
  final bool levelVolume;

  /// Narrow the gap between dialogue and loud effects.
  final bool reduceLoudSounds;

  /// The fixed gain for this programme, from stored loudness evidence, or null
  /// when there is none and levelling has to run in realtime.
  final double? programmeGainDb;

  /// Bumped whenever a chain below changes what it does to the audio, so a
  /// log or a native side can tell which version produced a level.
  static const profileVersion = 1;

  static const none = AudioLoudness();

  /// True-peak limiter at -2 dBTP: alimiter run at 192 kHz, because a
  /// sample-peak limiter let intersample peaks through at +1,6 dBTP on the ISP
  /// fixture while this one held -2,0.
  static const truePeakLimiter =
      'aresample=192000,alimiter=limit=0.7943:level=false:attack=5:release=50:latency=1,aresample=48000';

  /// Reduce-loud-sounds compressor behind a fixed gain. The threshold sits 4 dB
  /// above the target, so dialogue at programme level passes and only what is
  /// louder is pulled in; at the old -38 dB the fixtures dropped to -39 LUFS.
  static const programmeCompressor = 'acompressor=threshold=-18dB:ratio=8:attack=5:release=250:makeup=1';

  /// mpv `af` chain ('' disables filtering).
  ///
  /// Without a programme gain the realtime chains run unchanged: single-pass
  /// `loudnorm`, with the -38 dB compressor ahead of it when loud sounds are
  /// reduced (that compressor narrowed a real excerpt from 10,2 to 6,4 LU at
  /// -22,5 LUFS; `LRA` alone barely moves single-pass loudnorm). With a gain,
  /// or with only loud sounds reduced, the chain is fixed and deterministic:
  /// gain, optional compressor, true-peak limiter. The limiter is what makes
  /// reduce-only safe now; a compressor with makeup and no ceiling once ran an
  /// excerpt to +5,4 dBFS.
  String get mpvFilter {
    if (!isEnabled) return '';
    final gain = programmeGainDb;
    if (levelVolume && gain == null) {
      if (!reduceLoudSounds) return 'loudnorm=I=-22:TP=-2:LRA=9';
      return 'acompressor=threshold=-38dB:ratio=8:attack=5:release=250,loudnorm=I=-22:TP=-2:LRA=3';
    }
    return [
      if (levelVolume) 'volume=${gain!.toStringAsFixed(2)}dB:precision=float',
      if (reduceLoudSounds) programmeCompressor,
      truePeakLimiter,
    ].join(',');
  }

  /// Whether any loudness processing is active.
  bool get isEnabled => levelVolume || reduceLoudSounds;

  LoudnessMode get mode {
    if (!isEnabled) return LoudnessMode.off;
    if (levelVolume && programmeGainDb == null) return LoudnessMode.realtime;
    return LoudnessMode.programme;
  }

  @override
  bool operator ==(Object other) =>
      other is AudioLoudness &&
      other.levelVolume == levelVolume &&
      other.reduceLoudSounds == reduceLoudSounds &&
      other.programmeGainDb == programmeGainDb;

  @override
  int get hashCode => Object.hash(levelVolume, reduceLoudSounds, programmeGainDb);

  @override
  String toString() =>
      'AudioLoudness(level: $levelVolume, reduceLoud: $reduceLoudSounds, mode: ${mode.name}'
      '${programmeGainDb == null ? '' : ', gain: ${programmeGainDb!.toStringAsFixed(2)} dB'})';
}

@freezed
sealed class AudioTrack with _$AudioTrack {
  const AudioTrack._();

  const factory AudioTrack({
    required String id,
    String? title,
    String? language,
    String? codec,
    int? channels,
    int? sampleRate,
    int? bitrate,

    /// Server-reported codec profile — where Atmos actually announces itself,
    /// rather than in [codec]. Mirrors `MediaStream.profile`.
    String? profile,

    /// Server-reported channel layout, e.g. `5.1(side)`.
    String? channelLayout,
    @Default(false) bool isDefault,
    @Default(false) bool isForced,
  }) = _AudioTrack;

  static const auto = AudioTrack(id: 'auto', title: 'Auto');

  static const off = AudioTrack(id: 'no', title: 'Off');

  int? get channelsCount => channels;

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (language != null && language!.isNotEmpty) return language!;
    return 'Track $id';
  }
}

@freezed
sealed class SubtitleTrack with _$SubtitleTrack {
  const SubtitleTrack._();

  const factory SubtitleTrack({
    required String id,
    String? title,
    String? language,
    String? codec,
    @Default(false) bool isDefault,
    @Default(false) bool isForced,
    @Default(false) bool isExternal,
    String? uri,
  }) = _SubtitleTrack;

  factory SubtitleTrack.uri(
    String uri, {
    String? title,
    String? language,
    String? codec,
    bool isDefault = false,
    bool isForced = false,
  }) => SubtitleTrack(
    id: 'external:$uri',
    title: title,
    language: language,
    codec: codec,
    isDefault: isDefault,
    isForced: isForced,
    isExternal: true,
    uri: uri,
  );

  static const auto = SubtitleTrack(id: 'auto', title: 'Auto');

  static const off = SubtitleTrack(id: 'no', title: 'Off');

  String get displayName {
    if (title != null && title!.isNotEmpty) return title!;
    if (language != null && language!.isNotEmpty) return language!;
    if (isExternal) return 'External';
    return 'Track $id';
  }
}

@Freezed(toStringOverride: false)
sealed class Tracks with _$Tracks {
  const Tracks._();

  const factory Tracks({
    @Default(<AudioTrack>[]) List<AudioTrack> audio,
    @Default(<SubtitleTrack>[]) List<SubtitleTrack> subtitle,
  }) = _Tracks;

  @override
  String toString() => 'Tracks(audio: ${audio.length}, subtitle: ${subtitle.length})';
}

@freezed
sealed class TrackSelection with _$TrackSelection {
  const factory TrackSelection({AudioTrack? audio, SubtitleTrack? subtitle, SubtitleTrack? secondarySubtitle}) =
      _TrackSelection;
}

@freezed
sealed class AudioDevice with _$AudioDevice {
  const factory AudioDevice({required String name, @Default('') String description}) = _AudioDevice;

  static const auto = AudioDevice(name: 'auto', description: 'Auto');
}

@Freezed(toStringOverride: false)
sealed class PlayerLog with _$PlayerLog {
  const PlayerLog._();

  const factory PlayerLog({required PlayerLogLevel level, required String prefix, required String text}) = _PlayerLog;

  @override
  String toString() => '[$prefix] ${level.name}: $text';
}

@freezed
sealed class Media with _$Media {
  const factory Media(String uri, {Map<String, String>? headers, Duration? start}) = _Media;
}
