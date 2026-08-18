/// Someone playing something right now, as reported by a source the signed-in
/// admin is entitled to read.
///
/// Backend-neutral on purpose, in the same spirit as [ItemWatcher]: the widgets
/// that render this never see a Tautulli field name. Today Tautulli is the only
/// source (it is Plex-only monitoring, and Jellyfin has no equivalent), but the
/// UI does not know that.
///
/// `ip_address` is absent by construction. Tautulli hands one out per session,
/// including public addresses, and it has no place in a model, a log or a cache
/// key. Only [isLan] survives, which carries the useful half without the
/// address.
library;

/// How the server is delivering a stream, which is the one thing an admin wants
/// to see at a glance.
enum StreamDelivery {
  /// The file goes out as it is.
  directPlay,

  /// Container swapped, video and audio untouched.
  directStream,

  /// The server is re-encoding.
  transcode,
}

/// One active playback.
class WatchSession {
  /// Source-local identifier, stable for the life of the session. Used as a
  /// widget key and to keep focus on the same row across polls.
  final String id;

  /// Who is watching, in the display name their admin configured.
  final String userName;

  /// Absolute avatar URL, or null for the initials fallback.
  final String? userThumb;

  /// Whether this is the signed-in admin's own playback. Those are filtered out
  /// of the presence indicator: your own stream is not news.
  final bool isSelf;

  /// What is playing. For an episode this is the series name, with the episode
  /// in [subtitle].
  final String title;

  /// Year for a movie, `S1 · E3 Llamigos` for an episode. Null when the source
  /// gives neither.
  final String? subtitle;

  /// Rating key of the item itself, so tapping a session can open the title.
  /// Null when the source reports no usable key, in which case the row is inert
  /// rather than opening the wrong page.
  final String? ratingKey;

  /// Landscape still for the row, or null for a placeholder.
  final String? artUrl;

  /// 0 to 100.
  final int progressPercent;

  /// Seconds left, when the source reports enough to compute it.
  final int? remainingSeconds;

  final bool isPaused;

  final StreamDelivery delivery;

  /// Short human summary of what the transcode costs, e.g. `1080p → 720p`.
  /// Null for anything that is not transcoding.
  final String? transcodeSummary;

  /// Whether the server is transcoding on its GPU. Worth showing to an admin: a
  /// software transcode is what melts a NAS.
  final bool hardwareTranscode;

  /// Stream bandwidth in kbps, 0 when unknown.
  final int bandwidthKbps;

  /// True for a local stream, false for remote, null when unreported.
  final bool? isLan;

  /// Device and app, already joined for display (`Apple TV · Pleya`). Null when
  /// the source names neither.
  final String? playerLabel;

  const WatchSession({
    required this.id,
    required this.userName,
    this.userThumb,
    this.isSelf = false,
    required this.title,
    this.subtitle,
    this.ratingKey,
    this.artUrl,
    this.progressPercent = 0,
    this.remainingSeconds,
    this.isPaused = false,
    this.delivery = StreamDelivery.directPlay,
    this.transcodeSummary,
    this.hardwareTranscode = false,
    this.bandwidthKbps = 0,
    this.isLan,
    this.playerLabel,
  });

  bool get isTranscoding => delivery == StreamDelivery.transcode;

  /// Whether two polls of the same session would draw the same row.
  ///
  /// Covers everything that can move while a session lives, which is more than
  /// the progress bar: the countdown ticks between two whole percent (on a
  /// three-hour film 1% is nearly two minutes, so comparing on
  /// [progressPercent] alone freezes it), a paused stream resumes, the server
  /// switches to transcoding, and one session key survives a jump to the next
  /// episode, which changes the title and the artwork under the same [id].
  static bool sameRender(WatchSession a, WatchSession b) =>
      a.id == b.id &&
      a.userName == b.userName &&
      a.userThumb == b.userThumb &&
      a.title == b.title &&
      a.subtitle == b.subtitle &&
      a.ratingKey == b.ratingKey &&
      a.artUrl == b.artUrl &&
      a.progressPercent == b.progressPercent &&
      a.remainingSeconds == b.remainingSeconds &&
      a.isPaused == b.isPaused &&
      a.delivery == b.delivery &&
      a.transcodeSummary == b.transcodeSummary &&
      a.hardwareTranscode == b.hardwareTranscode &&
      a.bandwidthKbps == b.bandwidthKbps &&
      a.isLan == b.isLan &&
      a.playerLabel == b.playerLabel;

  /// Longest running first, so the rows stop reshuffling under the pointer
  /// every poll. Ties fall back to the id, which is stable.
  static int compare(WatchSession a, WatchSession b) {
    final byProgress = b.progressPercent.compareTo(a.progressPercent);
    return byProgress != 0 ? byProgress : a.id.compareTo(b.id);
  }
}

/// Everything playing on one server plus the totals reported alongside it.
///
/// [sessions] excludes the signed-in admin's own playback; [ownSessionCount]
/// records how many were dropped, so the panel can still say something true
/// about a server where the only stream is yours.
class NowWatching {
  final List<WatchSession> sessions;
  final int ownSessionCount;

  /// Sum over all streams in kbps, 0 when unknown.
  final int totalBandwidthKbps;
  final int lanBandwidthKbps;
  final int wanBandwidthKbps;

  const NowWatching({
    required this.sessions,
    this.ownSessionCount = 0,
    this.totalBandwidthKbps = 0,
    this.lanBandwidthKbps = 0,
    this.wanBandwidthKbps = 0,
  });

  static const empty = NowWatching(sessions: []);

  /// What the presence indicator exists for: other people, watching now.
  bool get hasOthers => sessions.isNotEmpty;

  int get transcodeCount => sessions.where((s) => s.isTranscoding).length;

  /// Amber instead of green in the indicator. The only state an admin can act
  /// on without opening anything.
  bool get hasTranscode => transcodeCount > 0;
}
