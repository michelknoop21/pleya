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
      years: {2024},
      watchState: UnifiedWatchFilter.unwatched,
      serverIds: {'nas'},
    );

    test('constrainedTo drops what cannot run, and only that', () {
      final effective = stored.constrainedTo(UnifiedFilterCapabilities.none);
      expect(effective.genres, isEmpty);
      expect(effective.years, isEmpty);
      expect(effective.watchState, UnifiedWatchFilter.all);
      expect(effective.serverIds, {'nas'}, reason: 'source filters are backend-independent');
    });

    test('constrainedTo never mutates the stored value', () {
      stored.constrainedTo(UnifiedFilterCapabilities.none);
      expect(stored.genres, {'Drama'}, reason: 'suppressing a filter must be reversible');
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

  group('active count is per narrowing, not per value', () {
    test('three genres are one filter', () {
      const selection = UnifiedCatalogFilterSelection(genres: {'Drama', 'Comedy', 'Horror'});
      expect(selection.activeCount, 1);
    });

    test('every field counts once', () {
      const selection = UnifiedCatalogFilterSelection(
        genres: {'Drama'},
        years: {2024},
        watchState: UnifiedWatchFilter.unwatched,
        serverIds: {'nas'},
        libraryKeys: {'nas:1'},
      );
      expect(selection.activeCount, 5);
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

    test('genres and years reach the query sorted, so equal selections are equal queries', () {
      final a = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(genres: {'Horror', 'Drama'}, years: {2024, 1999}),
        ),
      );
      final b = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(genres: {'Drama', 'Horror'}, years: {1999, 2024}),
        ),
      );
      expect(a.genres, ['Drama', 'Horror']);
      expect(a.years, [1999, 2024]);
      expect(a, b, reason: 'an unstable order would restart the merge on every rebuild');
    });

    // The whole point of threading capabilities through the builder.
    test('an unexecutable filter never reaches the query', () {
      final query = build(
        const UnifiedCatalogPreferences(
          filters: UnifiedCatalogFilterSelection(
            genres: {'Drama'},
            years: {2024},
            watchState: UnifiedWatchFilter.unwatched,
          ),
        ),
        capabilities: UnifiedFilterCapabilities.none,
      );
      expect(query.genres, isNull);
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
          years: {2024, 1999},
          watchState: UnifiedWatchFilter.unwatched,
          serverIds: {'nas'},
          libraryKeys: {'nas:1'},
        ),
      );
      expect(UnifiedCatalogPreferences.fromJson(preferences.toJson()), preferences);
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
