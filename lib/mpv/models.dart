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

/// The two independent loudness choices and the mpv filter chain they make.
///
/// The numbers are measured, not chosen. On a 120-second dialogue excerpt of an
/// E-AC-3 Atmos title (dialnorm -27), decoded with dialnorm honoured, the
/// levelling chain lands between -22,2 and -23,1 LUFS across AC-3 and E-AC-3
/// and across dialnorm -27 and -28, with the true peak always at -2,0 dBFS.
/// That target is EBU R128, the level broadcasters are held to, so Pleya ends
/// up where the rest of the television is instead of 5 dB above it — where the
/// old `I=-14` put it — or 7 dB below it, where an untouched Dolby bitstream
/// sits.
class AudioLoudness {
  const AudioLoudness({this.levelVolume = false, this.reduceLoudSounds = false});

  /// Bring every title to the same average level.
  final bool levelVolume;

  /// Narrow the gap between dialogue and loud effects.
  final bool reduceLoudSounds;

  static const none = AudioLoudness();

  /// mpv `af` chain ('' disables filtering).
  ///
  /// [reduceLoudSounds] only does anything alongside [levelVolume], and that is
  /// a measurement result rather than a simplification: a compressor with
  /// makeup gain and no loudness target ran the same excerpt up to +5,4 dBFS —
  /// clipping — while leaving the loudness range where it started. Reducing
  /// dynamics is only safe once something is holding the level.
  String get mpvFilter {
    if (!levelVolume) return '';
    if (!reduceLoudSounds) return 'loudnorm=I=-22:TP=-2:LRA=9';
    // `LRA` alone barely moves single-pass loudnorm (10,2 against 8,5 LU), so
    // the compressor ahead of it is what actually narrows the range: 10,2 down
    // to 6,4 LU at the same -22,5 LUFS.
    return 'acompressor=threshold=-38dB:ratio=8:attack=5:release=250,loudnorm=I=-22:TP=-2:LRA=3';
  }

  /// Whether any loudness filtering is active. Android's native effect is
  /// on/off only, so both switches collapse to this one bit there.
  bool get isEnabled => levelVolume;

  @override
  bool operator ==(Object other) =>
      other is AudioLoudness && other.levelVolume == levelVolume && other.reduceLoudSounds == reduceLoudSounds;

  @override
  int get hashCode => Object.hash(levelVolume, reduceLoudSounds);

  @override
  String toString() => 'AudioLoudness(level: $levelVolume, reduceLoud: $reduceLoudSounds)';
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
