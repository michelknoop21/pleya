/// Covers `catalog_service.dart`'s k-way merge engine against hoofdstuk 12 of
/// docs/tvos-unified-experience.md: global merge order across libraries,
/// duplicate collapsing, group-aware paging, contained per-library failure,
/// late-duplicate in-place merging, and query-change cancellation.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/unified_catalog/catalog_service.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

/// One fake server. Serves a fixed, already-sorted item list per library;
/// can be told to throw on the next fetch of a given library, or to gate
/// (stall) it until released.
class _FakeLibraryClient implements MediaServerClient {
  _FakeLibraryClient({this.itemsByLibrary = const {}});

  final Map<String, List<MediaItem>> itemsByLibrary;
  final Map<String, Object> throwOnce = {};
  final Map<String, Completer<void>> gate = {};
  final List<({String libraryId, int offset, int limit})> calls = [];

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    calls.add((libraryId: libraryId, offset: query.offset, limit: query.limit));
    final wait = gate.remove(libraryId);
    if (wait != null) await wait.future;
    final err = throwOnce.remove(libraryId);
    if (err != null) throw err;

    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeLibraryClient: ${invocation.memberName}');
}

MediaItem _movie(String id, {required String title, required String serverId, String? guid, int? addedAt, int? year}) =>
    MediaItem(
      id: id,
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      title: title,
      serverId: serverId,
      guid: guid,
      addedAt: addedAt,
      year: year,
    );

CatalogLibrary _library(String serverId, String libraryId) => (
  serverId: ServerId(serverId),
  serverName: serverId,
  libraryId: libraryId,
  backend: MediaBackend.plex,
  libraryTitle: libraryId,
);

void main() {
  group('UnifiedCatalogService k-way merge', () {
    test('merges two libraries into one globally title-ordered stream, collapsing a shared duplicate', () async {
      // Exactly hoofdstuk 12.2's worked example.
      final serverA = _FakeLibraryClient(
        itemsByLibrary: {
          'A': [
            _movie('a-avatar', title: 'Avatar', serverId: 's1'),
            _movie('a-dune', title: 'Dune', serverId: 's1', guid: 'plex://movie/dune'),
            _movie('a-oppenheimer', title: 'Oppenheimer', serverId: 's1'),
          ],
        },
      );
      final serverB = _FakeLibraryClient(
        itemsByLibrary: {
          'B': [
            _movie('b-alien', title: 'Alien', serverId: 's2'),
            _movie('b-dune', title: 'Dune', serverId: 's2', guid: 'plex://movie/dune'),
            // No shared guid for Heat — this pair merges via hoofdstuk 11.6's
            // weak title+year fallback instead, covering that contract path
            // too (Dune above already covers the strong-guid path).
            _movie('b-heat-1', title: 'Heat', serverId: 's2', year: 1995),
          ],
        },
      );
      final serverC = _FakeLibraryClient(
        itemsByLibrary: {
          'C': [
            _movie('c-arrival', title: 'Arrival', serverId: 's3'),
            _movie('c-heat-2', title: 'Heat', serverId: 's3', year: 1995),
            _movie('c-silo', title: 'Silo', serverId: 's3'),
          ],
        },
      );

      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('s1', 'A'), _library('s2', 'B'), _library('s3', 'C')],
        clientFor: (id) => switch (id.value) {
          's1' => serverA,
          's2' => serverB,
          's3' => serverC,
          _ => null,
        },
        pageSize: 50,
        groupsPerPage: 20,
      );

      final snapshot = await service.loadMore();

      expect(snapshot.groups.map((g) => g.representativeSource.item.title), [
        'Alien',
        'Arrival',
        'Avatar',
        'Dune',
        'Heat',
        'Oppenheimer',
        'Silo',
      ]);
      // "Dune" and "Heat" collapse to one group each with both sources.
      final titleCounts = <String, int>{};
      for (final g in snapshot.groups) {
        final title = g.representativeSource.item.title ?? '';
        titleCounts[title] = (titleCounts[title] ?? 0) + 1;
      }
      expect(titleCounts['Dune'], 1);
      expect(titleCounts['Heat'], 1);
      final dune = snapshot.groups.firstWhere((g) => g.representativeSource.item.title == 'Dune');
      expect(dune.sources, hasLength(2));
      expect(snapshot.isComplete, isTrue);
    });

    test('paging target is a group count: it stops at groupsPerPage new groups, not a raw item count', () async {
      // 6 raw items, sharing guids pairwise, so they collapse to 3 groups.
      final client = _FakeLibraryClient(
        itemsByLibrary: {
          'A': [
            _movie('a1', title: 'Alpha', serverId: 's1', guid: 'plex://movie/alpha'),
            _movie('a2', title: 'Bravo', serverId: 's1', guid: 'plex://movie/bravo'),
            _movie('a3', title: 'Charlie', serverId: 's1', guid: 'plex://movie/charlie'),
          ],
          'B': [
            _movie('b1', title: 'Alpha', serverId: 's1', guid: 'plex://movie/alpha'),
            _movie('b2', title: 'Bravo', serverId: 's1', guid: 'plex://movie/bravo'),
            _movie('b3', title: 'Charlie', serverId: 's1', guid: 'plex://movie/charlie'),
          ],
        },
      );

      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('s1', 'A'), _library('s1', 'B')],
        clientFor: (_) => client,
        pageSize: 50,
        groupsPerPage: 2,
        maxRawItemsPerLoadMore: 500,
      );

      final snapshot = await service.loadMore();

      // groupsPerPage=2, but the merge had to pop 4 raw items (Alpha+Alpha,
      // Bravo+Bravo) to produce those 2 groups.
      expect(snapshot.groups, hasLength(2));
      expect(snapshot.groups.map((g) => g.representativeSource.item.title), ['Alpha', 'Bravo']);
      expect(snapshot.isComplete, isFalse);
    });

    test('B14: an item the backend repeats on the next page does not become a second card', () async {
      // Offset paging over a library that changed underneath the reader: the
      // second page opens with the item the first page already delivered. The
      // repeat is the same concrete membership, not a second copy.
      final client = _FakeLibraryClient(
        itemsByLibrary: {
          'A': [
            _movie('a1', title: 'Alpha', serverId: 's1'),
            _movie('a2', title: 'Bravo', serverId: 's1'),
            _movie('a1', title: 'Alpha', serverId: 's1'),
            _movie('a3', title: 'Charlie', serverId: 's1'),
          ],
        },
      );

      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('s1', 'A')],
        clientFor: (_) => client,
        pageSize: 2,
        groupsPerPage: 20,
      );

      final snapshot = await service.loadMore();

      expect(snapshot.groups.map((g) => g.representativeSource.item.id), ['a1', 'a2', 'a3']);
      expect(snapshot.groups.every((g) => g.sources.length == 1), isTrue, reason: 'one file, one bron');
      expect(snapshot.isComplete, isTrue);
    });

    test('one library erroring leaves the healthy results in place, and is retried on the next call', () async {
      final healthy = _FakeLibraryClient(
        itemsByLibrary: {
          'A': [_movie('a1', title: 'Alpha', serverId: 's1')],
        },
      );
      final broken = _FakeLibraryClient(
        itemsByLibrary: {
          'B': [_movie('b1', title: 'Bravo', serverId: 's2')],
        },
      )..throwOnce['B'] = StateError('server down');

      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('s1', 'A'), _library('s2', 'B')],
        clientFor: (id) => id.value == 's1' ? healthy : broken,
      );

      final first = await service.loadMore();
      expect(first.groups.map((g) => g.representativeSource.item.title), ['Alpha']);
      expect(first.failedLibraryIds, {'s2:B'});
      expect(first.initialLoadFailed, isFalse, reason: 'one healthy library already produced a result');

      final second = await service.loadMore();
      expect(second.groups.map((g) => g.representativeSource.item.title), ['Alpha', 'Bravo']);
      expect(second.failedLibraryIds, isEmpty);
    });

    test('every library failing on the very first round reports initialLoadFailed', () async {
      final broken = _FakeLibraryClient(
        itemsByLibrary: {
          'A': [_movie('a1', title: 'Alpha', serverId: 's1')],
        },
      )..throwOnce['A'] = StateError('down');

      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('s1', 'A')],
        clientFor: (_) => broken,
      );

      final snapshot = await service.loadMore();

      expect(snapshot.groups, isEmpty);
      expect(snapshot.initialLoadFailed, isTrue);
      expect(snapshot.failedLibraryIds, {'s1:A'});
    });

    test(
      'a duplicate arriving many pages later merges into the existing group instead of creating a new one',
      () async {
        final serverA = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a-dune', title: 'Dune', serverId: 's1', guid: 'plex://movie/dune')],
          },
        );
        // Server B has one unrelated item ahead of its own "Dune" copy, so the
        // duplicate only surfaces on B's *second* page.
        final serverB = _FakeLibraryClient(
          itemsByLibrary: {
            'B': [
              _movie('b-early', title: 'Aardvark', serverId: 's2'),
              _movie('b-dune', title: 'Dune', serverId: 's2', guid: 'plex://movie/dune'),
            ],
          },
        );

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A'), _library('s2', 'B')],
          clientFor: (id) => id.value == 's1' ? serverA : serverB,
          pageSize: 1, // forces server B's "Dune" onto a later page
          groupsPerPage: 100,
        );

        final snapshot = await service.loadMore();

        expect(snapshot.isComplete, isTrue);
        expect(snapshot.groups.map((g) => g.representativeSource.item.title), ['Aardvark', 'Dune']);
        final dune = snapshot.groups.firstWhere((g) => g.representativeSource.item.title == 'Dune');
        expect(dune.sources, hasLength(2));
      },
    );

    group('I19: applyUpdatedSourceItem', () {
      test('re-reads one item in place without touching the cursors', () async {
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a1', title: 'Alpha', serverId: 's1'), _movie('a2', title: 'Bravo', serverId: 's1')],
          },
        );
        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
        );
        await service.loadMore();
        final callsBefore = client.calls.length;

        final updated = MediaItem(
          id: 'a1',
          backend: MediaBackend.plex,
          kind: MediaKind.movie,
          title: 'Alpha',
          serverId: 's1',
          viewOffsetMs: 60000,
          durationMs: 6000000,
          lastViewedAt: 1756000000,
        );
        final applied = service.applyUpdatedSourceItem(updated);

        expect(applied, isTrue);
        expect(client.calls.length, callsBefore, reason: 'no page is refetched for a state-only update');
        final group = service.snapshot.groups.singleWhere((g) => g.sources.any((s) => s.item.id == 'a1'));
        expect(group.watchState.hasActiveProgress, isTrue);
      });

      test('an item this merge never popped changes nothing', () async {
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a1', title: 'Alpha', serverId: 's1')],
          },
        );
        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
        );
        await service.loadMore();

        final applied = service.applyUpdatedSourceItem(
          MediaItem(id: 'elsewhere', backend: MediaBackend.plex, kind: MediaKind.movie, serverId: 's1'),
        );

        expect(applied, isFalse);
      });

      test('the update survives a later refresh, not just the current snapshot', () async {
        // The subtle failure this guards: `_recomputeGroups` rebuilds every
        // group from `_poppedItems` on the next page, so an update applied
        // only to the already-built groups would be silently reverted the
        // moment paging continued.
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [
              _movie('a1', title: 'Alpha', serverId: 's1'),
              _movie('a2', title: 'Bravo', serverId: 's1'),
              _movie('a3', title: 'Charlie', serverId: 's1'),
            ],
          },
        );
        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 1,
          groupsPerPage: 1,
        );
        await service.loadMore();
        service.applyUpdatedSourceItem(
          MediaItem(
            id: 'a1',
            backend: MediaBackend.plex,
            kind: MediaKind.movie,
            title: 'Alpha',
            serverId: 's1',
            viewOffsetMs: 60000,
            durationMs: 6000000,
          ),
        );

        await service.loadMore();

        final group = service.snapshot.groups.singleWhere((g) => g.sources.any((s) => s.item.id == 'a1'));
        expect(group.watchState.hasActiveProgress, isTrue);
      });

      test('the preference snapshot at the time of the call reaches tier 4', () async {
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a1', title: 'Alpha', serverId: 's1', guid: 'plex://movie/alpha')],
            'B': [_movie('b1', title: 'Alpha', serverId: 's1', guid: 'plex://movie/alpha')],
          },
        );
        var preferred = <String>{};
        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A'), _library('s1', 'B')],
          clientFor: (_) => client,
          preferredSourceKeys: () => preferred,
        );
        await service.loadMore();
        preferred = {'s1:b1'};

        service.applyUpdatedSourceItem(
          MediaItem(
            id: 'a1',
            backend: MediaBackend.plex,
            kind: MediaKind.movie,
            title: 'Alpha',
            serverId: 's1',
            guid: 'plex://movie/alpha',
            viewOffsetMs: 20000,
            durationMs: 6000000,
            lastViewedAt: 1756000000,
          ),
        );
        service.applyUpdatedSourceItem(
          MediaItem(
            id: 'b1',
            backend: MediaBackend.plex,
            kind: MediaKind.movie,
            title: 'Alpha',
            serverId: 's1',
            guid: 'plex://movie/alpha',
            viewOffsetMs: 20000,
            durationMs: 6000000,
            lastViewedAt: 1756000000,
          ),
        );

        final group = service.snapshot.groups.single;
        expect(group.watchState.representativeSourceKey, 's1:b1');
      });
    });

    test('a stale in-flight fetch from before a query change never lands in the new state', () async {
      final client = _FakeLibraryClient(
        itemsByLibrary: {
          'A': [_movie('a-old', title: 'OldQueryItem', serverId: 's1')],
        },
      );
      // Captured locally: fetchLibraryPagedContent pops this straight out of
      // client.gate the moment it runs (before this test gets a chance to
      // run any more code), so removing it from the map a second time below
      // would be a no-op — the only live reference afterwards is this one.
      final gate = Completer<void>();
      client.gate['A'] = gate;

      final service = UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('s1', 'A')],
        clientFor: (_) => client,
      );

      final staleFuture = service.loadMore(); // hangs on the gate

      service.updateQuery(
        query: const UnifiedCatalogQuery(kind: MediaKind.show),
        libraries: [_library('s1', 'A')],
      );
      gate.complete(); // release the stale fetch now

      final staleResult = await staleFuture;
      expect(
        staleResult.groups,
        isEmpty,
        reason: 'the response for the abandoned generation must not populate the new query\'s state',
      );
      expect(service.query.kind, MediaKind.show);
    });
  });
}
