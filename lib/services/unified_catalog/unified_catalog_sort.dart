/// The orders a catalog can stand in, as one stable stored name each.
library;

import '../../media/library_query.dart';
import 'unified_catalog_query.dart';

/// One order a catalog can stand in.
///
/// An enum rather than a free (field, direction) pair because the pair has
/// combinations the contract does not offer — "oudst bekeken" is expressible
/// and meaningless — and because a stored preference needs a stable name to
/// serialise on. The scores are here since DEC-XXX replaced the condition of
/// hoofdstuk 10.5: they share one scale before the merge
/// (`media/catalog_score.dart`), and a unified score sort knowingly compares two
/// different sources.
enum UnifiedCatalogSort {
  titleAsc(UnifiedCatalogSortField.title, LibrarySortDirection.ascending),
  titleDesc(UnifiedCatalogSortField.title, LibrarySortDirection.descending),
  recentlyAdded(UnifiedCatalogSortField.addedAt, LibrarySortDirection.descending),
  oldestAdded(UnifiedCatalogSortField.addedAt, LibrarySortDirection.ascending),
  newestRelease(UnifiedCatalogSortField.releaseDate, LibrarySortDirection.descending),
  oldestRelease(UnifiedCatalogSortField.releaseDate, LibrarySortDirection.ascending),
  recentlyWatched(UnifiedCatalogSortField.recentlyWatched, LibrarySortDirection.descending),
  yearNewest(UnifiedCatalogSortField.year, LibrarySortDirection.descending),
  yearOldest(UnifiedCatalogSortField.year, LibrarySortDirection.ascending),
  criticHighest(UnifiedCatalogSortField.criticRating, LibrarySortDirection.descending),
  criticLowest(UnifiedCatalogSortField.criticRating, LibrarySortDirection.ascending),
  audienceHighest(UnifiedCatalogSortField.audienceRating, LibrarySortDirection.descending),
  audienceLowest(UnifiedCatalogSortField.audienceRating, LibrarySortDirection.ascending),
  userRatingHighest(UnifiedCatalogSortField.userRating, LibrarySortDirection.descending),
  userRatingLowest(UnifiedCatalogSortField.userRating, LibrarySortDirection.ascending),
  contentRatingYoungest(UnifiedCatalogSortField.contentRating, LibrarySortDirection.ascending),
  contentRatingOldest(UnifiedCatalogSortField.contentRating, LibrarySortDirection.descending),
  longest(UnifiedCatalogSortField.duration, LibrarySortDirection.descending),
  shortest(UnifiedCatalogSortField.duration, LibrarySortDirection.ascending),
  mostProgress(UnifiedCatalogSortField.progress, LibrarySortDirection.descending),
  leastProgress(UnifiedCatalogSortField.progress, LibrarySortDirection.ascending),
  mostPlayed(UnifiedCatalogSortField.plays, LibrarySortDirection.descending),
  leastPlayed(UnifiedCatalogSortField.plays, LibrarySortDirection.ascending),
  highestResolution(UnifiedCatalogSortField.resolution, LibrarySortDirection.descending),
  lowestResolution(UnifiedCatalogSortField.resolution, LibrarySortDirection.ascending);

  const UnifiedCatalogSort(this.field, this.direction);

  final UnifiedCatalogSortField field;
  final LibrarySortDirection direction;

  /// The sorts a list of named directions offers (the phone's sheet, the Home
  /// row wizard). Only the full-bleed catalog's page has the room for every
  /// field, with one row and an arrow each.
  static const List<UnifiedCatalogSort> named = [
    titleAsc,
    titleDesc,
    recentlyAdded,
    oldestAdded,
    newestRelease,
    oldestRelease,
    recentlyWatched,
  ];

  static UnifiedCatalogSort? byName(String? name) {
    if (name == null) return null;
    for (final sort in values) {
      if (sort.name == name) return sort;
    }
    return null;
  }
}
