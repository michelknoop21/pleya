/// External IDs (IMDb / TMDB / TVDB) extracted from a media server's
/// metadata. Shared by the Trakt and tracker resolvers.
///
/// - **Plex** stores them in a `Guid` array (`imdb://tt123`,
///   `tmdb://456`, `tvdb://789`) — fetched via
///   [PlexClient.fetchExternalGuids]. Use [ExternalIds.fromGuids].
/// - **Jellyfin** stores them inline as a `ProviderIds` map on every
///   `BaseItemDto`. Use [ExternalIds.fromJellyfinProviderIds].
class ExternalIds {
  final String? imdb;
  final int? tmdb;
  final int? tvdb;

  const ExternalIds({this.imdb, this.tmdb, this.tvdb});

  bool get hasAny => imdb != null || tmdb != null || tvdb != null;

  /// Round-trip form for cached rows. Absent keys stay absent rather than
  /// serialising as null, so an old row without a field reads back the same
  /// as a new one that never had it.
  Map<String, Object?> toJson() => {
    if (imdb != null) 'imdb': imdb,
    if (tmdb != null) 'tmdb': tmdb,
    if (tvdb != null) 'tvdb': tvdb,
  };

  factory ExternalIds.fromJson(Map<String, Object?> json) {
    final imdb = json['imdb'];
    final tmdb = json['tmdb'];
    final tvdb = json['tvdb'];
    return ExternalIds(
      imdb: imdb is String && imdb.isNotEmpty ? imdb : null,
      tmdb: tmdb is int ? tmdb : int.tryParse('$tmdb'),
      tvdb: tvdb is int ? tvdb : int.tryParse('$tvdb'),
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is ExternalIds && other.imdb == imdb && other.tmdb == tmdb && other.tvdb == tvdb;

  @override
  int get hashCode => Object.hash(imdb, tmdb, tvdb);

  @override
  String toString() => 'ExternalIds(imdb: $imdb, tmdb: $tmdb, tvdb: $tvdb)';

  factory ExternalIds.fromGuids(List<dynamic> guids) {
    String? imdb;
    int? tmdb;
    int? tvdb;
    for (final g in guids) {
      if (g is! Map) continue;
      final id = g['id'];
      if (id is! String) continue;
      if (id.startsWith('imdb://')) {
        imdb = id.substring(7);
      } else if (id.startsWith('tmdb://')) {
        tmdb = int.tryParse(id.substring(7));
      } else if (id.startsWith('tvdb://')) {
        tvdb = int.tryParse(id.substring(7));
      }
    }
    return ExternalIds(imdb: imdb, tmdb: tmdb, tvdb: tvdb);
  }

  /// Build from a Jellyfin `ProviderIds` map. Jellyfin stores external IDs
  /// directly on every `BaseItemDto` so no extra fetch is needed.
  /// Keys are case-insensitive in practice (`Tmdb`, `Imdb`, `Tvdb`).
  factory ExternalIds.fromJellyfinProviderIds(Map<String, Object?> providerIds) {
    String? imdb;
    int? tmdb;
    int? tvdb;
    providerIds.forEach((key, value) {
      if (value is! String || value.isEmpty) return;
      switch (key.toLowerCase()) {
        case 'imdb':
          imdb = value;
          break;
        case 'tmdb':
          tmdb = int.tryParse(value);
          break;
        case 'tvdb':
          tvdb = int.tryParse(value);
          break;
      }
    });
    return ExternalIds(imdb: imdb, tmdb: tmdb, tvdb: tvdb);
  }
}
