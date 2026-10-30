/// The one definition of what the Sort and Filter menus of a library list are
/// called and in which order they stand (Michel, 30 October 2026). tvOS draws
/// them on its panel, every other platform through `LibraryFilterSortLoader` on
/// its sheets, because nothing here knows a widget.
///
/// **A backend never decides the order or the words.** It only says whether an
/// option can run: `UnifiedFilterCapabilities` and `LibraryMenuSupport`. An
/// option no backend can truly execute is left out, never imitated on the client
/// over the pages that happen to be loaded.
library;

import '../i18n/strings.g.dart';
import '../services/unified_catalog/unified_catalog_query.dart';
import 'media_backend.dart';
import 'media_filter.dart';
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

/// The row a key of a backend's own sort list belongs on, or null when the
/// definition has none. `rating` is the critic score on Plex and the community
/// score on Jellyfin, so only the backend can place it.
UnifiedCatalogSortField? _sortFieldForKey(String key, MediaBackend backend) => switch (key) {
  'title' || 'titleSort' => UnifiedCatalogSortField.title,
  'year' || 'productionYear' => UnifiedCatalogSortField.year,
  'originallyAvailableAt' || 'premiereDate' => UnifiedCatalogSortField.releaseDate,
  'criticRating' => UnifiedCatalogSortField.criticRating,
  'rating' when backend == MediaBackend.plex => UnifiedCatalogSortField.criticRating,
  'rating' || 'communityRating' || 'audienceRating' => UnifiedCatalogSortField.audienceRating,
  'userRating' => UnifiedCatalogSortField.userRating,
  'contentRating' || 'officialRating' => UnifiedCatalogSortField.contentRating,
  'duration' || 'runtime' => UnifiedCatalogSortField.duration,
  'viewOffset' => UnifiedCatalogSortField.progress,
  'viewCount' || 'playCount' => UnifiedCatalogSortField.plays,
  'addedAt' || 'dateCreated' => UnifiedCatalogSortField.addedAt,
  'lastViewedAt' || 'datePlayed' => UnifiedCatalogSortField.recentlyWatched,
  'mediaHeight' => UnifiedCatalogSortField.resolution,
  _ => null,
};

/// A per-library list of sorts, as `MediaServerClient.fetchSortOptions` gives
/// it, in the menu's order and the menu's words. What has no place in the
/// definition (Willekeurig, Studio, Begindatum, Uitzendtijd) keeps its order and
/// its own name at the bottom: it does not go away. Keys never change, so a saved
/// sort still restores. For a list of one library only. A merged catalog cannot
/// run those: Random has no order two sources could agree on.
List<MediaSort> libraryMenuOrderedSorts(List<MediaSort> sorts, {required MediaBackend backend}) {
  int rank(UnifiedCatalogSortField? field) => field == null ? librarySortMenu.length : librarySortMenu.indexOf(field);

  final rows = [for (final (i, sort) in sorts.indexed) (i, sort, _sortFieldForKey(sort.key, backend))];
  rows.sort((a, b) {
    final cmp = rank(a.$3).compareTo(rank(b.$3));
    return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
  });
  return [
    for (final (_, sort, field) in rows) field == null ? sort : sort.copyWith(title: librarySortFieldLabel(field)),
  ];
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

/// What a server's own `/filters` list says about one library: which known
/// quick choices it can run and under which spelling, which booleans the
/// definition has no row for, and which non-boolean categories there are.
///
/// The server is the source for what exists, the definition only for order and
/// label. Nothing here assumes a key: a Plex key for Dolby Vision, HDR10+ or
/// Atmos cannot be proven from the documentation, so a row shows only when the
/// server names a filter that [libraryQuickFilterForServerKey] recognises.
class LibraryServerFilters {
  const LibraryServerFilters({this.known = const {}, this.extras = const [], this.categories = const []});

  /// The known quick choice and the `filter` value the server asked for it
  /// under, which is what a request must send (`hdr10Plus`, not `hdr10plus`).
  final Map<LibraryQuickFilter, String> known;

  /// Booleans the definition has no row for, at the bottom of the quick list.
  final List<LibraryServerFilter> extras;

  /// Non-boolean categories beyond Genre, Jaar, Decennium, Leeftijd and
  /// Audiotaal, in serverlabel.
  final List<LibraryServerFilter> categories;
}

/// One filter as a server lists it: the `filter` value a request uses and the
/// `title` the server gives it.
class LibraryServerFilter {
  const LibraryServerFilter({required this.key, required this.label});

  final String key;
  final String label;

  @override
  bool operator ==(Object other) => other is LibraryServerFilter && other.key == key && other.label == label;

  @override
  int get hashCode => Object.hash(key, label);
}

/// The spelling of a server key reduced to what it means: lower case, `+` read
/// as "plus", every other non-alphanumeric removed.
String _normalisedServerKey(String key) =>
    key.toLowerCase().replaceAll('+', 'plus').replaceAll(RegExp(r'[^a-z0-9]'), '');

/// Short aliases for the keys the definition has a row for. Short on purpose:
/// a spelling that is not here is shown as an unknown boolean, never lost.
const Map<String, LibraryQuickFilter> _knownServerKeys = {
  'hdr': LibraryQuickFilter.hdr,
  'dovi': LibraryQuickFilter.dolbyVision,
  'dolbyvision': LibraryQuickFilter.dolbyVision,
  'hdr10plus': LibraryQuickFilter.hdr10Plus,
  'atmos': LibraryQuickFilter.atmos,
  'dolbyatmos': LibraryQuickFilter.atmos,
  'unmatched': LibraryQuickFilter.unmatched,
  'duplicate': LibraryQuickFilter.duplicates,
  'duplicates': LibraryQuickFilter.duplicates,
};

/// Watch states the catalog already runs from its own watch filter, so a
/// server listing them adds no row.
const Map<String, LibraryQuickFilter> _watchStateServerKeys = {
  'unwatched': LibraryQuickFilter.unwatched,
  'inprogress': LibraryQuickFilter.inProgress,
  'watched': LibraryQuickFilter.watched,
};

/// Categories that have a row of their own under the divider, top to bottom.
const List<String> _ownCategoryServerKeys = ['genre', 'year', 'decade', 'contentrating', 'audiolanguage'];

/// The known quick choice a server key stands for, case-insensitively, or null.
LibraryQuickFilter? libraryQuickFilterForServerKey(String key) => _knownServerKeys[_normalisedServerKey(key)];

/// Sorts a library's filter list into what the menus draw.
LibraryServerFilters classifyServerFilters(Iterable<MediaFilter> filters) {
  final known = <LibraryQuickFilter, String>{};
  final extras = <LibraryServerFilter>[];
  final categories = <LibraryServerFilter>[];
  for (final filter in filters) {
    final key = filter.filter;
    if (key.isEmpty) continue;
    final normalised = _normalisedServerKey(key);
    if (filter.filterType == 'boolean') {
      if (_watchStateServerKeys.containsKey(normalised)) continue;
      final quick = _knownServerKeys[normalised];
      if (quick != null) {
        known.putIfAbsent(quick, () => key);
      } else if (!extras.any((e) => e.key == key)) {
        extras.add(LibraryServerFilter(key: key, label: filter.title.isEmpty ? key : filter.title));
      }
    } else if (!_ownCategoryServerKeys.contains(normalised) && !categories.any((c) => c.key == key)) {
      categories.add(LibraryServerFilter(key: key, label: filter.title.isEmpty ? key : filter.title));
    }
  }
  return LibraryServerFilters(known: known, extras: extras, categories: categories);
}

String? _ownCategoryLabel(String normalisedKey) => switch (normalisedKey) {
  'genre' => t.unifiedCatalog.filters.genre,
  'year' => t.unifiedCatalog.filters.year,
  'decade' => t.unifiedCatalog.filters.decade,
  'contentrating' => t.unifiedCatalog.filters.contentRating,
  'audiolanguage' => t.libraries.filterCategories.audioLanguage,
  _ => null,
};

/// A library's own filter list, as `fetchLibraryFiltersWithValues` gives it, in
/// the menu's order and the menu's words: the quick rows, the booleans the
/// definition does not know, its categories, then the server's other categories.
///
/// Unlike [classifyServerFilters] this drops nothing. The watch states and the
/// five categories are what a library's sheet runs on, and Jellyfin's Tag and
/// Pleya Server's Resolution are categories it has and the definition does not.
/// The `filter` values stay as the server gave them, because a request sends those.
List<MediaFilter> libraryMenuOrderedFilters(List<MediaFilter> filters) {
  final server = classifyServerFilters(filters);
  final quickKeys = {for (final entry in server.known.entries) entry.value: entry.key};

  bool isToggle(MediaFilter filter) => filter.filterType == 'boolean';

  LibraryQuickFilter? quickOf(MediaFilter filter) =>
      isToggle(filter) ? quickKeys[filter.filter] ?? _watchStateServerKeys[_normalisedServerKey(filter.filter)] : null;

  /// One rank per group: within a group the server's own order stands.
  int rank(MediaFilter filter) {
    if (quickOf(filter) case final quick?) return libraryQuickFilterMenu.indexOf(quick);
    final unknownToggles = libraryQuickFilterMenu.length;
    if (isToggle(filter)) return unknownToggles;
    final own = _ownCategoryServerKeys.indexOf(_normalisedServerKey(filter.filter));
    return unknownToggles + 1 + (own >= 0 ? own : _ownCategoryServerKeys.length);
  }

  final rows = [for (final (i, filter) in filters.indexed) (i, filter, rank(filter))];
  rows.sort((a, b) {
    final cmp = a.$3.compareTo(b.$3);
    return cmp != 0 ? cmp : a.$1.compareTo(b.$1);
  });
  return [
    for (final (_, filter, _) in rows)
      if (quickOf(filter) case final quick?)
        _titled(filter, libraryQuickFilterLabel(quick))
      else if (isToggle(filter) ? null : _ownCategoryLabel(_normalisedServerKey(filter.filter)) case final label?)
        _titled(filter, label)
      else
        filter,
  ];
}

MediaFilter _titled(MediaFilter filter, String title) =>
    MediaFilter(filter: filter.filter, filterType: filter.filterType, key: filter.key, title: title, type: filter.type);

/// The categories under the divider of Filteren op, top to bottom: Genre, Jaar,
/// Decennium and Leeftijd, then every other category there is, so nothing goes.
enum LibraryFilterCategory { genre, year, decade, contentRating, audioLanguage, servers, libraries }

const List<LibraryFilterCategory> libraryFilterCategoryMenu = LibraryFilterCategory.values;
