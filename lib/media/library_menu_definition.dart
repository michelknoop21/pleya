/// The one definition of what the Sort and Filter menus of a library list are
/// called and in which order they stand (Michel, 30 October 2026). tvOS draws it
/// now; the iPhone can draw the same lists, because nothing here knows a widget.
///
/// **A backend never decides the order or the words.** It only says whether an
/// option can run: `UnifiedFilterCapabilities` and `LibraryMenuSupport`. An
/// option no backend can truly execute is left out, never imitated on the client
/// over the pages that happen to be loaded.
library;

import '../i18n/strings.g.dart';
import '../services/unified_catalog/unified_catalog_query.dart';
import 'media_sort.dart';

/// The rows of Sorteren op, top to bottom.
const List<UnifiedCatalogSortField> librarySortMenu = [
  UnifiedCatalogSortField.title,
  UnifiedCatalogSortField.year,
  UnifiedCatalogSortField.releaseDate,
  UnifiedCatalogSortField.criticRating,
  UnifiedCatalogSortField.audienceRating,
  UnifiedCatalogSortField.userRating,
  UnifiedCatalogSortField.contentRating,
  UnifiedCatalogSortField.duration,
  UnifiedCatalogSortField.progress,
  UnifiedCatalogSortField.plays,
  UnifiedCatalogSortField.addedAt,
  UnifiedCatalogSortField.recentlyWatched,
  UnifiedCatalogSortField.resolution,
];

String librarySortFieldLabel(UnifiedCatalogSortField field) => switch (field) {
  UnifiedCatalogSortField.title => t.unifiedCatalog.sort.fields.title,
  UnifiedCatalogSortField.year => t.unifiedCatalog.sort.fields.year,
  UnifiedCatalogSortField.releaseDate => t.unifiedCatalog.sort.fields.releaseDate,
  UnifiedCatalogSortField.criticRating => t.unifiedCatalog.sort.fields.criticRating,
  UnifiedCatalogSortField.audienceRating => t.unifiedCatalog.sort.fields.audienceRating,
  UnifiedCatalogSortField.userRating => t.unifiedCatalog.sort.fields.userRating,
  UnifiedCatalogSortField.contentRating => t.unifiedCatalog.sort.fields.contentRating,
  UnifiedCatalogSortField.duration => t.unifiedCatalog.sort.fields.duration,
  UnifiedCatalogSortField.progress => t.unifiedCatalog.sort.fields.progress,
  UnifiedCatalogSortField.plays => t.unifiedCatalog.sort.fields.plays,
  UnifiedCatalogSortField.addedAt => t.unifiedCatalog.sort.fields.addedAt,
  UnifiedCatalogSortField.recentlyWatched => t.unifiedCatalog.sort.fields.recentlyWatched,
  UnifiedCatalogSortField.resolution => t.unifiedCatalog.sort.fields.resolution,
};

/// The key a Plex server lists [field] under in
/// `/library/sections/{id}/sorts`.
String plexSortKeyFor(UnifiedCatalogSortField field) => switch (field) {
  UnifiedCatalogSortField.title => 'titleSort',
  UnifiedCatalogSortField.criticRating => 'rating',
  _ => field.libraryQueryField,
};

/// Keys of a backend's own sort list in the order of [librarySortMenu].
/// `rating` stands after the critics key on purpose: it is the critic score on
/// Plex and the community score on Jellyfin, and both then land on their row.
const List<String> _sortKeyOrder = [
  'title',
  'titleSort',
  'year',
  'productionYear',
  'originallyAvailableAt',
  'premiereDate',
  'criticRating',
  'rating',
  'communityRating',
  'audienceRating',
  'userRating',
  'contentRating',
  'officialRating',
  'duration',
  'runtime',
  'viewOffset',
  'viewCount',
  'playCount',
  'addedAt',
  'dateCreated',
  'lastViewedAt',
  'datePlayed',
  'mediaHeight',
];

/// A per-library list of sorts, as `MediaServerClient.fetchSortOptions` gives
/// it, in the menu's order. What has no place in the definition (Willekeurig,
/// Studio, Begindatum, Uitzendtijd) keeps its order at the bottom: it does not
/// go away. For a list of one library only. A merged catalog cannot run those:
/// Random has no order two sources could agree on.
List<MediaSort> libraryMenuOrderedSorts(List<MediaSort> sorts) {
  int rank(MediaSort sort) {
    final index = _sortKeyOrder.indexOf(sort.key);
    return index < 0 ? _sortKeyOrder.length : index;
  }

  final indexed = [for (var i = 0; i < sorts.length; i++) (i, sorts[i])];
  indexed.sort((a, b) {
    final cmp = rank(a.$2).compareTo(rank(b.$2));
    return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
  });
  return [for (final entry in indexed) entry.$2];
}

/// The quick choices at the top of Filteren op. One at a time: Alles carries
/// the tick while none of the others does.
enum LibraryQuickFilter {
  all,
  hdr,
  dolbyVision,
  hdr10Plus,
  atmos,
  unwatched,
  inProgress,
  unmatched,
  duplicates,
  watched,
}

/// The quick rows, top to bottom. Bekeken has no place in the definition and
/// stays at the bottom, on the backends that can run it.
const List<LibraryQuickFilter> libraryQuickFilterMenu = [
  LibraryQuickFilter.all,
  LibraryQuickFilter.hdr,
  LibraryQuickFilter.dolbyVision,
  LibraryQuickFilter.hdr10Plus,
  LibraryQuickFilter.atmos,
  LibraryQuickFilter.unwatched,
  LibraryQuickFilter.inProgress,
  LibraryQuickFilter.unmatched,
  LibraryQuickFilter.duplicates,
  LibraryQuickFilter.watched,
];

String libraryQuickFilterLabel(LibraryQuickFilter filter) => switch (filter) {
  LibraryQuickFilter.all => t.unifiedCatalog.filters.quick.all,
  LibraryQuickFilter.hdr => t.unifiedCatalog.filters.quick.hdr,
  LibraryQuickFilter.dolbyVision => t.unifiedCatalog.filters.quick.dolbyVision,
  LibraryQuickFilter.hdr10Plus => t.unifiedCatalog.filters.quick.hdr10Plus,
  LibraryQuickFilter.atmos => t.unifiedCatalog.filters.quick.atmos,
  LibraryQuickFilter.unwatched => t.unifiedCatalog.filters.quick.unwatched,
  LibraryQuickFilter.inProgress => t.unifiedCatalog.filters.quick.inProgress,
  LibraryQuickFilter.unmatched => t.unifiedCatalog.filters.quick.unmatched,
  LibraryQuickFilter.duplicates => t.unifiedCatalog.filters.quick.duplicates,
  LibraryQuickFilter.watched => t.unifiedCatalog.filters.quick.watched,
};

/// The quick choices that are a property of the media rather than of the
/// viewing, which is every one that is not a watch state.
const Set<LibraryQuickFilter> libraryMediaQuickFilters = {
  LibraryQuickFilter.hdr,
  LibraryQuickFilter.dolbyVision,
  LibraryQuickFilter.hdr10Plus,
  LibraryQuickFilter.atmos,
  LibraryQuickFilter.unmatched,
  LibraryQuickFilter.duplicates,
};

/// The boolean filter a Plex section lists [filter] under in
/// `/library/sections/{id}/filters`, or null when no key is known.
///
/// A key only offers the row when the live server lists it. The Plex API
/// documentation names no filter for Dolby Vision, HDR10+ or Atmos, and neither
/// does this repository, so those stay null and do not appear. Jellyfin's
/// `/Items` documents no parameter for any of these six.
String? plexFilterKeyFor(LibraryQuickFilter filter) => switch (filter) {
  LibraryQuickFilter.hdr => 'hdr',
  LibraryQuickFilter.unmatched => 'unmatched',
  LibraryQuickFilter.duplicates => 'duplicate',
  _ => null,
};

/// The categories under the divider of Filteren op, top to bottom: Genre, Jaar,
/// Decennium and Leeftijd, then every other category there is, so nothing goes.
enum LibraryFilterCategory { genre, year, decade, contentRating, audioLanguage, servers, libraries }

const List<LibraryFilterCategory> libraryFilterCategoryMenu = LibraryFilterCategory.values;
