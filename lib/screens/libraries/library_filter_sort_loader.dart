import '../../media/library_filter_result.dart';
import '../../media/library_menu_definition.dart';
import '../../media/media_filter.dart';
import '../../media/media_library.dart';
import '../../media/media_server_client.dart';
import '../../media/media_sort.dart';

/// Combined filter + sort listing loaded for a [MediaLibrary].
///
/// Plex returns categories from `/library/sections/{id}/filters` and sort
/// options from `/library/sections/{id}/sorts` separately, with values
/// fetched lazily per-category via `FiltersBottomSheet`. Jellyfin returns
/// categories *and* values together via `/Items/Filters` (so [cachedValues]
/// is populated up-front) and has no sort-listing endpoint, so its sorts
/// come from a client-side hardcoded list.
class LoadedFiltersAndSorts {
  final List<MediaFilter> filters;
  final List<MediaSort> sorts;
  final Map<String, List<MediaFilterValue>> cachedValues;

  const LoadedFiltersAndSorts({required this.filters, required this.sorts, this.cachedValues = const {}});
}

/// Loads filter categories and sort options for a [MediaLibrary] across both
/// backends through the unified [MediaServerClient] interface — Plex pulls
/// categories with no values (FiltersBottomSheet fetches lazily), Jellyfin
/// pre-populates [cachedValues] from `/Items/Filters`. [clientFor] resolves
/// the right concrete client for the library being loaded.
class LibraryFilterSortLoader {
  final MediaServerClient Function(MediaLibrary library) clientFor;

  LibraryFilterSortLoader({required this.clientFor});

  Future<LoadedFiltersAndSorts> load(MediaLibrary library) async {
    // Future.wait and not a record's `.wait`: that wraps a failure in a
    // ParallelWaitError, and `friendlyError` would lose the specific message.
    final filters = loadFilters(library);
    final sorts = loadSorts(library);
    await Future.wait([filters, sorts]);
    final filterResult = await filters;
    return LoadedFiltersAndSorts(
      filters: filterResult.filters,
      sorts: await sorts,
      cachedValues: filterResult.cachedValues,
    );
  }

  /// The sorts alone, in the shared menu's order and words, for a Jellyfin page 1
  /// that cannot wait for `/Items/Filters`.
  Future<List<MediaSort>> loadSorts(MediaLibrary library) async => libraryMenuOrderedSorts(
    await clientFor(library).fetchSortOptions(library.id, libraryType: library.kind.id),
    backend: library.backend,
  );

  /// The filters alone, in the same menu's order and words: the other half of
  /// that Jellyfin path. Every filter the server lists stays.
  Future<LibraryFilterResult> loadFilters(MediaLibrary library) async {
    final result = await clientFor(library).fetchLibraryFiltersWithValues(library.id);
    return LibraryFilterResult(filters: libraryMenuOrderedFilters(result.filters), cachedValues: result.cachedValues);
  }
}
