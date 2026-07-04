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
