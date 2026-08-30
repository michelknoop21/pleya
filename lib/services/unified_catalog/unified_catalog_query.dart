/// The neutral request describing what a unified catalog session shows
/// (hoofdstuk 10.1/12 of docs/tvos-unified-experience.md): a movie or show
/// catalog, backend-neutral sort/filter, across every eligible library on
/// every eligible server. Distinct from [LibraryQuery], which is the
/// *per-library* page request one `UnifiedSourceCursor` issues — this type
/// carries no offset/limit of its own; [toLibraryQuery] is the only place a
/// concrete per-library page request gets built from it.
library;

import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../../utils/title_normalizer.dart';

/// hoofdstuk 12.4's four documented group-sort-key cases, plus the
/// [LibraryQuery.sort] field name each maps to. [UnifiedCatalogQuery.sortField]
/// must name one of these — the unified k-way merge needs every
/// participating library to produce items in one *globally* comparable
/// order, which "random" (a valid single-library [LibrarySort.field]) can
/// never give.
enum UnifiedCatalogSortField {
  title('title'),
  addedAt('addedAt'),
  releaseDate('originallyAvailableAt'),
  recentlyWatched('lastViewedAt');

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
  final String? nameStartsWith;
  final List<String>? genres;
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
    this.nameStartsWith,
    this.genres,
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
    nameStartsWith: nameStartsWith,
    genres: genres,
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
          other.nameStartsWith == nameStartsWith &&
          _listEquals(other.genres, genres) &&
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
    nameStartsWith,
    genres == null ? null : Object.hashAll(genres!),
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

/// The per-item comparator for one [UnifiedCatalogQuery]'s sort — the k-way
/// merge's head-to-head comparison (hoofdstuk 12.2). Applied to raw items
/// *before* grouping, so it necessarily reads each item's own value: a
/// group's true key (hoofdstuk 12.4 — e.g. the *highest* addedAt across every
/// member) can only be known once every source has been seen, which is
/// exactly why a late duplicate with a materially different value surfaces
/// many pages later instead of merging on sight (hoofdstuk 12.5).
///
/// A missing value on the requested field always sinks to the end regardless
/// of direction — pinning a "dateless" item to the top of a descending
/// "recently added" list would be actively misleading, matching the
/// sink-to-bottom convention `getLatestMoviesFromAllServers` already uses for
/// the same reason.
int Function(MediaItem a, MediaItem b) unifiedCatalogItemComparator(UnifiedCatalogQuery query) {
  final ascending = query.sortDirection == LibrarySortDirection.ascending;
  int direction(int cmp) => ascending ? cmp : -cmp;

  int compareNullableInt(int? a, int? b) {
    if (a == null && b == null) return 0;
    if (a == null) return 1;
    if (b == null) return -1;
    return direction(a.compareTo(b));
  }

  int compareTitle(MediaItem a, MediaItem b) {
    final ta = normalizeTitleForMatching(a.titleSort ?? a.title);
    final tb = normalizeTitleForMatching(b.titleSort ?? b.title);
    if (ta.isEmpty && tb.isEmpty) return 0;
    if (ta.isEmpty) return 1;
    if (tb.isEmpty) return -1;
    return direction(ta.compareTo(tb));
  }

  // The server-side sort this field requests is the full
  // `originallyAvailableAt` date (see UnifiedCatalogSortField.releaseDate's
  // libraryQueryField), so the client-side merge comparator must compare at
  // that same granularity — comparing only MediaItem.year would tie two
  // same-year, different-month items from different libraries and let an
  // arbitrary server/library tie-break decide their order instead of the
  // date the server actually sorted by.
  int compareReleaseDate(MediaItem a, MediaItem b) {
    final da = DateTime.tryParse(a.originallyAvailableAt ?? '');
    final db = DateTime.tryParse(b.originallyAvailableAt ?? '');
    if (da == null && db == null) return 0;
    if (da == null) return 1;
    if (db == null) return -1;
    return direction(da.compareTo(db));
  }

  return (a, b) => switch (query.sortField) {
    UnifiedCatalogSortField.title => compareTitle(a, b),
    UnifiedCatalogSortField.addedAt => compareNullableInt(a.addedAt, b.addedAt),
    UnifiedCatalogSortField.releaseDate => compareReleaseDate(a, b),
    UnifiedCatalogSortField.recentlyWatched => compareNullableInt(a.lastViewedAt, b.lastViewedAt),
  };
}
