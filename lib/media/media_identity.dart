import '../utils/external_ids.dart';
import '../utils/title_normalizer.dart';
import 'media_item.dart';
import 'media_kind.dart';

/// A title as described by something that is not a server: a watchlist entry,
/// a catalogue result, a tracker row.
///
/// Used to ask a server "do you have this", where "this" cannot be a rating
/// key because those differ per server.
class MediaIdentity {
  /// Plex catalogue guid (`plex://movie/...`) when the source has one.
  final String? guid;

  final ExternalIds externalIds;
  final String? title;
  final int? year;
  final MediaKind kind;

  const MediaIdentity({
    this.guid,
    this.externalIds = const ExternalIds(),
    this.title,
    this.year,
    this.kind = MediaKind.unknown,
  });

  /// A candidate paired with the external ids the server reported for it.
  /// Kept separate because [MediaItem] does not carry them: Plex ships them in
  /// a `Guid` array next to the item and Jellyfin in a `ProviderIds` map.
  static ({MediaItem item, ExternalIds ids}) candidate(MediaItem item, ExternalIds ids) => (item: item, ids: ids);

  /// The one candidate that is confidently this title, or null.
  ///
  /// Three tiers, and the order is the point: a guid is proof, an external id
  /// is near-proof, and a title is a guess that only counts when nothing else
  /// answers. **Ambiguity never resolves.** Two candidates that both look
  /// right mean the library holds two versions or two different films with the
  /// same name, and picking one would put the wrong entry behind a poster.
  MediaItem? pickMatch(List<({MediaItem item, ExternalIds ids})> candidates) {
    final wanted = guid;
    if (wanted != null && wanted.isNotEmpty) {
      final byGuid = candidates.where((c) => c.item.guid == wanted).toList();
      if (byGuid.length == 1) return byGuid.single.item;
      if (byGuid.length > 1) return null;
    }

    if (externalIds.hasAny) {
      final byExternal = candidates.where((c) => _sharesExternalId(c.ids)).toList();
      if (byExternal.length == 1) return byExternal.single.item;
      if (byExternal.length > 1) return null;
    }

    final wantedTitle = title;
    if (wantedTitle == null || wantedTitle.isEmpty) return null;
    final normalized = normalizeTitleForMatching(wantedTitle);
    if (normalized.isEmpty) return null;

    final byTitle = candidates.where((c) {
      final item = c.item;
      if (kind != MediaKind.unknown && item.kind != kind) return false;
      if (normalizeTitleForMatching(item.title) != normalized) return false;
      // A year on both sides has to agree; a library that omits it is
      // tolerated rather than rejected.
      if (year != null && item.year != null && year != item.year) return false;
      return true;
    }).toList();

    return byTitle.length == 1 ? byTitle.single.item : null;
  }

  bool _sharesExternalId(ExternalIds other) {
    final imdb = externalIds.imdb;
    if (imdb != null && imdb.isNotEmpty && other.imdb == imdb) return true;
    final tmdb = externalIds.tmdb;
    if (tmdb != null && other.tmdb == tmdb) return true;
    final tvdb = externalIds.tvdb;
    if (tvdb != null && other.tvdb == tvdb) return true;
    return false;
  }

  /// Whether there is anything at all to match on. An identity without guid,
  /// external id or title cannot be looked up and should not cost a request.
  bool get isSearchable => (guid != null && guid!.isNotEmpty) || externalIds.hasAny || (title?.isNotEmpty ?? false);

  @override
  String toString() => 'MediaIdentity(${guid ?? title ?? '?'}${year != null ? ' ($year)' : ''})';
}
