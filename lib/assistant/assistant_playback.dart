import 'assistant_spoiler_context.dart';
import 'dart:async';

import '../mpv/mpv.dart';
import '../services/playback_stream_evidence.dart';
import '../widgets/video_controls/widgets/performance_overlay/performance_stats.dart';

enum AssistantPlaybackActionKind { audio, subtitle, version, quality }

/// Advances on each observed track-state change, including A → B → A. The
/// signature remains private because external-track IDs may carry credentials.
class AssistantPlaybackRevision {
  Object? _previous;
  int _revision = 0;
  int get value => _revision;
  void invalidate() => _revision++;
  void observe(Object signature) {
    if (signature == _previous) return;
    _previous = signature;
    _revision++;
  }

  /// Watch actual native changes, including events whose final selection
  /// matches the original one. Disposal closes queued predecessor events.
  void Function() bind(Player player, {required bool Function() isCurrent}) {
    var active = true;
    var track = player.state.track;
    var tracks = player.state.tracks;
    observe((player, track, tracks));
    final selection = player.streams.track.listen((value) {
      if (!active || !isCurrent()) return;
      track = value;
      observe((player, track, tracks));
    });
    final available = player.streams.tracks.listen((value) {
      if (!active || !isCurrent()) return;
      tracks = value;
      observe((player, track, tracks));
    });
    final backend = player.streams.backendSwitched.listen((_) {
      if (active && isCurrent()) invalidate();
    });
    return () {
      active = false;
      selection.cancel();
      available.cancel();
      backend.cancel();
    };
  }
}

class AssistantPlaybackTrack {
  const AssistantPlaybackTrack({required this.index, this.language, this.codec, this.selected = false});
  final int index;
  final String? language;
  final String? codec;
  final bool selected;
  Map<String, Object?> toJson() => {
    'index': index,
    'language': playbackSafeLabel(language),
    'codec': playbackCodec(codec),
    'selected': selected,
  };
}

/// A complete existing player action, never an instruction or arbitrary ID.
class AssistantPlaybackAction {
  const AssistantPlaybackAction({required this.kind, required this.label, required this.execute});
  final AssistantPlaybackActionKind kind;
  final String label;
  final Future<bool> Function(bool Function() isTaskCurrent) execute;
}

/// The existing native track selection followed by its preference callback.
/// The live predicate is checked again across the native await and is also
/// passed into persistence, whose own leading awaits must stay in this scope.
Future<bool> assistantSelectPlaybackTrack({
  required Player player,
  required AssistantPlaybackRevision revisions,
  required Future<void> Function() select,
  required Future<void> Function(bool Function()) persist,
  required bool Function() isCurrent,
  required bool Function() selectionMatches,
}) async {
  if (!isCurrent()) return false;
  final observed = Completer<bool>();
  int? selectedRevision;
  void capture() {
    if (observed.isCompleted) return;
    if (!isCurrent()) {
      observed.complete(false);
    } else if (selectionMatches()) {
      revisions.observe((player, player.state.track, player.state.tracks));
      selectedRevision = revisions.value;
      observed.complete(true);
    }
  }

  // Property acknowledgement can precede the native observed-track event.
  // Subscribe before issuing the selection so neither ordering loses it.
  final subscription = player.streams.track.listen(
    (_) => capture(),
    onDone: () {
      if (!observed.isCompleted) observed.complete(false);
    },
    onError: (Object _, StackTrace _) {
      if (!observed.isCompleted) observed.complete(false);
    },
  );
  try {
    await select();
    if (!isCurrent()) return false;
    capture();
    if (!await observed.future.timeout(const Duration(seconds: 2), onTimeout: () => false)) return false;
    bool stillSelected() => isCurrent() && selectionMatches() && revisions.value == selectedRevision;
    if (!stillSelected()) return false;
    await persist(stillSelected);
    return stillSelected();
  } finally {
    await subscription.cancel();
  }
}

/// Plex's existing source-subtitle route represents off with stream ID 0.
/// IDs remain closure-only; only these registered option labels are shown.
List<AssistantPlaybackAction> assistantSourceSubtitleActions({
  required List<int> streamIds,
  required int? selectedId,
  required bool Function() isCurrent,
  required Future<bool> Function(int, bool Function()) switchSource,
}) => [
  for (final (index, id) in [0, ...streamIds.where((id) => id != 0)].indexed)
    if (id != selectedId)
      AssistantPlaybackAction(
        kind: AssistantPlaybackActionKind.subtitle,
        label: index == 0 ? 'Source subtitles off' : 'Source subtitle $index',
        execute: (taskCurrent) async {
          if (!taskCurrent() || !isCurrent()) return false;
          return switchSource(id, taskCurrent);
        },
      ),
];

/// The player owns these callbacks. Its scoped registration lease and live
/// predicate close old/profile/hidden-source sessions without a new registry.
class AssistantPlaybackServices {
  const AssistantPlaybackServices({
    required this.available,
    required this.sample,
    required this.isCurrent,
    this.watchBoundary,
    this.boundaryCurrent,
  });
  const AssistantPlaybackServices.unavailable()
    : available = _unavailable,
      sample = _noSample,
      isCurrent = _notCurrent,
      watchBoundary = null,
      boundaryCurrent = null;
  static bool _unavailable() => false;
  static Future<AssistantPlaybackSnapshot?> _noSample() async => null;
  static bool _notCurrent(AssistantPlaybackSnapshot _) => false;
  final bool Function() available;
  final Future<AssistantPlaybackSnapshot?> Function() sample;
  final bool Function(AssistantPlaybackSnapshot) isCurrent;
  final AssistantWatchBoundary? Function()? watchBoundary;
  final bool Function(AssistantWatchBoundary)? boundaryCurrent;
}

/// Allowlisted fields only: never holds a URL, header, raw response or server
/// session credential. Actions stay in memory and never enter model context.
class AssistantPlaybackSnapshot {
  AssistantPlaybackSnapshot({
    required this.sessionId,
    required this.revision,
    this.playMethod,
    this.isTranscoding = false,
    this.isOffline = false,
    this.streamEvidence = const PlaybackStreamEvidence(),
    this.sourceVideoCodec,
    this.sourceAudioCodec,
    this.sourceSubtitleCodec,
    this.mediaIndex,
    this.quality,
    this.audioTrack,
    this.subtitleTrack,
    this.stats,
    List<AssistantPlaybackTrack> audioTracks = const [],
    List<AssistantPlaybackTrack> subtitleTracks = const [],
    List<AssistantPlaybackAction> actions = const [],
  }) : actions = List.unmodifiable(actions),
       audioTracks = List.unmodifiable(audioTracks),
       subtitleTracks = List.unmodifiable(subtitleTracks);

  final String sessionId;
  final String revision;
  final String? playMethod;
  final bool isTranscoding;
  final bool isOffline;
  final PlaybackStreamEvidence streamEvidence;
  final String? sourceVideoCodec;
  final String? sourceAudioCodec;
  final String? sourceSubtitleCodec;
  final int? mediaIndex;
  final String? quality;
  final int? audioTrack;
  final int? subtitleTrack;
  final PerformanceStats? stats;
  final List<AssistantPlaybackAction> actions;
  final List<AssistantPlaybackTrack> audioTracks;
  final List<AssistantPlaybackTrack> subtitleTracks;

  Map<String, Object?> diagnose() {
    final method = switch (playMethod) {
      'DirectPlay' || 'DirectStream' || 'Transcode' => playMethod,
      _ => null,
    };
    final direct = method == 'DirectPlay';
    bool? transcode(PlaybackStreamDecision? decision) => direct
        ? false
        : decision == null
        ? null
        : decision == PlaybackStreamDecision.transcode;
    final video = transcode(streamEvidence.video);
    final audio = transcode(streamEvidence.audio);
    final burn = direct
        ? false
        : switch (streamEvidence.subtitle) {
            PlaybackSubtitleDecision.burn => true,
            PlaybackSubtitleDecision.copy => false,
            null => null,
          };
    final observedVideo = playbackCodec(stats?.videoCodec);
    final observedAudio = playbackCodec(stats?.audioCodec);
    return {
      'session_id': sessionId,
      'revision': revision,
      'play_method': method,
      'transcoding_stream': isTranscoding,
      'offline': isOffline,
      'video_transcode': video,
      'audio_transcode': audio,
      'subtitle_burn_in': burn,
      'source_video_codec': playbackCodec(sourceVideoCodec),
      'source_audio_codec': playbackCodec(sourceAudioCodec),
      'source_subtitle_codec': playbackCodec(sourceSubtitleCodec),
      'observed_video_codec': observedVideo,
      'observed_audio_codec': observedAudio,
      'version_index': mediaIndex,
      'quality': playbackSafeLabel(quality),
      'audio_track_index': audioTrack,
      'subtitle_track_index': subtitleTrack,
      'audio_tracks': [for (final track in audioTracks) track.toJson()],
      'subtitle_tracks': [for (final track in subtitleTracks) track.toJson()],
      'player': switch (stats?.playerType) {
        'mpv' || 'exoplayer' => stats!.playerType,
        _ => null,
      },
      'hardware_decoder': playbackSafeLabel(stats?.hwdecCurrent),
      'audio_output': playbackSafeLabel(stats?.currentAo),
      'audio_output_format': playbackSafeLabel(stats?.audioOutFormat),
      'cache_seconds': stats?.cacheDuration,
      'cache_bytes_per_second': stats?.cacheSpeed,
      'dropped_frames': stats?.frameDropCount,
      'decoder_dropped_frames': stats?.decoderFrameDropCount,
      'unknowns': [
        if (method == null) 'play_method',
        if (video == null) 'video_transcode',
        if (audio == null) 'audio_transcode',
        if (burn == null) 'subtitle_burn_in',
        if (observedVideo == null) 'observed_video_codec',
        if (observedAudio == null) 'observed_audio_codec',
        'transcode_cause',
        'network_cause',
      ],
      'evidence_scope': 'current_playback_only; source metadata is not observed decoder output; no inferred causes',
    };
  }
}

/// Technical labels only, never server-provided title/path/URL text.
String? playbackSafeLabel(String? value) {
  if (value == null || !RegExp(r'^[a-zA-Z0-9 ._+()/-]{1,64}$').hasMatch(value) || value.contains('//')) return null;
  return value;
}

String? playbackCodec(String? value) => switch (value?.toLowerCase().replaceAll(RegExp(r'[. -]'), '')) {
  'hevc' || 'h265' => 'HEVC',
  'h264' || 'avc' || 'avc1' => 'H.264',
  'av1' => 'AV1',
  'vp9' => 'VP9',
  'mpeg2video' || 'mpeg2' => 'MPEG-2',
  'aac' => 'AAC',
  'ac3' => 'AC3',
  'eac3' => 'EAC3',
  'dts' || 'dca' => 'DTS',
  'truehd' => 'TrueHD',
  'flac' => 'FLAC',
  'opus' => 'Opus',
  'mp3' => 'MP3',
  'pgs' || 'hdmvpgssubtitle' => 'PGS',
  'subrip' || 'srt' => 'SRT',
  'ass' || 'ssa' => 'ASS',
  'webvtt' || 'vtt' => 'WebVTT',
  'dvdsubtitle' || 'vobsub' => 'VobSub',
  _ => null,
};
