/// Response models for the Tautulli API, shaped after the measured captures in
/// `test/fixtures/tautulli/`.
///
/// Parsing is lenient: Tautulli returns numbers as ints or strings depending on
/// the command and the version, and adds fields between releases. Unknown
/// fields are ignored, missing ones fall back rather than throw.
///
/// `ip_address` is deliberately absent from every model here. Tautulli hands it
/// out on history and activity, including public addresses, and it has no place
/// in a model, a log or a cache key.
library;

import 'tautulli_json.dart';

const _int = tInt;
const _double = tDouble;
const _str = tStr;

/// One user's totals for a single title, from `get_item_user_stats`.
///
/// Works for a movie and for a show, where Tautulli aggregates every episode.
///
/// [totalPlays] counts **every** play, including abandoned ones: the measured
/// capture has a user with three plays of which one stopped at 10 percent. So
/// this type answers "has watched in this title", not "has finished it". Use
/// [TautulliHistoryEntry.isWatched] when the stronger claim is needed.
class TautulliItemUserStat {
  final int userId;
  final String username;
  final String friendlyName;
  final String? userThumb;
  final int totalPlays;

  /// Seconds of playback across all plays.
  final int totalTime;

  const TautulliItemUserStat({
    required this.userId,
    required this.username,
    required this.friendlyName,
    this.userThumb,
    required this.totalPlays,
    required this.totalTime,
  });

  /// The name to show. Tautulli lets the admin override a Plex username with a
  /// friendly name, and that override is the one people recognise.
  String get displayName => friendlyName.isNotEmpty ? friendlyName : username;

  static TautulliItemUserStat? tryFromJson(Map<String, dynamic> json) {
    final id = _int(json['user_id']);
    if (id == null) return null;
    return TautulliItemUserStat(
      userId: id,
      username: _str(json['username']) ?? '',
      friendlyName: _str(json['friendly_name']) ?? '',
      userThumb: _str(json['user_thumb']),
      totalPlays: _int(json['total_plays']) ?? 0,
      totalTime: _int(json['total_time']) ?? 0,
    );
  }
}

/// One playback from `get_history`.
class TautulliHistoryEntry {
  final int? rowId;
  final int? userId;
  final String? user;
  final String? friendlyName;
  final String? userThumb;

  /// 0 = not watched, 1 = watched. Tautulli also emits 0.5 for a partially
  /// watched item, which is why this is a number and not a bool.
  final double watchedStatus;

  /// 0 to 100.
  final int percentComplete;

  /// Epoch seconds of the play.
  final int? date;

  /// Seconds actually played.
  final int? duration;

  /// Seconds actually played, read from `play_duration` with `duration` as a
  /// fallback.
  ///
  /// Inside `get_history` these are literally the same value: `datafactory.py`
  /// writes `'duration': item['play_duration']` next to
  /// `'play_duration': item['play_duration']`, and that value is
  /// `SUM(stopped - started) - SUM(paused_counter)`. The media duration is not
  /// in this response at all; it is only used internally as the denominator for
  /// `percent_complete`.
  ///
  /// The separate name exists because the same key means something else one
  /// command over: in `get_activity`, `duration` is the media length in
  /// milliseconds. Anything reasoning about how much was watched should say
  /// [playSeconds] so the two can never be swapped by accident.
  final int? playSeconds;

  /// `pms_identifier` of the server the play happened on. Absent on older
  /// Tautulli builds, which is why a missing value is not a rejection.
  final String? machineId;

  final String? platform;
  final String? player;
  final String? mediaType;
  final int? ratingKey;
  final int? grandparentRatingKey;
  final String? fullTitle;
  final String? transcodeDecision;

  /// `lan` or `wan`. Kept because it is useful and carries no address.
  final String? location;

  const TautulliHistoryEntry({
    this.rowId,
    this.userId,
    this.user,
    this.friendlyName,
    this.userThumb,
    required this.watchedStatus,
    required this.percentComplete,
    this.date,
    this.duration,
    this.playSeconds,
    this.machineId,
    this.platform,
    this.player,
    this.mediaType,
    this.ratingKey,
    this.grandparentRatingKey,
    this.fullTitle,
    this.transcodeDecision,
    this.location,
  });

  /// Tautulli's own verdict that the item was watched through, using the
  /// threshold the admin configured. Anything below that stays false, so a
  /// five-second start never counts.
  bool get isWatched => watchedStatus >= 1;

  String get displayName => (friendlyName?.isNotEmpty ?? false) ? friendlyName! : (user ?? '');

  static TautulliHistoryEntry fromJson(Map<String, dynamic> json) {
    return TautulliHistoryEntry(
      rowId: _int(json['row_id']),
      userId: _int(json['user_id']),
      user: _str(json['user']),
      friendlyName: _str(json['friendly_name']),
      userThumb: _str(json['user_thumb']),
      watchedStatus: _double(json['watched_status']) ?? 0,
      percentComplete: _int(json['percent_complete']) ?? 0,
      date: _int(json['date']),
      duration: _int(json['duration']),
      playSeconds: _int(json['play_duration']) ?? _int(json['duration']),
      machineId: _str(json['machine_id']),
      platform: _str(json['platform']),
      player: _str(json['player']),
      mediaType: _str(json['media_type']),
      ratingKey: _int(json['rating_key']),
      grandparentRatingKey: _int(json['grandparent_rating_key']),
      fullTitle: _str(json['full_title']),
      transcodeDecision: _str(json['transcode_decision']),
      location: _str(json['location']),
    );
  }
}

/// A page of history rows plus the totals Tautulli reports alongside them.
class TautulliHistoryPage {
  final List<TautulliHistoryEntry> entries;
  final int recordsTotal;
  final int recordsFiltered;

  /// Seconds across the filtered set.
  final int totalDuration;

  const TautulliHistoryPage({
    required this.entries,
    this.recordsTotal = 0,
    this.recordsFiltered = 0,
    this.totalDuration = 0,
  });

  static const empty = TautulliHistoryPage(entries: []);

  static TautulliHistoryPage fromJson(Map<String, dynamic> json) {
    final rows = json['data'];
    return TautulliHistoryPage(
      entries: rows is List
          ? rows.whereType<Map<String, dynamic>>().map(TautulliHistoryEntry.fromJson).toList()
          : const [],
      recordsTotal: _int(json['recordsTotal']) ?? 0,
      recordsFiltered: _int(json['recordsFiltered']) ?? 0,
      // Tautulli sends this as a formatted string on some versions.
      totalDuration: _int(json['total_duration']) ?? 0,
    );
  }
}

/// A Plex user known to Tautulli, from `get_users`.
///
/// Unlike the Plex Media Server's own `/accounts`, which returned an empty
/// `thumb` for every account in the measured capture, this carries a usable
/// avatar URL for all of them.
class TautulliUser {
  final int userId;
  final String username;
  final String friendlyName;
  final String? thumb;
  final bool isActive;
  final bool isAdmin;
  final bool isHomeUser;

  const TautulliUser({
    required this.userId,
    required this.username,
    required this.friendlyName,
    this.thumb,
    this.isActive = true,
    this.isAdmin = false,
    this.isHomeUser = false,
  });

  String get displayName => friendlyName.isNotEmpty ? friendlyName : username;

  static TautulliUser? tryFromJson(Map<String, dynamic> json) {
    final id = _int(json['user_id']);
    if (id == null) return null;
    return TautulliUser(
      userId: id,
      username: _str(json['username']) ?? '',
      friendlyName: _str(json['friendly_name']) ?? '',
      thumb: _str(json['thumb']),
      isActive: _int(json['is_active']) != 0,
      isAdmin: _int(json['is_admin']) == 1,
      isHomeUser: _int(json['is_home_user']) == 1,
    );
  }
}

/// Total plays and seconds for a title over a window, from
/// `get_item_watch_time_stats`. Tautulli returns one entry per window, with
/// `query_days: 0` meaning "all time".
class TautulliWatchTimeStat {
  final int queryDays;
  final int totalPlays;
  final int totalTime;

  const TautulliWatchTimeStat({required this.queryDays, required this.totalPlays, required this.totalTime});

  bool get isAllTime => queryDays == 0;

  static TautulliWatchTimeStat fromJson(Map<String, dynamic> json) => TautulliWatchTimeStat(
    queryDays: _int(json['query_days']) ?? 0,
    totalPlays: _int(json['total_plays']) ?? 0,
    totalTime: _int(json['total_time']) ?? 0,
  );
}
