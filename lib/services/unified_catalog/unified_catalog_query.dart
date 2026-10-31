/// The neutral request describing what a unified catalog session shows
/// (hoofdstuk 10.1/12 of docs/tvos-unified-experience.md): a movie or show
/// catalog, backend-neutral sort/filter, across every eligible library on
/// every eligible server. Distinct from [LibraryQuery], which is the
/// *per-library* page request one `UnifiedSourceCursor` issues — this type
/// carries no offset/limit of its own; [toLibraryQuery] is the only place a
/// concrete per-library page request gets built from it.
library;

import '../../media/catalog_score.dart';
import '../../media/library_query.dart';
import '../../media/media_backend.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../media/media_version.dart';
import '../../utils/title_normalizer.dart';
import 'content_rating_labels.dart';

/// Every order a unified catalog can stand in, plus the neutral
/// [LibraryQuery.sort] field name each maps to. [UnifiedCatalogQuery.sortField]
/// must name one of these — the unified k-way merge needs every
/// participating library to produce items in one *globally* comparable
/// order, which "random" (a valid single-library [LibrarySort.field]) can
/// never give.
///
/// `librarySortMenu` in `media/library_menu_definition.dart` holds the order of
/// the sort page. Which backends can run a field is
/// [UnifiedFilterCapabilities.supportsSort]; the two translators in
/// `library_query_translator.dart` spell the field per backend.
enum UnifiedCatalogSortField {
  title('title'),
  year('year'),
  releaseDate('originallyAvailableAt'),
  criticRating('criticRating'),
  audienceRating('audienceRating'),
  userRating('userRating'),
  contentRating('contentRating'),
  duration('duration'),
  progress('viewOffset'),
  plays('viewCount'),
  addedAt('addedAt'),
  recentlyWatched('lastViewedAt'),
  resolution('mediaHeight');

  const UnifiedCatalogSortField(this.libraryQueryField);

  final String libraryQueryField;
}

class UnifiedCatalogQuery {
  /// The unified catalog is always exactly one kind — Films or Series
  /// (hoofdstuk 10.1) — never a mixed browse; that stays Bibliotheken's job
  /// (hoofdstuk 4.5/DEC-063 point 5).
  final MediaKind kind;

  final UnifiedCatalogSortField sortField;
  final LibrarySortDirection sortDirection;
  final List<LibraryFilter> filters;
  final String? search;
  final bool includeWatched;
  final bool favoritesOnly;
  final bool inProgressOnly;
  final bool watchedOnly;
  final String? nameStartsWith;
  final List<String>? genres;
  final List<String>? audioLanguages;
  final List<String>? officialRatings;
  final List<int>? years;
  final List<String>? tags;

  const UnifiedCatalogQuery({
    required this.kind,
    this.sortField = UnifiedCatalogSortField.title,
    this.sortDirection = LibrarySortDirection.ascending,
    this.filters = const [],
    this.search,
    this.includeWatched = true,
    this.favoritesOnly = false,
    this.inProgressOnly = false,
    this.watchedOnly = false,
    this.nameStartsWith,
    this.genres,
    this.audioLanguages,
    this.officialRatings,
    this.years,
    this.tags,
  });

  /// The per-library page request one `UnifiedSourceCursor` issues for
  /// [offset]/[limit] — this query translated into the shape
  /// [MediaServerClient.fetchLibraryPagedContent] expects (the caller also
  /// passes [kind] separately as that method's own `libraryKind`, to
  /// disambiguate a Jellyfin "Shows" library into Series rows). Every
  /// participating library gets exactly this same query (hoofdstuk 12.2:
  /// "Iedere deelnemende library levert dezelfde neutrale sorteerquery"), so
  /// the k-way merge can trust that each cursor's buffer arrives already
  /// sorted the same way.
  LibraryQuery toLibraryQuery({required int offset, required int limit}) => LibraryQuery(
    kind: kind,
    offset: offset,
    limit: limit,
    sort: LibrarySort(field: sortField.libraryQueryField, direction: sortDirection),
    filters: filters,
    search: search,
    includeWatched: includeWatched,
    favoritesOnly: favoritesOnly,
    inProgressOnly: inProgressOnly,
    watchedOnly: watchedOnly,
    nameStartsWith: nameStartsWith,
    genres: genres,
    audioLanguages: audioLanguages,
    officialRatings: officialRatings,
    years: years,
    tags: tags,
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedCatalogQuery &&
          other.kind == kind &&
          other.sortField == sortField &&
          other.sortDirection == sortDirection &&
          _listEquals(other.filters, filters) &&
          other.search == search &&
          other.includeWatched == includeWatched &&
          other.favoritesOnly == favoritesOnly &&
          other.inProgressOnly == inProgressOnly &&
          other.watchedOnly == watchedOnly &&
          other.nameStartsWith == nameStartsWith &&
          _listEquals(other.genres, genres) &&
          _listEquals(other.audioLanguages, audioLanguages) &&
          _listEquals(other.officialRatings, officialRatings) &&
          _listEquals(other.years, years) &&
          _listEquals(other.tags, tags);

  @override
  int get hashCode => Object.hash(
    kind,
    sortField,
    sortDirection,
    Object.hashAll(filters),
    search,
    includeWatched,
    favoritesOnly,
    inProgressOnly,
    watchedOnly,
    nameStartsWith,
    genres == null ? null : Object.hashAll(genres!),
    audioLanguages == null ? null : Object.hashAll(audioLanguages!),
    officialRatings == null ? null : Object.hashAll(officialRatings!),
    years == null ? null : Object.hashAll(years!),
    tags == null ? null : Object.hashAll(tags!),
  );

  @override
  String toString() => 'UnifiedCatalogQuery(${kind.id}, ${sortField.name} ${sortDirection.name})';
}

bool _listEquals<T>(List<T>? a, List<T>? b) {
  if (identical(a, b)) return true;
  if (a == null || b == null) return false;
  if (a.length != b.length) return false;
  for (var i = 0; i < a.length; i++) {
    if (a[i] != b[i]) return false;
  }
  return true;
}

/// What [field] orders [item] on, or null when the item has no value for it.
///
/// One function for the comparator and for the merge's question of which items
/// have nothing to sort on, so the two cannot disagree. The numeric fields treat
/// zero as absent: Plex leaves `viewCount` out where Jellyfin sends 0, and a
/// title nobody has played has no play count to order by on either.
Object? _sortKey(MediaItem item, UnifiedCatalogSortField field) {
  int? positive(int? value) => value != null && value > 0 ? value : null;

  return switch (field) {
    UnifiedCatalogSortField.title => switch (normalizeTitleForMatching(item.titleSort ?? item.title)) {
      '' => null,
      final title => title,
    },
    UnifiedCatalogSortField.year => positive(item.year),
    // The server-side sort is the full `originallyAvailableAt` date, so the
    // merge compares at that granularity: comparing only MediaItem.year would
    // tie two same-year, different-month items from different libraries and
    // let the server tie-break decide instead of the date.
    UnifiedCatalogSortField.releaseDate => DateTime.tryParse(item.originallyAvailableAt ?? ''),
    UnifiedCatalogSortField.criticRating => catalogCriticScore(item)?.percent,
    UnifiedCatalogSortField.audienceRating => catalogAudienceScore(item)?.percent,
    UnifiedCatalogSortField.userRating => catalogUserScore(item)?.percent,
    UnifiedCatalogSortField.contentRating => switch (item.contentRating) {
      null || '' => null,
      final rating => contentRatingLabel(rating),
    },
    UnifiedCatalogSortField.duration => positive(item.durationMs),
    UnifiedCatalogSortField.progress => positive(item.viewOffsetMs),
    UnifiedCatalogSortField.plays => positive(item.viewCount),
    UnifiedCatalogSortField.addedAt => item.addedAt,
    UnifiedCatalogSortField.recentlyWatched => item.lastViewedAt,
    UnifiedCatalogSortField.resolution => _tallestVersion(item),
  };
}

/// The best version's height, which is the resolution a title can be seen in.
int? _tallestVersion(MediaItem item) {
  int? tallest;
  for (final version in item.mediaVersions ?? const <MediaVersion>[]) {
    final height = version.height;
    if (height != null && height > 0 && (tallest == null || height > tallest)) tallest = height;
  }
  return tallest;
}

/// Whether [item] has anything to sort on under [field].
bool unifiedCatalogHasSortValue(MediaItem item, UnifiedCatalogSortField field) => _sortKey(item, field) != null;

/// Whether an item without a key under [field] truly has no value on [backend].
///
/// True means the merge can both correct a server that sends such an item first
/// and rank it against another source. False where the server sorts series on
/// something the mapped item does not carry:
///
/// * Jellyfin orders series on `SeriesDatePlayed`, worked out from the episodes,
///   while the item's own `UserData.LastPlayedDate` stays empty on a series.
/// * Pleya Server orders a show's last played date and duration on its episodes
///   (`keyExpression`, `subjectKey` in `catalog/cursor.go`), and those two carry a
///   sentinel that puts titles without a value last in both directions.
/// * Jellyfin's `PlayCount` on a series: `JellyfinMappers._viewCount` reads 0 unless
///   `UserData.Played` is set, which a series with one episode watched is not.
///   The demo server had nothing watched on 31 October 2026, so whether the
///   server's own count stays 0 there is unmeasured, and the row stays for one
///   library.
///
/// One library then keeps the server's order untouched, and two sources cannot
/// be ranked on that field at all: `unifiedFilterCapabilitiesFor` takes it away.
/// [kind] is null where a caller asks without a kind, which reads as films.
///
/// Never for title, which holds nothing back: an untitled row is rare, and the
/// comparator sinks it anyway.
bool unifiedCatalogKeyProvesNoValue(UnifiedCatalogSortField field, MediaKind? kind, MediaBackend backend) =>
    switch ((field, backend)) {
      (UnifiedCatalogSortField.title, _) => false,
      (UnifiedCatalogSortField.recentlyWatched, MediaBackend.jellyfin || MediaBackend.pleyaServer) ||
      (UnifiedCatalogSortField.duration, MediaBackend.pleyaServer) ||
      (UnifiedCatalogSortField.plays, MediaBackend.jellyfin) => kind != MediaKind.show,
      _ => true,
    };

/// The per-item comparator for one sort — the k-way merge's head-to-head
/// comparison (hoofdstuk 12.2). Applied to raw items *before* grouping, so it
/// necessarily reads each item's own value: a group's true key (hoofdstuk 12.4
/// — e.g. the *highest* addedAt across every member) can only be known once
/// every source has been seen, which is exactly why a late duplicate with a
/// materially different value surfaces many pages later instead of merging on
/// sight (hoofdstuk 12.5).
///
/// A missing value on the requested field always sinks to the end regardless
/// of direction — pinning a "dateless" item to the top of a descending
/// "recently added" list would be actively misleading, matching the
/// sink-to-bottom convention `getLatestMoviesFromAllServers` already uses for
/// the same reason.
///
/// Equal values read in title order, whichever way the field runs (`04.png`:
/// Year descending, the 2026 films from A). That is what makes the sources of a
/// merge interleave, and what orders the titles without a value among themselves.
int Function(MediaItem a, MediaItem b) unifiedCatalogSortComparator(
  UnifiedCatalogSortField field,
  LibrarySortDirection sortDirection,
) {
  final sign = sortDirection == LibrarySortDirection.ascending ? 1 : -1;

  int compareOn(UnifiedCatalogSortField on, int direction, MediaItem a, MediaItem b) {
    final ka = _sortKey(a, on);
    final kb = _sortKey(b, on);
    if (ka == null && kb == null) return 0;
    if (ka == null) return 1;
    if (kb == null) return -1;
    final cmp = on == UnifiedCatalogSortField.contentRating
        ? compareContentRatingLabels(ka as String, kb as String)
        : (ka as Comparable<Object>).compareTo(kb);
    return direction * cmp;
  }

  return (a, b) {
    final cmp = compareOn(field, sign, a, b);
    if (cmp != 0 || field == UnifiedCatalogSortField.title) return cmp;
    return compareOn(UnifiedCatalogSortField.title, 1, a, b);
  };
}

/// [unifiedCatalogSortComparator] for one [UnifiedCatalogQuery].
int Function(MediaItem a, MediaItem b) unifiedCatalogItemComparator(UnifiedCatalogQuery query) =>
    unifiedCatalogSortComparator(query.sortField, query.sortDirection);
