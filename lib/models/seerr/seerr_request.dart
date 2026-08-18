import '../../services/seerr/seerr_constants.dart';

/// A single media request row from `/request`.
///
/// Lenient: the embedded `media` carries the tmdb id + availability, and
/// `requestedBy` is the seerr user who filed it (used for "my requests" vs
/// admin views).
class SeerrRequest {
  final int id;
  final SeerrRequestStatus status;
  final String mediaType; // 'movie' | 'tv'
  final int? tmdbId;
  final String? mediaTitle;
  final String? mediaYear;
  final String? posterPath;
  final String? backdropPath;
  final SeerrMediaStatus mediaStatus;
  final List<int> seasons;
  final bool is4k;
  final int? requestedById;
  final String? requestedByName;
  final String? createdAt;

  const SeerrRequest({
    required this.id,
    required this.status,
    required this.mediaType,
    this.tmdbId,
    this.mediaTitle,
    this.mediaYear,
    this.posterPath,
    this.backdropPath,
    this.mediaStatus = SeerrMediaStatus.unknown,
    this.seasons = const [],
    this.is4k = false,
    this.requestedById,
    this.requestedByName,
    this.createdAt,
  });

  bool get isPending => status == SeerrRequestStatus.pending;

  /// Whether the row still lacks the fields that make it readable. Overseerr's
  /// `/request` payload carries the media row (tmdb id, availability) but no
  /// title, year or artwork, so these have to be fetched separately.
  bool get needsDisplayData => mediaTitle == null || posterPath == null;

  /// Returns a copy with the display fields filled in. Only overwrites what is
  /// still missing, so a Jellyseerr payload that did embed them keeps its own.
  SeerrRequest withDisplayData({String? title, String? year, String? posterPath, String? backdropPath}) {
    return SeerrRequest(
      id: id,
      status: status,
      mediaType: mediaType,
      tmdbId: tmdbId,
      mediaTitle: mediaTitle ?? title,
      mediaYear: mediaYear ?? year,
      posterPath: this.posterPath ?? posterPath,
      backdropPath: this.backdropPath ?? backdropPath,
      mediaStatus: mediaStatus,
      seasons: seasons,
      is4k: is4k,
      requestedById: requestedById,
      requestedByName: requestedByName,
      createdAt: createdAt,
    );
  }

  static int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  static String? _nonEmptyString(Object? value) {
    final s = value?.toString().trim();
    return s == null || s.isEmpty ? null : s;
  }

  static String? _yearFrom(Object? date) {
    final s = date?.toString();
    if (s == null || s.length < 4) return null;
    return s.substring(0, 4);
  }

  static SeerrRequest? tryFromJson(Map<String, dynamic> json) {
    final id = _asInt(json['id']);
    if (id == null) return null;

    final media = json['media'];
    final mediaMap = media is Map ? media.cast<String, dynamic>() : const <String, dynamic>{};
    final embeddedMovie = mediaMap['movie'];
    final embeddedTv = mediaMap['tv'];
    final embeddedMedia = embeddedMovie is Map
        ? embeddedMovie.cast<String, dynamic>()
        : embeddedTv is Map
        ? embeddedTv.cast<String, dynamic>()
        : const <String, dynamic>{};
    final mediaType = (json['type'] ?? mediaMap['mediaType'])?.toString() ?? 'movie';

    final requestedBy = json['requestedBy'];
    final requestedByMap = requestedBy is Map ? requestedBy : const {};

    final seasons = <int>[];
    if (json['seasons'] is List) {
      for (final s in json['seasons'] as List) {
        final n = s is Map ? _asInt(s['seasonNumber']) : _asInt(s);
        if (n != null) seasons.add(n);
      }
    }

    return SeerrRequest(
      id: id,
      status: SeerrRequestStatus.fromValue(_asInt(json['status'])),
      mediaType: mediaType,
      tmdbId: _asInt(mediaMap['tmdbId']),
      mediaTitle: _nonEmptyString(
        mediaMap['title'] ??
            mediaMap['name'] ??
            mediaMap['originalTitle'] ??
            mediaMap['originalName'] ??
            embeddedMedia['title'] ??
            embeddedMedia['name'] ??
            embeddedMedia['originalTitle'] ??
            embeddedMedia['originalName'],
      ),
      mediaYear: _yearFrom(
        mediaMap['releaseDate'] ??
            mediaMap['firstAirDate'] ??
            embeddedMedia['releaseDate'] ??
            embeddedMedia['firstAirDate'],
      ),
      posterPath: _nonEmptyString(mediaMap['posterPath'] ?? embeddedMedia['posterPath']),
      backdropPath: _nonEmptyString(mediaMap['backdropPath'] ?? embeddedMedia['backdropPath']),
      mediaStatus: SeerrMediaStatus.fromValue(_asInt(mediaMap['status'])),
      seasons: seasons,
      is4k: json['is4k'] == true,
      requestedById: _asInt(requestedByMap['id']),
      requestedByName: (requestedByMap['displayName'] ?? requestedByMap['username'] ?? requestedByMap['plexUsername'])
          ?.toString(),
      createdAt: json['createdAt']?.toString(),
    );
  }
}

/// Collapses requested season numbers into a compact, still-accurate string:
/// `3`, `18-22`, `1-3, 7`. Runs of consecutive seasons become a range; gaps are
/// preserved, because "Seizoenen 1-22" would be a lie about what was asked for.
///
/// Returns null past [maxGroups] separate runs, where naming every one of them
/// takes over the card. The caller then says how many there are instead.
String? seerrSeasonRanges(List<int> seasons, {int maxGroups = 3}) {
  if (seasons.isEmpty) return null;
  final sorted = seasons.toSet().toList()..sort();

  final groups = <String>[];
  var start = sorted.first;
  var previous = start;
  for (final n in sorted.skip(1)) {
    if (n == previous + 1) {
      previous = n;
      continue;
    }
    groups.add(start == previous ? '$start' : '$start-$previous');
    start = n;
    previous = n;
  }
  groups.add(start == previous ? '$start' : '$start-$previous');

  if (groups.length > maxGroups) return null;
  return groups.join(', ');
}
