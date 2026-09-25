import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_filters.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';

/// Fase 5's filter contract (docs/tvos-unified-experience.md hoofdstuk 10.4,
/// 10.5, 10.6), tested where it lives: as pure values and pure functions, with
/// no widget tree, no provider and no server.
///
/// The rule this file exists to pin is 10.4's "geen filter tonen dat
/// UnifiedCatalogQuery niet correct kan uitvoeren", and specifically the two
/// halves that are easy to get backwards: capabilities follow the *current*
/// participating set, and an unexecutable filter is suppressed on the way to
/// the query without ever being deleted from what the user chose.

CatalogLibrary _library(String serverId, String libraryId, MediaBackend backend) => (
  serverId: ServerId(serverId),
  serverName: serverId.toUpperCase(),
  libraryId: libraryId,
  libraryTitle: 'Library $libraryId',
  backend: backend,
);

void main() {
  group('capabilities are the intersection of the participating backends', () {
    test('Plex and Jellyfin execute every global filter', () {
      final capabilities = unifiedFilterCapabilitiesFor([MediaBackend.plex, MediaBackend.jellyfin]);
      expect(capabilities.supportsMetadataFilters, isTrue);
      expect(capabilities.supportsWatchFilter, isTrue);
    });

    // `pleya_server_client/parts/browse.dart` passes only sort, offset and
    // limit, and the PS-1 wire contract is frozen. Offering a genre filter over
    // a catalog containing one would present that server's whole library as
    // matches.
    test('one Pleya Server library suppresses the item filters for everyone', () {
      final capabilities = unifiedFilterCapabilitiesFor([
        MediaBackend.plex,
        MediaBackend.jellyfin,
        MediaBackend.pleyaServer,
      ]);
      expect(capabilities.supportsMetadataFilters, isFalse);
      expect(capabilities.supportsWatchFilter, isFalse);
    });

    // Jellyfin has `Filters=IsPlayed`; Plex `unwatched=0` is undocumented as
    // "watched only", so one Plex library withholds Bekeken for everyone.
    test('watched is offered only when every backend is Jellyfin', () {
      expect(unifiedFilterCapabilitiesFor([MediaBackend.jellyfin]).supportsWatchedFilter, isTrue);
      expect(unifiedFilterCapabilitiesFor([MediaBackend.plex, MediaBackend.jellyfin]).supportsWatchedFilter, isFalse);
      expect(unifiedFilterCapabilitiesFor([MediaBackend.plex]).supportsWatchedFilter, isFalse);
      expect(
        unifiedFilterCapabilitiesFor([MediaBackend.jellyfin, MediaBackend.pleyaServer]).supportsWatchedFilter,
        isFalse,
      );
    });

    test('an empty catalog promises nothing rather than everything', () {
      expect(unifiedFilterCapabilitiesFor(const []), UnifiedFilterCapabilities.none);
    });
  });

  group('source filters decide who takes part', () {
    final plex = _library('nas', '1', MediaBackend.plex);
    final jellyfin = _library('attic', '2', MediaBackend.jellyfin);
    final pleya = _library('shed', '3', MediaBackend.pleyaServer);

    test('an empty selection selects everything', () {
      const selection = UnifiedCatalogFilterSelection.empty;
      expect([plex, jellyfin, pleya].where(selection.selects), hasLength(3));
    });

    test('a server filter keeps only that server', () {
      const selection = UnifiedCatalogFilterSelection(serverIds: {'nas'});
      expect([plex, jellyfin, pleya].where(selection.selects).map((l) => l.libraryId), ['1']);
    });

    test('server and library filters are ANDed, not ORed', () {
      const selection = UnifiedCatalogFilterSelection(serverIds: {'nas'}, libraryKeys: {'attic:2'});
      expect(
        [plex, jellyfin].where(selection.selects),
        isEmpty,
        reason: 'picking a server and then a library on another means neither, not both',
      );
    });

    // The behaviour the user asked to be sure of: excluding the backend that
    // cannot filter has to bring genre and year back, rather than its mere
    // existence disabling them permanently.
    test('excluding the incapable backend restores the item filters', () {
      const restricted = UnifiedCatalogFilterSelection(serverIds: {'nas', 'attic'});
      final participating = [plex, jellyfin, pleya].where(restricted.selects);
      final capabilities = unifiedFilterCapabilitiesFor(participating.map((l) => l.backend));

      expect(participating, hasLength(2));
      expect(capabilities.supportsMetadataFilters, isTrue);
      expect(capabilities.supportsWatchFilter, isTrue);
    });
  });

  group('the stored selection survives what it cannot currently execute', () {
    const stored = UnifiedCatalogFilterSelection(
      genres: {'Drama'},
      audioLanguages: {'eng'},
      years: {2024},
      watchState: UnifiedWatchFilter.unwatched,
      serverIds: {'nas'},
    );

    test('constrainedTo drops what cannot run, and only that', () {
      final effective = stored.constrainedTo(UnifiedFilterCapabilities.none);
      expect(effective.genres, isEmpty);
      expect(effective.audioLanguages, isEmpty);
      expect(effective.years, isEmpty);
      expect(effective.watchState, UnifiedWatchFilter.all);
      expect(effective.serverIds, {'nas'}, reason: 'source filters are backend-independent');
    });

    test('a Pleya Server in the mix drops Actief bezig and Leeftijd, and keeps them stored', () {
      const selection = UnifiedCatalogFilterSelection(
        watchState: UnifiedWatchFilter.inProgress,
        officialRatings: {'12'},
      );
      final effective = selection.constrainedTo(
        unifiedFilterCapabilitiesFor([MediaBackend.jellyfin, MediaBackend.pleyaServer]),
      );
      expect(effective.watchState, UnifiedWatchFilter.all);
      expect(effective.officialRatings, isEmpty);
      expect(selection.watchState, UnifiedWatchFilter.inProgress);
    });

    test('constrainedTo never mutates the stored value', () {
      stored.constrainedTo(UnifiedFilterCapabilities.none);
      expect(stored.genres, {'Drama'}, reason: 'suppressing a filter must be reversible');
      expect(stored.audioLanguages, {'eng'});
      expect(stored.years, {2024});
      expect(stored.watchState, UnifiedWatchFilter.unwatched);
    });

    // Hoofdstuk 10.6's other pruning rule, which *is* destructive on purpose: a
    // key naming a server that no longer exists has no row left to untick it.
    test('withKnownSources drops vanished servers and libraries', () {
      const selection = UnifiedCatalogFilterSelection(serverIds: {'nas', 'gone'}, libraryKeys: {'nas:1', 'gone:9'});
      final pruned = selection.withKnownSources(knownServerIds: {'nas'}, knownLibraryKeys: {'nas:1'});
      expect(pruned.serverIds, {'nas'});
      expect(pruned.libraryKeys, {'nas:1'});
    });

    test('withKnownSources returns the same instance when nothing changed', () {
      const selection = UnifiedCatalogFilterSelection(serverIds: {'nas'});
      expect(
        identical(selection.withKnownSources(knownServerIds: {'nas'}, knownLibraryKeys: const {}), selection),
        isTrue,
        reason: 'an unchanged selection must not look like a change and restart the merge',
      );
    });
  });

  // ---------------------------------------------------------------------------
  // CAT20: a server that has merely not finished connecting yet must not lose
  // its stored library keys either, the same race withKnownSources's plain
  // server-id prune already survives. Caught by whole-branch review: the first
  // CAT20 fix widened only the server set, so a viewer's next filter/sort
  // change wrote the slow server's library selection away permanently, one
  // level below what the original bug report and its own test covered.
  // ---------------------------------------------------------------------------

  group('pruneStoredSourceFilter, CAT20', () {
    const stored = UnifiedCatalogPreferences(
      filters: UnifiedCatalogFilterSelection(serverIds: {'plexflix', 'nas'}, libraryKeys: {'plexflix:7', 'nas:1'}),
    );

    test('a library on a server that has not bound yet is not pruned out', () {
      final pruning = pruneStoredSourceFilter(
        stored: stored,
        boundServerIds: {'nas'},
        boundLibraryKeys: {'nas:1'},
        registeredServerIds: {'plexflix', 'nas'},
      );

      expect(pruning.preferences.filters.serverIds, contains('plexflix'));
      expect(
        pruning.preferences.filters.libraryKeys,
        contains('plexflix:7'),
        reason: 'plexflix has not bound yet, so its stored library is unproven, not gone',
      );
      expect(pruning.shouldPersist, isFalse, reason: 'the source list is not complete yet');
    });

    test('a library on a bound server that no longer reports it is pruned', () {
      final pruning = pruneStoredSourceFilter(
        stored: stored,
        boundServerIds: {'plexflix', 'nas'},
        boundLibraryKeys: {'nas:1'},
        registeredServerIds: {'plexflix', 'nas'},
      );

      expect(
        pruning.preferences.filters.libraryKeys,
        isNot(contains('plexflix:7')),
        reason: 'plexflix is fully bound and did not report this library, so it really is gone',
      );
      expect(pruning.shouldPersist, isTrue, reason: 'the source list is now complete');
    });
  });

  group('active count is per narrowing, not per value', () {
    test('three genres are one filter', () {
      const selection = UnifiedCatalogFilterSelection(genres: {'Drama', 'Comedy', 'Horror'});
      expect(selection.activeCount, 1);
    });

    test('every field counts once', () {
      const selection = UnifiedCatalogFilterSelection(
        genres: {'Drama'},
        audioLanguages: {'eng'},
        officialRatings: {'PG-13'},
        years: {2024},
        watchState: UnifiedWatchFilter.unwatched,
        serverIds: {'nas'},
        libraryKeys: {'nas:1'},
      );
      expect(selection.activeCount, 7);
      expect(selection.itemFilterCount, 5);
    });

    test('the default selection is empty and restricts no source', () {
      expect(UnifiedCatalogFilterSelection.empty.activeCount, 0);
      expect(UnifiedCatalogFilterSelection.empty.isEmpty, isTrue);
      expect(UnifiedCatalogFilterSelection.empty.restrictsSources, isFalse);
    });
  });

  group('the query a selection produces', () {
    UnifiedCatalogQuery build(
      UnifiedCatalogPreferences preferences, {
      UnifiedFilterCapabilities capabilities = const UnifiedFilterCapabilities(
        supportsMetadataFilters: true,
        supportsWatchFilter: true,
      ),
      MediaKind kind = MediaKind.movie,
    }) => buildUnifiedCatalogQuery(kind: kind, preferences: preferences, capabilities: capabilities);

    test('the default is Title A–Z over everything', () {
      final query = build(UnifiedCatalogPreferences.defaults);
      expect(query.sortField, UnifiedCatalogSortField.title);
      expect(query.sortDirection, LibrarySortDirection.ascending);
      expect(query.includeWatched, isTrue);
      expect(query.genres, isNull);
      expect(query.audioLanguages, isNull);
      expect(query.years, isNull);
    });

    test('Films and Series ask for different kinds of the same query', () {
      expect(build(UnifiedCatalogPreferences.defaults).kind, MediaKind.movie);
      expect(build(UnifiedCatalogPreferences.defaults, kind: MediaKind.show).kind, MediaKind.show);
    });

    test('every sort maps to a field and a direction the merge can compare', () {
      for (final sort in UnifiedCatalogSort.values) {
        final query = build(UnifiedCatalogPreferences(sort: sort));
        expect(query.sortField, sort.field);
        expect(query.sortDirection, sort.direction);
      }
    });

    test('unwatched becomes includeWatched: false', () {
      final query = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.unwatched),
        ),
      );
      expect(query.includeWatched, isFalse);
    });

    test('content ratings reach the query sorted', () {
      final query = build(
        const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(officialRatings: {'PG-13', '12'})),
      );
      expect(query.officialRatings, ['12', 'PG-13']);
      expect(query.toLibraryQuery(offset: 0, limit: 10).officialRatings, ['12', 'PG-13']);
    });

    test('a grouped Leeftijd choice sends every raw rating behind it', () {
      final query = build(
        const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(officialRatings: {'12|gb/12', 'PG-13'})),
      );
      expect(query.officialRatings, ['12', 'PG-13', 'gb/12']);
    });

    test('content ratings need the metadata capability, like genre', () {
      final query = build(
        const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(officialRatings: {'PG-13'})),
        capabilities: UnifiedFilterCapabilities.none,
      );
      expect(query.officialRatings, isNull);
    });

    test('in progress becomes inProgressOnly and keeps watched items in', () {
      final query = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.inProgress),
        ),
      );
      expect(query.inProgressOnly, isTrue);
      expect(query.watchedOnly, isFalse);
      expect(query.includeWatched, isTrue);
      expect(query.toLibraryQuery(offset: 0, limit: 10).inProgressOnly, isTrue);
    });

    test('watched becomes watchedOnly where the backends can execute it', () {
      final query = build(
        const UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.watched)),
        capabilities: const UnifiedFilterCapabilities(
          supportsMetadataFilters: true,
          supportsWatchFilter: true,
          supportsWatchedFilter: true,
        ),
      );
      expect(query.watchedOnly, isTrue);
      expect(query.includeWatched, isTrue);
      expect(query.toLibraryQuery(offset: 0, limit: 10).watchedOnly, isTrue);
    });

    test('watched without the capability falls back to everything, not to a guess', () {
      const stored = UnifiedCatalogFilterSelection(watchState: UnifiedWatchFilter.watched);
      final query = build(const UnifiedCatalogPreferences(filters: stored));
      expect(query.watchedOnly, isFalse);
      expect(query, build(UnifiedCatalogPreferences.defaults));
      expect(stored.watchState, UnifiedWatchFilter.watched, reason: 'the stored choice is never rewritten');
    });

    test('metadata filters reach the query sorted, so equal selections are equal queries', () {
      final a = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(
            genres: {'Horror', 'Drama'},
            audioLanguages: {'nld', 'eng'},
            years: {2024, 1999},
          ),
        ),
      );
      final b = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(
            genres: {'Drama', 'Horror'},
            audioLanguages: {'eng', 'nld'},
            years: {1999, 2024},
          ),
        ),
      );
      expect(a.genres, ['Drama', 'Horror']);
      expect(a.audioLanguages, ['eng', 'nld']);
      expect(a.years, [1999, 2024]);
      expect(a, b, reason: 'an unstable order would restart the merge on every rebuild');
    });

    // The whole point of threading capabilities through the builder.
    test('an unexecutable filter never reaches the query', () {
      final query = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(
            genres: {'Drama'},
            audioLanguages: {'eng'},
            years: {2024},
            watchState: UnifiedWatchFilter.unwatched,
          ),
        ),
        capabilities: UnifiedFilterCapabilities.none,
      );
      expect(query.genres, isNull);
      expect(query.audioLanguages, isNull);
      expect(query.years, isNull);
      expect(query.includeWatched, isTrue);
    });

    test('source filters are absent from the query entirely', () {
      final query = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(serverIds: {'nas'}, libraryKeys: {'nas:1'}),
        ),
      );
      expect(
        query,
        build(UnifiedCatalogPreferences.defaults),
        reason: 'they are executed by leaving a cursor out of the merge, not by narrowing the page request',
      );
    });
  });

  group('preferences round-trip through storage', () {
    test('a full selection survives encode and decode', () {
      const preferences = UnifiedCatalogPreferences(
        sort: UnifiedCatalogSort.newestRelease,
        filters: UnifiedCatalogFilterSelection(
          genres: {'Drama', 'Comedy'},
          audioLanguages: {'eng', 'nld'},
          officialRatings: {'PG-13', '12'},
          years: {2024, 1999},
          watchState: UnifiedWatchFilter.unwatched,
          serverIds: {'nas'},
          libraryKeys: {'nas:1'},
        ),
      );
      expect(UnifiedCatalogPreferences.fromJson(preferences.toJson()), preferences);
      expect(preferences.toJson()['officialRatings'], ['12', 'PG-13']);
    });

    test('every watch state survives encode and decode', () {
      for (final state in UnifiedWatchFilter.values) {
        final preferences = UnifiedCatalogPreferences(filters: UnifiedCatalogFilterSelection(watchState: state));
        expect(UnifiedCatalogPreferences.fromJson(preferences.toJson()).filters.watchState, state);
      }
    });

    // Home rows and catalog setups stored by older builds carry `watch:
    // unwatched` or nothing; a value from a newer build must not throw.
    test('old and unknown watch values decode safely', () {
      expect(
        UnifiedCatalogPreferences.fromJson({'watch': 'unwatched'}).filters.watchState,
        UnifiedWatchFilter.unwatched,
      );
      expect(UnifiedCatalogPreferences.fromJson({'watch': 'rewatching'}).filters.watchState, UnifiedWatchFilter.all);
      expect(UnifiedCatalogPreferences.fromJson(const {}).filters.watchState, UnifiedWatchFilter.all);
    });

    test('the defaults serialise to just their sort', () {
      expect(UnifiedCatalogPreferences.defaults.toJson(), {'sort': 'titleAsc'});
    });

    // This runs while a page is opening. A stored sort from a newer build, or
    // one dropped from hoofdstuk 10.5, must not stop the page from rendering.
    test('an unknown sort falls back instead of throwing', () {
      expect(UnifiedCatalogPreferences.fromJson({'sort': 'byVibes'}).sort, UnifiedCatalogSort.titleAsc);
      expect(UnifiedCatalogPreferences.fromJson(const {}).sort, UnifiedCatalogSort.titleAsc);
    });

    test('malformed collections decode as empty rather than throwing', () {
      final decoded = UnifiedCatalogPreferences.fromJson({
        'sort': 'titleAsc',
        'genres': 'Drama',
        'years': [2024, 'nineteen', null],
        'servers': [1, 'nas', ''],
      });
      expect(decoded.filters.genres, isEmpty);
      expect(decoded.filters.years, {2024});
      expect(decoded.filters.serverIds, {'nas'});
    });
  });
}
