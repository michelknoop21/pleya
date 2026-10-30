/// What Films and Series may be narrowed and reordered by (hoofdstuk 10.4 and
/// 10.5 of docs/tvos-unified-experience.md).
///
/// Pure data and pure functions: a selection, the sorts it can carry, the rule
/// deciding which filters a given set of libraries can actually honour, and the
/// translation of all of that into the two things the fase-3 engine consumes —
/// a [UnifiedCatalogQuery] and a participating-library set. Nothing here
/// touches a widget tree, a provider or a server, which is what lets the filter
/// contract be tested without any of them.
///
/// ## Why filters are executed in two different places
///
/// Genre, year and watch state are *item* predicates: every participating
/// library gets them as part of the one neutral query hoofdstuk 12.2 requires,
/// and the backend applies them before the k-way merge ever sees an item.
///
/// Server and library are *source* predicates. They are executed by restricting
/// which cursors take part at all ([UnifiedCatalogFilterSelection.selects]),
/// not by filtering results afterwards. That is both cheaper — an excluded
/// server is never asked — and the only correct option: dropping items after
/// the merge would leave a page that yielded twenty groups showing three, and
/// paging counts would stop meaning anything.
///
/// ## Why a filter can be unavailable
///
/// Hoofdstuk 10.4 lists genre, year and watch state as globally safe, and for
/// Plex and Jellyfin they are: `library_query_translator.dart` maps all three
/// on both sides. The Pleya Server client does so since venster 3 (pakket D1,
/// `capabilities.filters`); against a server without that capability it answers
/// an empty page and never an unfiltered one, so a filter cannot present a
/// whole library as its matches. The local folder client still has no index to
/// filter on.
///
/// Hoofdstuk 10.4's own rule for exactly this ("Geen filter tonen dat
/// UnifiedCatalogQuery niet correct kan uitvoeren") is therefore applied as a
/// capability, computed from the participating backends by
/// [unifiedFilterCapabilitiesFor]. With Plex and/or Jellyfin — the whole
/// canonical fixture of hoofdstuk 28 — every filter is offered. The two source
/// predicates are always available: restricting the cursor set is something the
/// merge engine does, not a backend.
library;

import '../../media/library_menu_definition.dart';
import '../../media/library_query.dart';
import '../../media/media_kind.dart';
import '../../utils/global_key_utils.dart';
import 'content_rating_labels.dart';
import 'source_cursor.dart';
import 'unified_catalog_capabilities.dart';
import 'unified_catalog_query.dart';
import 'unified_catalog_sort.dart';

export 'content_rating_labels.dart';
export 'unified_catalog_capabilities.dart';
export 'unified_catalog_sort.dart';

/// One catalog's current narrowing, as the user set it.
///
/// Immutable and comparable, so a screen can tell "the same filters" from "new
/// filters" without diffing five collections at the call site — which is what
/// decides whether the merge restarts and the grid scrolls back to the top.
class UnifiedCatalogFilterSelection {
  /// Genre names, OR-ed within the field by both backends.
  final Set<String> genres;
  final Set<String> audioLanguages;

  /// Content ratings as each server names them ("PG-13", "12"). The value list
  /// is a union of rating systems; a value one server does not use simply
  /// matches nothing there. Plex `contentRating`, Jellyfin `OfficialRatings`.
  final Set<String> officialRatings;

  final Set<int> years;

  /// First year of each chosen decade. Runs as the years it holds, on every
  /// backend that filters on year: there is nothing to imitate.
  final Set<int> decades;
  final UnifiedWatchFilter watchState;

  /// One of [libraryMediaQuickFilters], or null. The quick choices take one at a
  /// time, so choosing one clears [watchState] and the other way around.
  final LibraryQuickFilter? mediaFilter;

  /// The `filter` value of a boolean the servers list and the definition has no
  /// row for, or null. Takes the same single slot as [mediaFilter]: choosing
  /// one clears the other.
  final String? extraFilter;

  /// Choices in the non-boolean categories the servers list beyond the five of
  /// the definition: `filter` value to the chosen values.
  final Map<String, Set<String>> serverFilters;

  /// Stable server ids. Empty means every visible server, which is not the same
  /// as "all of them explicitly selected": a server that appears later is
  /// included by an empty set and excluded by an exhaustive one, and the first
  /// is what "Alle bronnen" means.
  final Set<String> serverIds;

  /// `serverId:libraryId` keys, same emptiness rule.
  final Set<String> libraryKeys;

  const UnifiedCatalogFilterSelection({
    this.genres = const {},
    this.audioLanguages = const {},
    this.officialRatings = const {},
    this.years = const {},
    this.decades = const {},
    this.watchState = UnifiedWatchFilter.all,
    this.mediaFilter,
    this.extraFilter,
    this.serverFilters = const {},
    this.serverIds = const {},
    this.libraryKeys = const {},
  });

  static const empty = UnifiedCatalogFilterSelection();

  /// How many separate narrowings are active — the number on the Filters
  /// action (hoofdstuk 10.6's "Actieve filtercount verschijnt op de
  /// Filter-knop"). One per *field*, not per value: "three genres" is one
  /// narrowing the user made, and counting values would put a 7 on a button
  /// after two clicks.
  int get activeCount =>
      (genres.isEmpty ? 0 : 1) +
      (audioLanguages.isEmpty ? 0 : 1) +
      (officialRatings.isEmpty ? 0 : 1) +
      (years.isEmpty ? 0 : 1) +
      (decades.isEmpty ? 0 : 1) +
      (watchState == UnifiedWatchFilter.all ? 0 : 1) +
      (mediaFilter == null && extraFilter == null ? 0 : 1) +
      serverFilters.length +
      (serverIds.isEmpty ? 0 : 1) +
      (libraryKeys.isEmpty ? 0 : 1);

  bool get isEmpty => activeCount == 0;

  /// How many narrowings apply to the *items* rather than to which sources take
  /// part: CAT5's "2 actief" under the Filters row of the rail.
  ///
  /// Not [activeCount]. The rail states the source restriction on its own row,
  /// directly above ("Alle · 3 servers"), so counting it again one line lower
  /// says the viewer made two choices where they made one. [activeCount] keeps
  /// counting all five, because the panel those rows both open has all five
  /// sections in it and hoofdstuk 10.6 puts the count on the panel's own
  /// button.
  int get itemFilterCount =>
      (genres.isEmpty ? 0 : 1) +
      (audioLanguages.isEmpty ? 0 : 1) +
      (officialRatings.isEmpty ? 0 : 1) +
      (years.isEmpty ? 0 : 1) +
      (decades.isEmpty ? 0 : 1) +
      (watchState == UnifiedWatchFilter.all ? 0 : 1) +
      (mediaFilter == null && extraFilter == null ? 0 : 1) +
      serverFilters.length;

  /// Whether anything here narrows *which sources take part*, as opposed to
  /// which items they return. Drives the "Alle bronnen" action's own label.
  bool get restrictsSources => serverIds.isNotEmpty || libraryKeys.isNotEmpty;

  /// Which quick row carries the tick.
  LibraryQuickFilter get quickFilter =>
      mediaFilter ??
      switch (watchState) {
        UnifiedWatchFilter.all => LibraryQuickFilter.all,
        UnifiedWatchFilter.unwatched => LibraryQuickFilter.unwatched,
        UnifiedWatchFilter.inProgress => LibraryQuickFilter.inProgress,
        UnifiedWatchFilter.watched => LibraryQuickFilter.watched,
      };

  /// This selection with the quick choice set to [filter].
  UnifiedCatalogFilterSelection withQuickFilter(LibraryQuickFilter filter) => UnifiedCatalogFilterSelection(
    genres: genres,
    audioLanguages: audioLanguages,
    officialRatings: officialRatings,
    years: years,
    decades: decades,
    watchState: switch (filter) {
      LibraryQuickFilter.unwatched => UnifiedWatchFilter.unwatched,
      LibraryQuickFilter.inProgress => UnifiedWatchFilter.inProgress,
      LibraryQuickFilter.watched => UnifiedWatchFilter.watched,
      _ => UnifiedWatchFilter.all,
    },
    mediaFilter: libraryMediaQuickFilters.contains(filter) ? filter : null,
    serverFilters: serverFilters,
    serverIds: serverIds,
    libraryKeys: libraryKeys,
  );

  /// This selection with the boolean [key] the servers list as the quick choice.
  UnifiedCatalogFilterSelection withExtraFilter(String key) => UnifiedCatalogFilterSelection(
    genres: genres,
    audioLanguages: audioLanguages,
    officialRatings: officialRatings,
    years: years,
    decades: decades,
    extraFilter: key,
    serverFilters: serverFilters,
    serverIds: serverIds,
    libraryKeys: libraryKeys,
  );

  UnifiedCatalogFilterSelection copyWith({
    Set<String>? genres,
    Set<String>? audioLanguages,
    Set<String>? officialRatings,
    Set<int>? years,
    Set<int>? decades,
    UnifiedWatchFilter? watchState,
    Map<String, Set<String>>? serverFilters,
    Set<String>? serverIds,
    Set<String>? libraryKeys,
  }) => UnifiedCatalogFilterSelection(
    genres: genres ?? this.genres,
    audioLanguages: audioLanguages ?? this.audioLanguages,
    officialRatings: officialRatings ?? this.officialRatings,
    years: years ?? this.years,
    decades: decades ?? this.decades,
    watchState: watchState ?? this.watchState,
    mediaFilter: mediaFilter,
    extraFilter: extraFilter,
    serverFilters: serverFilters ?? this.serverFilters,
    serverIds: serverIds ?? this.serverIds,
    libraryKeys: libraryKeys ?? this.libraryKeys,
  );

  /// This selection with everything a set of [capabilities] cannot execute
  /// dropped — the *effective* selection, as opposed to the stored one.
  ///
  /// **Never write the result back.** Capabilities follow the current
  /// participating library set, and that set is itself something the user
  /// changes: a Pleya Server library taking part suppresses the genre filter,
  /// and restricting sources to the Plex and Jellyfin libraries brings it back.
  /// Persisting the constrained value would make the first of those two
  /// destructive and the second impossible, so the stored selection keeps
  /// everything the user chose and this is applied at the two places it is
  /// actually needed: building the query, and rendering the panel and its
  /// active count.
  ///
  /// A vanished server or library is the opposite case and *is* written back —
  /// hoofdstuk 10.6's "wordt bij openen automatisch uit de opgeslagen selectie
  /// verwijderd" — because a key naming a server that no longer exists has no
  /// row left in the panel to untick it with. That is [withKnownSources].
  UnifiedCatalogFilterSelection constrainedTo(UnifiedFilterCapabilities capabilities) => UnifiedCatalogFilterSelection(
    genres: capabilities.supportsMetadataFilters ? genres : const {},
    audioLanguages: capabilities.supportsMetadataFilters ? audioLanguages : const {},
    officialRatings: capabilities.supportsMetadataFilters ? officialRatings : const {},
    years: capabilities.supportsMetadataFilters ? years : const {},
    decades: capabilities.supportsMetadataFilters ? decades : const {},
    watchState: capabilities.supportsWatchState(watchState) ? watchState : UnifiedWatchFilter.all,
    mediaFilter: mediaFilter != null && capabilities.supportsQuickFilter(mediaFilter!) ? mediaFilter : null,
    extraFilter: extraFilter != null && capabilities.supportsExtraFilter(extraFilter!) ? extraFilter : null,
    serverFilters: {
      for (final entry in serverFilters.entries)
        if (capabilities.supportsServerCategory(entry.key)) entry.key: entry.value,
    },
    serverIds: serverIds,
    libraryKeys: libraryKeys,
  );

  /// This selection with server and library choices that no longer exist
  /// dropped (hoofdstuk 10.6).
  ///
  /// A stored key that names a removed server would otherwise be an invisible
  /// filter: it narrows nothing a user can see and can never be unticked,
  /// because the row it belonged to is gone from the panel.
  UnifiedCatalogFilterSelection withKnownSources({
    required Set<String> knownServerIds,
    required Set<String> knownLibraryKeys,
  }) {
    final servers = serverIds.intersection(knownServerIds);
    final libraries = libraryKeys.intersection(knownLibraryKeys);
    if (servers.length == serverIds.length && libraries.length == libraryKeys.length) return this;
    return copyWith(serverIds: servers, libraryKeys: libraries);
  }

  /// Whether [library] takes part in the merge under this selection.
  ///
  /// The two source predicates are AND-ed: picking a server and then one of its
  /// libraries means that library, not "that server plus that library". Each is
  /// skipped while empty, so "Alle bronnen" is the absence of a restriction
  /// rather than a list that has to be kept in sync with the server registry.
  bool selects(CatalogLibrary library) {
    if (serverIds.isNotEmpty && !serverIds.contains(library.serverId.value)) return false;
    if (libraryKeys.isNotEmpty && !libraryKeys.contains(buildGlobalKey(library.serverId, library.libraryId))) {
      return false;
    }
    return true;
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is UnifiedCatalogFilterSelection &&
          _setEquals(other.genres, genres) &&
          _setEquals(other.audioLanguages, audioLanguages) &&
          _setEquals(other.officialRatings, officialRatings) &&
          _setEquals(other.years, years) &&
          _setEquals(other.decades, decades) &&
          other.watchState == watchState &&
          other.mediaFilter == mediaFilter &&
          other.extraFilter == extraFilter &&
          _mapOfSetsEqual(other.serverFilters, serverFilters) &&
          _setEquals(other.serverIds, serverIds) &&
          _setEquals(other.libraryKeys, libraryKeys);

  @override
  int get hashCode => Object.hash(
    Object.hashAllUnordered(genres),
    Object.hashAllUnordered(audioLanguages),
    Object.hashAllUnordered(officialRatings),
    Object.hashAllUnordered(years),
    Object.hashAllUnordered(decades),
    watchState,
    mediaFilter,
    extraFilter,
    Object.hashAll(
      ([...serverFilters.keys]..sort()).map((k) => Object.hash(k, Object.hashAllUnordered(serverFilters[k]!))),
    ),
    Object.hashAllUnordered(serverIds),
    Object.hashAllUnordered(libraryKeys),
  );

  @override
  String toString() => 'UnifiedCatalogFilterSelection($activeCount active)';
}

bool _mapOfSetsEqual(Map<String, Set<String>> a, Map<String, Set<String>> b) =>
    a.length == b.length && a.entries.every((e) => b[e.key] != null && _setEquals(b[e.key]!, e.value));

bool _setEquals<T>(Set<T> a, Set<T> b) => a.length == b.length && a.containsAll(b);

Set<String> _stringSet(Object? raw) => raw is List
    ? {
        for (final value in raw)
          if (value is String && value.isNotEmpty) value,
      }
    : const {};

Set<int> _intSet(Object? raw) => raw is List
    ? {
        for (final value in raw)
          if (value is int) value,
      }
    : const {};

/// The whole of what one catalog page remembers: how it is ordered and how it
/// is narrowed. Persisted per profile per kind by
/// `UnifiedCatalogQueryStore`; distinct from the *preferred server*, which is a
/// profile-wide activation preference and not a view setting at all.
class UnifiedCatalogPreferences {
  final UnifiedCatalogSort sort;
  final UnifiedCatalogFilterSelection filters;

  const UnifiedCatalogPreferences({
    this.sort = UnifiedCatalogSort.titleAsc,
    this.filters = UnifiedCatalogFilterSelection.empty,
  });

  static const defaults = UnifiedCatalogPreferences();

  UnifiedCatalogPreferences copyWith({UnifiedCatalogSort? sort, UnifiedCatalogFilterSelection? filters}) =>
      UnifiedCatalogPreferences(sort: sort ?? this.sort, filters: filters ?? this.filters);

  /// The sort in force: the stored one, the year where a backend taking part has
  /// no date (a stored Nieuwste release must not read A to Z on Pleya Server,
  /// whose release sort has always run on the year), or else title.
  ///
  /// Every reader takes it from here, so the query, the label and the tick of a
  /// sheet cannot disagree.
  ///
  /// **Never write the result back**, for the reason on
  /// [UnifiedCatalogFilterSelection.constrainedTo]: the set of backends is
  /// itself something the user changes, and lifting the source restriction has
  /// to bring the score sort back.
  UnifiedCatalogSort effectiveSort(UnifiedFilterCapabilities capabilities) {
    if (capabilities.supportsSort(sort.field)) return sort;
    if (sort.field == UnifiedCatalogSortField.releaseDate && capabilities.supportsSort(UnifiedCatalogSortField.year)) {
      return sort.direction == LibrarySortDirection.descending
          ? UnifiedCatalogSort.yearNewest
          : UnifiedCatalogSort.yearOldest;
    }
    return UnifiedCatalogSort.titleAsc;
  }

  Map<String, dynamic> toJson() => {
    'sort': sort.name,
    if (filters.genres.isNotEmpty) 'genres': filters.genres.toList()..sort(),
    if (filters.audioLanguages.isNotEmpty) 'audioLanguages': filters.audioLanguages.toList()..sort(),
    if (filters.officialRatings.isNotEmpty) 'officialRatings': filters.officialRatings.toList()..sort(),
    if (filters.years.isNotEmpty) 'years': filters.years.toList()..sort(),
    if (filters.decades.isNotEmpty) 'decades': filters.decades.toList()..sort(),
    if (filters.watchState != UnifiedWatchFilter.all) 'watch': filters.watchState.name,
    if (filters.mediaFilter != null) 'media': filters.mediaFilter!.name,
    if (filters.extraFilter != null) 'extra': filters.extraFilter,
    if (filters.serverFilters.isNotEmpty)
      'serverFilters': {for (final e in filters.serverFilters.entries) e.key: e.value.toList()..sort()},
    if (filters.serverIds.isNotEmpty) 'servers': filters.serverIds.toList()..sort(),
    if (filters.libraryKeys.isNotEmpty) 'libraries': filters.libraryKeys.toList()..sort(),
  };

  /// Every field is optional and every unknown value falls back to the default.
  ///
  /// A stored sort name that no longer exists — a sort dropped from hoofdstuk
  /// 10.5, or an entry written by a newer build — must not throw: this runs
  /// while a page is opening, and the honest recovery is Title A–Z, not a
  /// crash. Same for a genre the servers no longer report: it is kept, applies
  /// to nothing, and the user can clear it from the panel.
  factory UnifiedCatalogPreferences.fromJson(Map<String, dynamic> json) => UnifiedCatalogPreferences(
    sort: UnifiedCatalogSort.byName(json['sort'] as String?) ?? UnifiedCatalogSort.titleAsc,
    filters: UnifiedCatalogFilterSelection(
      genres: _stringSet(json['genres']),
      audioLanguages: _stringSet(json['audioLanguages']),
      officialRatings: _stringSet(json['officialRatings']),
      years: _intSet(json['years']),
      decades: _intSet(json['decades']),
      watchState: UnifiedWatchFilter.byName(json['watch']),
      mediaFilter: _mediaFilter(json['media']),
      extraFilter: json['extra'] is String && (json['extra'] as String).isNotEmpty ? json['extra'] as String : null,
      serverFilters: _serverFilters(json['serverFilters']),
      serverIds: _stringSet(json['servers']),
      libraryKeys: _stringSet(json['libraries']),
    ),
  );

  @override
  bool operator ==(Object other) =>
      identical(this, other) || other is UnifiedCatalogPreferences && other.sort == sort && other.filters == filters;

  @override
  int get hashCode => Object.hash(sort, filters);
}

Map<String, Set<String>> _serverFilters(Object? raw) {
  if (raw is! Map) return const {};
  final result = <String, Set<String>>{};
  for (final entry in raw.entries) {
    final values = _stringSet(entry.value);
    if (entry.key is String && values.isNotEmpty) result[entry.key as String] = values;
  }
  return result;
}

LibraryQuickFilter? _mediaFilter(Object? name) {
  for (final filter in libraryMediaQuickFilters) {
    if (filter.name == name) return filter;
  }
  return null;
}

/// The years a selection narrows to. A decade is the ten years it holds; a year
/// chosen beside it has to lie inside it, the two being AND-ed like every other
/// pair of fields.
List<int>? _queryYears(UnifiedCatalogFilterSelection filters) {
  if (filters.decades.isEmpty) return filters.years.isEmpty ? null : (filters.years.toList()..sort());
  final inDecades = {
    for (final decade in filters.decades)
      for (var year = decade; year < decade + 10; year++) year,
  };
  final years = filters.years.isEmpty ? inDecades : inDecades.intersection(filters.years);
  // A year outside every chosen decade: nothing matches, and year 0 is how a
  // query says so on every backend.
  return years.isEmpty ? const [0] : (years.toList()..sort());
}

/// The neutral query these preferences produce for [kind], with [capabilities]
/// applied.
///
/// The one place a selection becomes engine input, so every caller gets the
/// same translation *and* the same guarantee: a filter the participating
/// backends cannot execute never reaches the query, whatever is stored. The
/// values are sorted so two equal selections produce an equal query — the
/// provider restarts the merge on a query change, and an unstable list order
/// would restart it on every rebuild.
UnifiedCatalogQuery buildUnifiedCatalogQuery({
  required MediaKind kind,
  required UnifiedCatalogPreferences preferences,
  required UnifiedFilterCapabilities capabilities,
}) {
  final filters = preferences.filters.constrainedTo(capabilities);
  final sort = preferences.effectiveSort(capabilities);
  return UnifiedCatalogQuery(
    kind: kind,
    sortField: sort.field,
    sortDirection: sort.direction,
    includeWatched: filters.watchState != UnifiedWatchFilter.unwatched,
    inProgressOnly: filters.watchState == UnifiedWatchFilter.inProgress,
    watchedOnly: filters.watchState == UnifiedWatchFilter.watched,
    genres: filters.genres.isEmpty ? null : (filters.genres.toList()..sort()),
    audioLanguages: filters.audioLanguages.isEmpty ? null : (filters.audioLanguages.toList()..sort()),
    officialRatings: filters.officialRatings.isEmpty
        ? null
        : ({for (final value in filters.officialRatings) ...value.split(contentRatingValueSeparator)}.toList()..sort()),
    years: _queryYears(filters),
    // The `field` is the `filter` value the server listed, never a key of ours.
    filters: [
      if (capabilities.mediaFilterKeys[filters.mediaFilter] case final key?)
        LibraryFilter(field: key, values: const ['1']),
      if (filters.extraFilter case final key?) LibraryFilter(field: key, values: const ['1']),
      for (final entry in filters.serverFilters.entries)
        LibraryFilter(field: entry.key, values: entry.value.toList()..sort()),
    ],
  );
}

/// A screen's `_restorePreferences` step, factored out so the TV and mobile
/// catalog screens share one answer instead of two (CAT20).
///
/// [boundServerIds]/[boundLibraryKeys] are what [UnifiedCatalogFilterSelection.
/// withKnownSources] has always pruned against: the libraries actually bound
/// right now. That set alone cannot tell a server that no longer exists from
/// one that simply has not finished connecting yet: a cold start can still be
/// waiting on a slow server's endpoint race when the first read happens. This
/// widens the known-server set with [registeredServerIds], every server the
/// active profile is configured for, bound or not, which only the caller
/// (backed by [MultiServerProvider.expectedServerIds]) can supply.
///
/// [shouldPersist] is true only once every registered server has actually
/// bound: writing the prune back while one is still connecting would freeze
/// that half-arrived snapshot into the store, which is the bug this exists to
/// avoid.
///
/// The same race applies one level down, at the library key: a stored key for
/// a library on a server that has not finished connecting yet is not known to
/// be gone either, only unproven so far. A registered-but-unbound server's own
/// stored library keys are kept provisionally instead of pruned, since there
/// is no library list yet to check them against; a bound server's keys are
/// still pruned against what it actually reports.
({UnifiedCatalogPreferences preferences, bool shouldPersist}) pruneStoredSourceFilter({
  required UnifiedCatalogPreferences stored,
  required Set<String> boundServerIds,
  required Set<String> boundLibraryKeys,
  required Set<String> registeredServerIds,
}) {
  final pendingServerIds = registeredServerIds.difference(boundServerIds);
  final provisionalLibraryKeys = stored.filters.libraryKeys.where((key) {
    final parsed = parseGlobalKey(key);
    return parsed != null && pendingServerIds.contains(parsed.serverId);
  }).toSet();
  final pruned = stored.copyWith(
    filters: stored.filters.withKnownSources(
      knownServerIds: boundServerIds.union(registeredServerIds),
      knownLibraryKeys: boundLibraryKeys.union(provisionalLibraryKeys),
    ),
  );
  final complete = registeredServerIds.every(boundServerIds.contains);
  return (preferences: pruned, shouldPersist: pruned != stored && complete);
}
