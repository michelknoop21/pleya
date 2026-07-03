import '../../services/seerr/seerr_constants.dart';

/// A movie or TV result from a seerr search / discover / detail response.
///
/// Parsed leniently: unknown fields are ignored and every field is optional
/// except [tmdbId] / [mediaType], so Overseerr and Jellyseerr (v1/v2) payloads
/// both decode. Titles differ by media type (`title` for movies, `name` for
/// TV), and dates likewise (`releaseDate` / `firstAirDate`).
class SeerrMedia {
  final int tmdbId;
  final String mediaType; // 'movie' | 'tv'
  final String title;
  final String? year;
  final String? posterPath;
  final String? overview;
  final SeerrMediaStatus status;

  const SeerrMedia({
    required this.tmdbId,
    required this.mediaType,
    required this.title,
    this.year,
    this.posterPath,
    this.overview,
    this.status = SeerrMediaStatus.unknown,
  });

  bool get isMovie => mediaType == 'movie';
  String get posterUrl => SeerrConstants.tmdbPosterUrl(posterPath);

  static int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  static String? _yearFrom(Object? date) {
    final s = date?.toString();
    if (s == null || s.length < 4) return null;
    return s.substring(0, 4);
  }

  /// Decode a search/discover row. Returns null when it isn't a movie/tv
  /// row (e.g. `person` results) or has no usable tmdb id.
  static SeerrMedia? tryFromJson(Map<String, dynamic> json) {
    final type = (json['mediaType'] ?? json['media_type'])?.toString();
    if (type != 'movie' && type != 'tv') return null;
    final tmdbId = _asInt(json['id']) ?? _asInt(json['tmdbId']);
    if (tmdbId == null) return null;

    final mediaInfo = json['mediaInfo'];
    final statusVal = mediaInfo is Map ? _asInt(mediaInfo['status']) : null;

    return SeerrMedia(
      tmdbId: tmdbId,
      mediaType: type!,
      title: (json['title'] ?? json['name'] ?? json['originalTitle'] ?? json['originalName'] ?? '').toString(),
      year: _yearFrom(json['releaseDate'] ?? json['firstAirDate']),
      posterPath: json['posterPath']?.toString(),
      overview: json['overview']?.toString(),
      status: SeerrMediaStatus.fromValue(statusVal),
    );
  }

  /// Decode a movie/tv *detail* response (`/movie/{id}`, `/tv/{id}`), where the
  /// media type isn't echoed back in the body.
  factory SeerrMedia.fromDetail(Map<String, dynamic> json, {required String mediaType}) {
    final mediaInfo = json['mediaInfo'];
    final statusVal = mediaInfo is Map ? _asInt(mediaInfo['status']) : null;
    return SeerrMedia(
      tmdbId: _asInt(json['id']) ?? 0,
      mediaType: mediaType,
      title: (json['title'] ?? json['name'] ?? '').toString(),
      year: _yearFrom(json['releaseDate'] ?? json['firstAirDate']),
      posterPath: json['posterPath']?.toString(),
      overview: json['overview']?.toString(),
      status: SeerrMediaStatus.fromValue(statusVal),
    );
  }
}

/// A single season entry from a TV detail response, with its per-season
/// availability so the request sheet can disable already-available seasons.
class SeerrSeason {
  final int seasonNumber;
  final String? name;
  final int episodeCount;
  final SeerrMediaStatus status;

  const SeerrSeason({
    required this.seasonNumber,
    this.name,
    this.episodeCount = 0,
    this.status = SeerrMediaStatus.unknown,
  });

  static List<SeerrSeason> listFromDetail(Map<String, dynamic> detail) {
    final rawSeasons = detail['seasons'];
    if (rawSeasons is! List) return const [];

    // Per-season availability lives on mediaInfo.seasons keyed by seasonNumber.
    final statusBySeason = <int, SeerrMediaStatus>{};
    final mediaInfo = detail['mediaInfo'];
    if (mediaInfo is Map && mediaInfo['seasons'] is List) {
      for (final s in mediaInfo['seasons'] as List) {
        if (s is! Map) continue;
        final n = SeerrMedia._asInt(s['seasonNumber']);
        if (n == null) continue;
        statusBySeason[n] = SeerrMediaStatus.fromValue(SeerrMedia._asInt(s['status']));
      }
    }

    final out = <SeerrSeason>[];
    for (final s in rawSeasons) {
      if (s is! Map) continue;
      final n = SeerrMedia._asInt(s['seasonNumber']);
      if (n == null || n == 0) continue; // skip "Specials" (season 0)
      out.add(
        SeerrSeason(
          seasonNumber: n,
          name: s['name']?.toString(),
          episodeCount: SeerrMedia._asInt(s['episodeCount']) ?? 0,
          status: statusBySeason[n] ?? SeerrMediaStatus.unknown,
        ),
      );
    }
    return out;
  }
}

/// A Radarr/Sonarr backend server the admin can target for advanced request
/// options.
class SeerrServiceServer {
  final int id;
  final String name;
  final bool is4k;
  final bool isDefault;

  const SeerrServiceServer({required this.id, required this.name, this.is4k = false, this.isDefault = false});

  static List<SeerrServiceServer> listFrom(Object? raw) {
    if (raw is! List) return const [];
    final out = <SeerrServiceServer>[];
    for (final s in raw) {
      if (s is! Map) continue;
      final id = SeerrMedia._asInt(s['id']);
      if (id == null) continue;
      out.add(
        SeerrServiceServer(
          id: id,
          name: (s['name'] ?? 'Server $id').toString(),
          is4k: s['is4k'] == true,
          isDefault: s['isDefault'] == true,
        ),
      );
    }
    return out;
  }
}
