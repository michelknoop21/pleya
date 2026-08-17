/// How often and how long a title was played on this server.
///
/// Tautulli-only. The Plex Media Server can be asked who watched something, but
/// not how much time went into it, so there is no fallback and no section when
/// Tautulli is not configured. Showing a play count without the hours would be
/// a different, weaker claim dressed up as the same one.
class MediaWatchStats {
  /// Every play, finished or abandoned. This is Tautulli's own counter and it
  /// does not filter on `watched_status`, so it is deliberately not the same
  /// number as the length of the watchers list.
  final int totalPlays;

  final Duration totalTime;

  /// Distinct people with at least one play. Null when not resolved.
  final int? userCount;

  /// Plays in the last thirty days, for a sense of whether it is current.
  /// Null when Tautulli did not report that window.
  final int? playsLast30Days;

  const MediaWatchStats({required this.totalPlays, required this.totalTime, this.userCount, this.playsLast30Days});

  static const empty = MediaWatchStats(totalPlays: 0, totalTime: Duration.zero);

  /// Nothing worth a line on the detail page.
  bool get isEmpty => totalPlays == 0 && totalTime == Duration.zero;

  bool get isNotEmpty => !isEmpty;
}
