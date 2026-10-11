import 'trakt_ids.dart';

/// One title from a Trakt list (watched or watchlist): only what mapping to a
/// library needs, never the per-episode tree.
class TraktTitle {
  const TraktTitle({required this.title, required this.ids, required this.isShow, this.year, this.at});

  final String title;
  final int? year;
  final TraktIds ids;
  final bool isShow;

  /// `last_watched_at` or `listed_at`, as Trakt sent it.
  final String? at;

  /// A list entry wrapped under `movie` or `show`; null when it has no usable
  /// title or no `ids` map. Entries are skipped, never
  /// failed on, so one odd row does not hide a whole list.
  static TraktTitle? fromEntry(Object? entry, {required bool isShow}) {
    if (entry is! Map) return null;
    final inner = entry[isShow ? 'show' : 'movie'];
    if (inner is! Map) return null;
    final title = inner['title'];
    final rawIds = inner['ids'];
    if (title is! String || title.trim().isEmpty || rawIds is! Map) return null;
    final ids = TraktIds(
      trakt: _int(rawIds['trakt']),
      slug: rawIds['slug'] is String ? rawIds['slug'] as String : null,
      imdb: rawIds['imdb'] is String && (rawIds['imdb'] as String).isNotEmpty ? rawIds['imdb'] as String : null,
      tmdb: _int(rawIds['tmdb']),
      tvdb: _int(rawIds['tvdb']),
    );
    final at = entry['last_watched_at'] ?? entry['listed_at'];
    return TraktTitle(
      title: title.trim(),
      year: _int(inner['year']),
      ids: ids,
      isShow: isShow,
      at: at is String ? at : null,
    );
  }

  static int? _int(Object? v) => v is int ? v : (v is num ? v.toInt() : null);
}
