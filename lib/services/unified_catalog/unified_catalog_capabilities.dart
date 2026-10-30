/// Which filters a set of backends can execute correctly. The reasoning lives in
/// the library doc of `unified_catalog_filters.dart`; this file is the table.
library;

import '../../media/media_backend.dart';

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

  const UnifiedFilterCapabilities({
    required this.supportsMetadataFilters,
    required this.supportsWatchFilter,
    this.supportsWatchedFilter = false,
  });

  /// The answer for an empty catalog: nothing participates, so nothing is
  /// promised. Rendering a filter panel here would offer choices over no data.
  static const none = UnifiedFilterCapabilities(supportsMetadataFilters: false, supportsWatchFilter: false);

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
      other.supportsWatchedFilter == supportsWatchedFilter;

  @override
  int get hashCode => Object.hash(supportsMetadataFilters, supportsWatchFilter, supportsWatchedFilter);
}

/// What [backends] can all honour.
///
/// Deliberately the intersection, not the union: a filter is a promise about
/// the whole result list, and one backend ignoring it makes the promise false
/// for every row that backend contributed. An empty set yields
/// [UnifiedFilterCapabilities.none] rather than "everything is supported",
/// because a vacuous truth here would light up a filter panel on a catalog with
/// no libraries in it.
UnifiedFilterCapabilities unifiedFilterCapabilitiesFor(Iterable<MediaBackend> backends) {
  final all = backends.toSet();
  if (all.isEmpty) return UnifiedFilterCapabilities.none;
  return UnifiedFilterCapabilities(
    supportsMetadataFilters: all.every(_executesMetadataFilters),
    supportsWatchFilter: all.every(_executesWatchFilter),
    supportsWatchedFilter: all.every(_executesWatchedFilter),
  );
}

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
