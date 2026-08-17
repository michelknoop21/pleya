/// Models for `get_activity`, shaped after captures of a live Tautulli
/// v2.17.2. See `test/fixtures/tautulli/README.md` for what each capture
/// showed.
///
/// A session row carries 247 fields, most of which are library metadata the app
/// already has from Plex. What is kept here is what a server admin cannot see
/// anywhere else: who is streaming, on what, how far in, and what the server is
/// doing to the file to make it play.
///
/// Deliberately dropped, and not to be added later: `ip_address`,
/// `ip_address_public`, `machine_id`, `email`, `file` and `file_size`. The
/// first four identify a person or a device beyond what this feature needs, and
/// the last two expose the server's filesystem layout to every screen that
/// renders a session.
library;

import 'tautulli_json.dart';

/// What the server is doing to a stream, from `transcode_decision`.
///
/// The measured values are `direct play`, `copy` and `transcode`. Tautulli
/// derives it from `video_decision` and `audio_decision`: `copy` means the
/// container is being remuxed while both codecs pass through, which Plex's own
/// UI calls "direct stream".
enum TautulliDecision {
  directPlay,
  directStream,
  transcode;

  static TautulliDecision fromWire(String? raw) => switch (raw?.toLowerCase()) {
    'transcode' => TautulliDecision.transcode,
    'copy' || 'direct stream' => TautulliDecision.directStream,
    _ => TautulliDecision.directPlay,
  };
}

/// One active stream.
class TautulliStream {
  /// Plex's per-session identifier. Stable while the stream lives, gone the
  /// moment it stops, which makes it the right key for a list that repaints
  /// every few seconds.
  final String sessionKey;

  final int? userId;
  final String? user;
  final String? friendlyName;
  final String? userThumb;

  /// `movie`, `episode`, `track`, `clip`, `photo` or `live`.
  final String? mediaType;

  final String? ratingKey;
  final String? grandparentRatingKey;

  /// The item's own title: the film, or the episode.
  final String? title;

  /// Series title, empty for a movie.
  final String? grandparentTitle;

  /// Season and episode numbers, both empty for a movie.
  final int? seasonNumber;
  final int? episodeNumber;

  final int? year;

  /// Plex library paths (`/library/metadata/57752/thumb/...`), not absolute
  /// URLs. Rendering one needs a Plex server and a token, which is why the UI
  /// resolves artwork through the rating key instead.
  final String? thumb;
  final String? art;

  /// `playing`, `paused` or `buffering`.
  final String? state;

  /// 0 to 100.
  final int percentComplete;

  /// Milliseconds. Tautulli reports both in ms here, unlike `get_history`,
  /// which reports seconds.
  final int? viewOffsetMs;
  final int? durationMs;

  final TautulliDecision decision;

  /// Source resolution (`4k`, `1080p`) and what the client actually receives
  /// (`720p`). Equal unless the video is being resized.
  ///
  /// This pair is the only reliable way to see a downscale: `transcode_width`
  /// and `transcode_height` were empty strings even in a measured capture that
  /// really was transcoding 1080p down to 720p.
  final String? sourceResolution;
  final String? streamResolution;

  final String? sourceVideoCodec;
  final String? streamVideoCodec;

  /// The measured transcode kept the video codec (h264 to h264) and changed
  /// only the audio (eac3 to opus), so a summary built on the video codec alone
  /// would have claimed nothing was happening.
  final String? sourceAudioCodec;
  final String? streamAudioCodec;

  /// Whether the server is using its GPU. Worth showing to an admin: a software
  /// transcode is what melts a NAS.
  final bool hardwareTranscode;

  /// Kbps for this stream, as Tautulli totals it into `total_bandwidth`.
  final int bandwidthKbps;

  /// `lan` or `wan`. Kept because it is useful and carries no address.
  final String? location;

  /// The client's own name for itself, and the product behind it: `Apple TV`
  /// and `Pleya`. The measured capture had an empty `device`, so the player is
  /// the one to show.
  final String? player;
  final String? product;
  final String? platform;

  /// The client's requested quality, e.g. `Original` or `1080p 8 Mbps`.
  final String? qualityProfile;

  const TautulliStream({
    required this.sessionKey,
    this.userId,
    this.user,
    this.friendlyName,
    this.userThumb,
    this.mediaType,
    this.ratingKey,
    this.grandparentRatingKey,
    this.title,
    this.grandparentTitle,
    this.seasonNumber,
    this.episodeNumber,
    this.year,
    this.thumb,
    this.art,
    this.state,
    this.percentComplete = 0,
    this.viewOffsetMs,
    this.durationMs,
    this.decision = TautulliDecision.directPlay,
    this.sourceResolution,
    this.streamResolution,
    this.sourceVideoCodec,
    this.streamVideoCodec,
    this.sourceAudioCodec,
    this.streamAudioCodec,
    this.hardwareTranscode = false,
    this.bandwidthKbps = 0,
    this.location,
    this.player,
    this.product,
    this.platform,
    this.qualityProfile,
  });

  bool get isPaused => state == 'paused';

  bool get isEpisode => mediaType == 'episode';

  /// The name to show, with the admin's override winning over the Plex account
  /// name, as everywhere else in this integration.
  String get displayName => (friendlyName?.isNotEmpty ?? false) ? friendlyName! : (user ?? '');

  /// Seconds left at normal speed, or null when either end is unknown.
  int? get remainingSeconds {
    final total = durationMs;
    final at = viewOffsetMs;
    if (total == null || at == null || total <= 0) return null;
    final left = (total - at) ~/ 1000;
    return left < 0 ? 0 : left;
  }

  static TautulliStream? tryFromJson(Map<String, dynamic> json) {
    final key = tStr(json['session_key']);
    if (key == null) return null;
    return TautulliStream(
      sessionKey: key,
      userId: tInt(json['user_id']),
      user: tStr(json['user']),
      friendlyName: tStr(json['friendly_name']),
      userThumb: tStr(json['user_thumb']),
      mediaType: tStr(json['media_type']),
      ratingKey: tStr(json['rating_key']),
      grandparentRatingKey: tStr(json['grandparent_rating_key']),
      title: tStr(json['title']),
      grandparentTitle: tStr(json['grandparent_title']),
      seasonNumber: tInt(json['parent_media_index']),
      episodeNumber: tInt(json['media_index']),
      year: tInt(json['year']),
      thumb: tStr(json['thumb']),
      art: tStr(json['art']),
      state: tStr(json['state']),
      percentComplete: tInt(json['progress_percent']) ?? 0,
      viewOffsetMs: tInt(json['view_offset']),
      durationMs: tInt(json['duration']),
      decision: TautulliDecision.fromWire(tStr(json['transcode_decision'])),
      sourceResolution: tStr(json['video_full_resolution']),
      streamResolution: tStr(json['stream_video_full_resolution']),
      sourceVideoCodec: tStr(json['video_codec']),
      streamVideoCodec: tStr(json['stream_video_codec']),
      sourceAudioCodec: tStr(json['audio_codec']),
      streamAudioCodec: tStr(json['stream_audio_codec']),
      hardwareTranscode: tInt(json['transcode_hw_encoding']) == 1,
      bandwidthKbps: tInt(json['bandwidth']) ?? 0,
      location: tStr(json['location']),
      player: tStr(json['player']),
      product: tStr(json['product']),
      platform: tStr(json['platform']),
      qualityProfile: tStr(json['quality_profile']),
    );
  }
}

/// The `get_activity` container: the streams plus the totals Tautulli computes
/// over them.
class TautulliActivity {
  final List<TautulliStream> streams;

  /// Tautulli's own counts. Kept rather than recomputed, because it derives
  /// them the same way its web interface does.
  final int streamCount;
  final int directPlayCount;
  final int directStreamCount;
  final int transcodeCount;

  /// Kbps.
  final int totalBandwidth;
  final int lanBandwidth;
  final int wanBandwidth;

  const TautulliActivity({
    required this.streams,
    this.streamCount = 0,
    this.directPlayCount = 0,
    this.directStreamCount = 0,
    this.transcodeCount = 0,
    this.totalBandwidth = 0,
    this.lanBandwidth = 0,
    this.wanBandwidth = 0,
  });

  static const empty = TautulliActivity(streams: []);

  static TautulliActivity fromJson(Map<String, dynamic> json) {
    final rows = json['sessions'];
    return TautulliActivity(
      streams: rows is List
          ? rows.whereType<Map<String, dynamic>>().map(TautulliStream.tryFromJson).nonNulls.toList()
          : const [],
      // `stream_count` arrives as a string while the three counters next to it
      // arrive as numbers, in the same container.
      streamCount: tInt(json['stream_count']) ?? 0,
      directPlayCount: tInt(json['stream_count_direct_play']) ?? 0,
      directStreamCount: tInt(json['stream_count_direct_stream']) ?? 0,
      transcodeCount: tInt(json['stream_count_transcode']) ?? 0,
      totalBandwidth: tInt(json['total_bandwidth']) ?? 0,
      lanBandwidth: tInt(json['lan_bandwidth']) ?? 0,
      wanBandwidth: tInt(json['wan_bandwidth']) ?? 0,
    );
  }
}
