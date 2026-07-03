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
    this.mediaStatus = SeerrMediaStatus.unknown,
    this.seasons = const [],
    this.is4k = false,
    this.requestedById,
    this.requestedByName,
    this.createdAt,
  });

  bool get isPending => status == SeerrRequestStatus.pending;

  static int? _asInt(Object? v) => v is int ? v : (v is num ? v.toInt() : int.tryParse('${v ?? ''}'));

  static SeerrRequest? tryFromJson(Map<String, dynamic> json) {
    final id = _asInt(json['id']);
    if (id == null) return null;

    final media = json['media'];
    final mediaMap = media is Map ? media.cast<String, dynamic>() : const <String, dynamic>{};
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
