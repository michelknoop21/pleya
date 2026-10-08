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

  /// `media.status4k`, which Seerr tracks apart from the HD status. Null when
  /// the payload does not carry it.
  final SeerrMediaStatus? mediaStatus4k;
  final List<int> seasons;
  final bool is4k;
  final int? requestedById;
  final String? requestedByName;
  final String? createdAt;

  /// The Radarr/Sonarr target stored on the request. Null means the payload
  /// carried no value, which is not the same as "the server default": an edit
  /// has to echo these back unchanged (see `SeerrClientRequests.updateRequest`).
  final int? serverId;
  final int? profileId;
  final String? rootFolder;
  final int? languageProfileId;
  final List<int>? tags;

  /// What the payload actually said, as opposed to what this class filled in.
  ///
  /// Parsing is lenient so a list can still show a row that is missing a
  /// field: no status reads as pending, no `is4k` as HD. That is fine for
  /// drawing and wrong as evidence. Anything that decides "did my write land"
  /// or "may I offer an action" asks these first, and a payload that does not
  /// say is not proof of anything.
  final bool statusKnown;
  final bool typeKnown;
  final bool qualityKnown;
  final bool seasonsKnown;

  /// All target fields were explicit and valid (including explicit null).
  final bool targetKnown;

  /// Advanced fields that PUT echoes were explicit and valid. Missing or
  /// partly malformed values cannot replace the last trustworthy request.
  final bool advancedKnown;

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
    this.mediaStatus4k,
    this.seasons = const [],
    this.is4k = false,
    this.requestedById,
    this.requestedByName,
    this.createdAt,
    this.serverId,
    this.profileId,
    this.rootFolder,
    this.languageProfileId,
    this.tags,
    this.statusKnown = true,
    this.typeKnown = true,
    this.qualityKnown = true,
    this.seasonsKnown = true,
    this.targetKnown = true,
    this.advancedKnown = true,
  });

  /// Pending because the server said so, not because it said nothing.
  bool get isPending => statusKnown && status == SeerrRequestStatus.pending;

  /// Whether this payload can be compared with a write: every field a write
  /// touches or depends on is one the server actually sent.
  bool get isReliableReadback =>
      statusKnown && typeKnown && qualityKnown && requestedById != null && (mediaType != 'tv' || seasonsKnown);

  /// Whether the media this request asked for is there, in the quality it
  /// asked for. Unknown 4K status is not "there".
  bool get isFulfilled => (is4k ? mediaStatus4k : mediaStatus) == SeerrMediaStatus.available;

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
      mediaStatus4k: mediaStatus4k,
      seasons: seasons,
      is4k: is4k,
      requestedById: requestedById,
      requestedByName: requestedByName,
      createdAt: createdAt,
      serverId: serverId,
      profileId: profileId,
      rootFolder: rootFolder,
      languageProfileId: languageProfileId,
      tags: tags,
      statusKnown: statusKnown,
      typeKnown: typeKnown,
      qualityKnown: qualityKnown,
      seasonsKnown: seasonsKnown,
      targetKnown: targetKnown,
      advancedKnown: advancedKnown,
    );
  }

  static int? _asInt(Object? v) {
    if (v is int) return v;
    if (v is num) return v.isFinite && v == v.truncateToDouble() ? v.toInt() : null;
    return v is String ? int.tryParse(v) : null;
  }

  static bool _validId(Object? value) {
    final id = _asInt(value);
    return id != null && id >= 0;
  }

  static bool _nullableIdKnown(Map<String, dynamic> json, String key) =>
      json.containsKey(key) && (json[key] == null || _validId(json[key]));

  static bool _tagsKnown(Map<String, dynamic> json) =>
      json.containsKey('tags') &&
      (json['tags'] == null || (json['tags'] is List && (json['tags'] as List).every(_validId)));

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
    var seasonsKnown = json['seasons'] is List;
    if (json['seasons'] is List) {
      for (final s in json['seasons'] as List) {
        final n = s is Map ? _asInt(s['seasonNumber']) : _asInt(s);
        if (n != null) {
          seasons.add(n);
        } else {
          // An entry that is not a season number: the list is not the whole
          // answer any more.
          seasonsKnown = false;
        }
      }
    }
    final rawStatus = _asInt(json['status']);
    final rawType = json['type'] ?? mediaMap['mediaType'];

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
      mediaStatus4k: _asInt(mediaMap['status4k']) == null
          ? null
          : SeerrMediaStatus.fromValue(_asInt(mediaMap['status4k'])),
      seasons: seasons,
      is4k: json['is4k'] == true,
      requestedById: _asInt(requestedByMap['id']),
      requestedByName: (requestedByMap['displayName'] ?? requestedByMap['username'] ?? requestedByMap['plexUsername'])
          ?.toString(),
      createdAt: json['createdAt']?.toString(),
      serverId: _asInt(json['serverId']),
      profileId: _asInt(json['profileId']),
      rootFolder: json['rootFolder'] is String ? json['rootFolder'] as String : null,
      languageProfileId: _asInt(json['languageProfileId']),
      tags: json['tags'] is List ? [for (final tag in json['tags'] as List) ?_asInt(tag)] : null,
      statusKnown: rawStatus != null && SeerrRequestStatus.values.any((s) => s.value == rawStatus),
      typeKnown: rawType == 'movie' || rawType == 'tv',
      qualityKnown: json['is4k'] is bool,
      seasonsKnown: seasonsKnown,
      targetKnown:
          _nullableIdKnown(json, 'serverId') &&
          _nullableIdKnown(json, 'profileId') &&
          json.containsKey('rootFolder') &&
          (json['rootFolder'] == null || json['rootFolder'] is String),
      advancedKnown: _tagsKnown(json) && (mediaType != 'tv' || _nullableIdKnown(json, 'languageProfileId')),
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
