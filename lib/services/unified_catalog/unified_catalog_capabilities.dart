/// Which filters a set of backends can execute correctly. The reasoning lives in
/// the library doc of `unified_catalog_filters.dart`; this file is the table.
library;

import '../../media/library_menu_definition.dart';
import '../../media/media_backend.dart';
import '../../media/media_kind.dart';
import 'library_menu_support.dart';
import 'unified_catalog_query.dart';

/// Hoofdstuk 10.4's watch-state filter, reduced to what a backend can answer.
///
/// Every state is a field on the neutral query, so the backend applies it
/// before the merge and paging keeps its meaning (see this library's doc):
///
/// - [unwatched]: `includeWatched: false`, Plex `unwatched=1`, Jellyfin
///   `Filters=IsUnplayed`.
/// - [inProgress]: `inProgressOnly`, Plex `inProgress=1` (a documented
///   boolean section filter), Jellyfin `Filters=IsResumable`.
/// - [watched]: `watchedOnly`, Jellyfin `Filters=IsPlayed`. Plex has no
///   documented "watched only" filter (`unwatched=0` is unmeasured), so this
///   state is gated by [UnifiedFilterCapabilities.supportsWatchedFilter] and
///   absent whenever a Plex library takes part.
enum UnifiedWatchFilter {
  all,
  unwatched,
  inProgress,
  watched;

  static UnifiedWatchFilter byName(Object? name) {
    for (final value in values) {
      if (value.name == name) return value;
    }
    return all;
  }
}

/// Which filters the participating backends can execute correctly.
class UnifiedFilterCapabilities {
  /// Genre and year, both of which ride on the neutral query's typed fields.
  final bool supportsMetadataFilters;

  /// `includeWatched: false` and `inProgressOnly`.
  final bool supportsWatchFilter;

  /// `watchedOnly`, which only Jellyfin executes.
  final bool supportsWatchedFilter;

  /// The sort fields every participating backend can run.
  final Set<UnifiedCatalogSortField> sortFields;

  /// The media quick filters every library has listed, with the `filter` value
  /// they are listed under: only a live answer can add one, see [narrowedTo].
  final Map<LibraryQuickFilter, String> mediaFilterKeys;

  /// Booleans the servers list that the definition has no row for.
  final List<LibraryServerFilter> extraFilters;

  /// Non-boolean categories the servers list beyond the five of the definition.
  final List<LibraryServerFilter> serverCategories;

  Set<LibraryQuickFilter> get mediaFilters => mediaFilterKeys.keys.toSet();

  const UnifiedFilterCapabilities({
    required this.supportsMetadataFilters,
    required this.supportsWatchFilter,
    this.supportsWatchedFilter = false,
    this.sortFields = const {UnifiedCatalogSortField.title},
    this.mediaFilterKeys = const {},
    this.extraFilters = const [],
    this.serverCategories = const [],
  });

  /// This table corrected by what the live servers said. Null changes nothing.
  UnifiedFilterCapabilities narrowedTo(LibraryMenuSupport? support) => support == null
      ? this
      : UnifiedFilterCapabilities(
          supportsMetadataFilters: supportsMetadataFilters,
          supportsWatchFilter: supportsWatchFilter,
          supportsWatchedFilter: supportsWatchedFilter,
          sortFields: sortFields.intersection(support.sortFields),
          mediaFilterKeys: support.mediaFilterKeys,
          extraFilters: support.extraFilters,
          serverCategories: support.serverCategories,
        );

  /// The answer for an empty catalog: nothing participates, so nothing is
  /// promised. Rendering a filter panel here would offer choices over no data.
  static const none = UnifiedFilterCapabilities(supportsMetadataFilters: false, supportsWatchFilter: false);

  /// Whether every participating backend can sort on [field]. A sort the
  /// catalog cannot run is never offered and never asked for: see
  /// [UnifiedCatalogPreferences.effectiveSort].
  bool supportsSort(UnifiedCatalogSortField field) => sortFields.contains(field);

  /// Whether every library can execute the quick choice [filter].
  bool supportsQuickFilter(LibraryQuickFilter filter) => switch (filter) {
    LibraryQuickFilter.all => true,
    LibraryQuickFilter.unwatched || LibraryQuickFilter.inProgress => supportsWatchFilter,
    LibraryQuickFilter.watched => supportsWatchFilter && supportsWatchedFilter,
    _ => mediaFilterKeys.containsKey(filter),
  };

  /// Whether every library lists the boolean [key] that has no row of its own.
  bool supportsExtraFilter(String key) => extraFilters.any((e) => e.key == key);

  /// Whether every library lists the non-boolean category [key].
  bool supportsServerCategory(String key) => serverCategories.any((c) => c.key == key);

  /// Whether [state] can be executed by every participating backend.
  bool supportsWatchState(UnifiedWatchFilter state) => switch (state) {
    UnifiedWatchFilter.all => true,
    UnifiedWatchFilter.unwatched || UnifiedWatchFilter.inProgress => supportsWatchFilter,
    UnifiedWatchFilter.watched => supportsWatchFilter && supportsWatchedFilter,
  };

  @override
  bool operator ==(Object other) =>
      other is UnifiedFilterCapabilities &&
      other.supportsMetadataFilters == supportsMetadataFilters &&
      other.supportsWatchFilter == supportsWatchFilter &&
      other.supportsWatchedFilter == supportsWatchedFilter &&
      other.sortFields.length == sortFields.length &&
      other.sortFields.containsAll(sortFields) &&
      _mapEquals(other.mediaFilterKeys, mediaFilterKeys) &&
      _listEquals(other.extraFilters, extraFilters) &&
      _listEquals(other.serverCategories, serverCategories);

  @override
  int get hashCode => Object.hash(
    supportsMetadataFilters,
    supportsWatchFilter,
    supportsWatchedFilter,
    Object.hashAllUnordered(sortFields),
    Object.hashAll(mediaFilterKeys.entries.map((e) => Object.hash(e.key, e.value))),
    Object.hashAll(extraFilters),
    Object.hashAll(serverCategories),
  );
}

bool _mapEquals<K, V>(Map<K, V> a, Map<K, V> b) =>
    a.length == b.length && a.entries.every((e) => b.containsKey(e.key) && b[e.key] == e.value);

bool _listEquals<T>(List<T> a, List<T> b) =>
    a.length == b.length && Iterable<int>.generate(a.length).every((i) => a[i] == b[i]);

/// What [backends] can all honour.
///
/// Deliberately the intersection, not the union: a filter is a promise about
/// the whole result list, and one backend ignoring it makes the promise false
/// for every row that backend contributed. An empty set yields
/// [UnifiedFilterCapabilities.none] rather than "everything is supported",
/// because a vacuous truth here would light up a filter panel on a catalog with
/// no libraries in it.
///
/// [kind] matters for the sorts only: a Plex show has no runtime or position of
/// its own to order by.
UnifiedFilterCapabilities unifiedFilterCapabilitiesFor(Iterable<MediaBackend> backends, {MediaKind? kind}) {
  final all = backends.toSet();
  if (all.isEmpty) return UnifiedFilterCapabilities.none;
  return UnifiedFilterCapabilities(
    supportsMetadataFilters: all.every(_executesMetadataFilters),
    supportsWatchFilter: all.every(_executesWatchFilter),
    supportsWatchedFilter: all.every(_executesWatchedFilter),
    sortFields: {
      for (final field in UnifiedCatalogSortField.values)
        if (all.every((backend) => _sortFieldsOf(backend, kind).contains(field))) field,
    },
  );
}

/// Sort fields of [backend], per client:
///
/// * Plex passes the neutral name through as `sort=`, except the critic score
///   (`PlexLibraryQueryTranslator`). `/library/sections/{id}/sorts` advertises
///   per library what it takes, and `PlexClient._withExtraSorts` adds plays and
///   user rating for movies and shows. No duration, position or resolution on a
///   show. This row is the upper bound: `LibraryMenuSupport` narrows it to what
///   the live server lists.
/// * Jellyfin and Emby go through `JellyfinLibraryQueryTranslator`. `ItemSortBy`
///   has no user rating (the mapped `Likes` flag is not a sort), no playback
///   position and no resolution.
/// * Pleya Server takes what `PleyaServerClient.fetchSortOptions` lists. The
///   year is a year, so Release Date is not offered as if it were a date.
/// * A local folder runs `LocalFolderClient._applySort`.
Set<UnifiedCatalogSortField> _sortFieldsOf(MediaBackend backend, MediaKind? kind) => switch (backend) {
  MediaBackend.plex => {
    UnifiedCatalogSortField.title,
    UnifiedCatalogSortField.year,
    UnifiedCatalogSortField.releaseDate,
    UnifiedCatalogSortField.criticRating,
    UnifiedCatalogSortField.audienceRating,
    UnifiedCatalogSortField.userRating,
    UnifiedCatalogSortField.contentRating,
    if (kind != MediaKind.show) UnifiedCatalogSortField.duration,
    if (kind != MediaKind.show) UnifiedCatalogSortField.progress,
    UnifiedCatalogSortField.plays,
    UnifiedCatalogSortField.addedAt,
    UnifiedCatalogSortField.recentlyWatched,
    if (kind != MediaKind.show) UnifiedCatalogSortField.resolution,
  },
  MediaBackend.jellyfin => const {
    UnifiedCatalogSortField.title,
    UnifiedCatalogSortField.year,
    UnifiedCatalogSortField.releaseDate,
    UnifiedCatalogSortField.criticRating,
    UnifiedCatalogSortField.audienceRating,
    UnifiedCatalogSortField.contentRating,
    UnifiedCatalogSortField.duration,
    UnifiedCatalogSortField.plays,
    UnifiedCatalogSortField.addedAt,
    UnifiedCatalogSortField.recentlyWatched,
  },
  MediaBackend.pleyaServer => const {
    UnifiedCatalogSortField.title,
    UnifiedCatalogSortField.year,
    UnifiedCatalogSortField.duration,
    UnifiedCatalogSortField.addedAt,
    UnifiedCatalogSortField.recentlyWatched,
  },
  MediaBackend.local => const {
    UnifiedCatalogSortField.title,
    UnifiedCatalogSortField.year,
    UnifiedCatalogSortField.plays,
    UnifiedCatalogSortField.addedAt,
    UnifiedCatalogSortField.recentlyWatched,
  },
};

/// Whether [backend]'s client translates `genres`/`years` into its own request.
///
/// Verified against `library_query_translator.dart`, which is the one place
/// either backend turns a [LibraryQuery] into wire parameters — Plex at
/// `genre`/`year`, Jellyfin at `Genres`/`Years`. The Pleya Server client
/// (`pleya_server_client/parts/browse.dart`) sends them as repeated protocol
/// parameters, and the local folder client browses a filesystem with no such
/// index.
bool _executesMetadataFilters(MediaBackend backend) =>
    backend == MediaBackend.plex || backend == MediaBackend.jellyfin || backend == MediaBackend.pleyaServer;

/// Whether [backend]'s client translates `includeWatched: false` and
/// `inProgressOnly`.
bool _executesWatchFilter(MediaBackend backend) =>
    backend == MediaBackend.plex || backend == MediaBackend.jellyfin || backend == MediaBackend.pleyaServer;

/// Whether [backend]'s client translates `watchedOnly`. Jellyfin and Pleya
/// Server (`watch=watched`): the Plex translator ignores it until a live server
/// proves what `unwatched=0` returns.
bool _executesWatchedFilter(MediaBackend backend) =>
    backend == MediaBackend.jellyfin || backend == MediaBackend.pleyaServer;
