import '../../media/library_query.dart';
import '../../media/media_item.dart';
import '../../media/media_kind.dart';
import '../unified_catalog/unified_catalog_query.dart';

/// Returns null for predicates this local projection cannot honestly execute.
/// Callers may use the online query instead; offline they show unavailable.
List<MediaItem>? queryLocalLibrary(List<MediaItem> items, LibraryQuery query) {
  if (query.filters.isNotEmpty || query.favoritesOnly || (query.audioLanguages?.isNotEmpty ?? false)) return null;
  final sortField = query.sort?.field == 'titleSort' ? 'title' : query.sort?.field ?? 'title';
  final field = UnifiedCatalogSortField.values.where((f) => f.libraryQueryField == sortField).firstOrNull;
  if (field == null) return null;
  final needle = query.search?.trim().toLowerCase() ?? '';
  bool any(List<String>? selected, List<String>? actual) =>
      selected == null ||
      selected.isEmpty ||
      selected.every((s) => actual?.any((a) => a.toLowerCase() == s.toLowerCase()) ?? false);
  final result = items.where((item) {
    if (query.kind != null && item.kind != query.kind) return false;
    final watched = (item.viewCount ?? 0) > 0 || ((item.leafCount ?? 0) > 0 && item.viewedLeafCount == item.leafCount);
    if (!query.includeWatched && watched || query.watchedOnly && !watched) return false;
    if (query.inProgressOnly && ((item.viewOffsetMs ?? 0) <= 0 || watched)) return false;
    if (needle.isNotEmpty && !item.displayTitle.toLowerCase().contains(needle)) return false;
    if (!any(query.genres, item.genres) || !any(query.tags, item.labels)) return false;
    if ((query.years?.isNotEmpty ?? false) && !query.years!.contains(item.year)) return false;
    if ((query.officialRatings?.isNotEmpty ?? false) && !query.officialRatings!.contains(item.contentRating))
      return false;
    final prefix = query.nameStartsWith?.toLowerCase();
    if (prefix != null && prefix.isNotEmpty) {
      final title = (item.titleSort ?? item.displayTitle).toLowerCase();
      if (prefix == '#' ? RegExp(r'^[a-z]').hasMatch(title) : !title.startsWith(prefix)) return false;
    }
    return true;
  }).toList();
  result.sort(
    unifiedCatalogItemComparator(
      UnifiedCatalogQuery(
        kind: query.kind ?? MediaKind.movie,
        sortField: field,
        sortDirection: query.sort?.direction ?? LibrarySortDirection.ascending,
      ),
    ),
  );
  return result;
}
