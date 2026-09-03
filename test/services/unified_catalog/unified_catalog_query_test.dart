import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';

MediaItem _item(
  String id, {
  int? addedAt,
  String? originallyAvailableAt,
  int? year,
  int? lastViewedAt,
  String title = 'X',
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: 's1',
  addedAt: addedAt,
  originallyAvailableAt: originallyAvailableAt,
  year: year,
  lastViewedAt: lastViewedAt,
);

void main() {
  group('UnifiedCatalogQuery.toLibraryQuery', () {
    test('carries the sort field/direction and passthrough filters into the per-library request', () {
      const query = UnifiedCatalogQuery(
        kind: MediaKind.show,
        sortField: UnifiedCatalogSortField.addedAt,
        sortDirection: LibrarySortDirection.descending,
        favoritesOnly: true,
      );

      final libraryQuery = query.toLibraryQuery(offset: 40, limit: 20);

      expect(libraryQuery.kind, MediaKind.show);
      expect(libraryQuery.offset, 40);
      expect(libraryQuery.limit, 20);
      expect(libraryQuery.sort?.field, 'addedAt');
      expect(libraryQuery.sort?.direction, LibrarySortDirection.descending);
      expect(libraryQuery.favoritesOnly, isTrue);
    });
  });

  group('unifiedCatalogItemComparator', () {
    test('release-date sort compares the full originallyAvailableAt date, not just the year', () {
      const query = UnifiedCatalogQuery(kind: MediaKind.movie, sortField: UnifiedCatalogSortField.releaseDate);
      final compare = unifiedCatalogItemComparator(query);

      // Same year, different months — a year-only comparator would tie these
      // and fall through to an arbitrary server/library tie-break instead of
      // the actual chronological order the server was asked to sort by.
      final january = _item('jan', originallyAvailableAt: '2020-01-15', year: 2020);
      final november = _item('nov', originallyAvailableAt: '2020-11-03', year: 2020);

      expect(compare(january, november), lessThan(0));
      expect(compare(november, january), greaterThan(0));
    });

    test('release-date sort sinks a dateless item to the end regardless of direction', () {
      final dated = _item('dated', originallyAvailableAt: '2020-01-15');
      final dateless = _item('dateless');

      const ascending = UnifiedCatalogQuery(kind: MediaKind.movie, sortField: UnifiedCatalogSortField.releaseDate);
      const descending = UnifiedCatalogQuery(
        kind: MediaKind.movie,
        sortField: UnifiedCatalogSortField.releaseDate,
        sortDirection: LibrarySortDirection.descending,
      );

      expect(unifiedCatalogItemComparator(ascending)(dateless, dated), greaterThan(0));
      expect(unifiedCatalogItemComparator(descending)(dateless, dated), greaterThan(0));
    });

    test('title sort is case- and diacritic-insensitive via titleSort/normalizeTitleForMatching', () {
      const query = UnifiedCatalogQuery(kind: MediaKind.movie);
      final compare = unifiedCatalogItemComparator(query);

      expect(compare(_item('a', title: 'apple'), _item('b', title: 'Banana')), lessThan(0));
      expect(compare(_item('a', title: 'Apple'), _item('b', title: 'apple')), 0);
    });

    test('addedAt sort sinks a missing value to the end', () {
      const query = UnifiedCatalogQuery(kind: MediaKind.movie, sortField: UnifiedCatalogSortField.addedAt);
      final compare = unifiedCatalogItemComparator(query);

      expect(compare(_item('no-date'), _item('dated', addedAt: 100)), greaterThan(0));
    });

    test('recentlyWatched sort compares lastViewedAt, missing sinks to the end', () {
      const query = UnifiedCatalogQuery(
        kind: MediaKind.movie,
        sortField: UnifiedCatalogSortField.recentlyWatched,
        sortDirection: LibrarySortDirection.descending,
      );
      final compare = unifiedCatalogItemComparator(query);

      expect(compare(_item('recent', lastViewedAt: 200), _item('older', lastViewedAt: 100)), lessThan(0));
      expect(compare(_item('never-watched'), _item('watched', lastViewedAt: 100)), greaterThan(0));
    });
  });

  group('UnifiedCatalogQuery equality', () {
    test('two queries with the same fields are equal and hash the same', () {
      const a = UnifiedCatalogQuery(kind: MediaKind.movie, genres: ['Action']);
      const b = UnifiedCatalogQuery(kind: MediaKind.movie, genres: ['Action']);

      expect(a, b);
      expect(a.hashCode, b.hashCode);
    });

    test('a different filter list makes two queries unequal', () {
      const a = UnifiedCatalogQuery(kind: MediaKind.movie, genres: ['Action']);
      const b = UnifiedCatalogQuery(kind: MediaKind.movie, genres: ['Comedy']);

      expect(a == b, isFalse);
    });
  });
}
