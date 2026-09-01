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
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/unified_catalog/catalog_service.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_snapshot.dart';
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

  /// E8: a lying/inconsistent `totalCount`, independent of what
  /// [itemsByLibrary] actually holds — this is the field a real backend's
  /// count can drift on while the concrete pages stay honest.
  final Map<String, int Function(int callNumber)> totalCountOverride = {};
  final Map<String, int> _callCount = {};

  /// E8's other pathological case: a backend that answers with the exact
  /// same page every time, ignoring the offset it was given.
  final Set<String> repeatsFirstPageForever = {};
  final Map<String, List<MediaItem>> _lastServedPage = {};

  /// E12: the [AbortController] most recently handed to a call still in
  /// flight, so a test can assert `cancelInFlight()` actually triggered it.
  AbortController? lastAbortController;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    calls.add((libraryId: libraryId, offset: query.offset, limit: query.limit));
    lastAbortController = abort;
    final wait = gate.remove(libraryId);
    if (wait != null) await wait.future;
    final err = throwOnce.remove(libraryId);
    if (err != null) throw err;

    final all = itemsByLibrary[libraryId] ?? const <MediaItem>[];
    List<MediaItem> slice;
    if (repeatsFirstPageForever.contains(libraryId) && _lastServedPage.containsKey(libraryId)) {
      slice = _lastServedPage[libraryId]!;
    } else {
      final end = (query.offset + query.limit).clamp(0, all.length);
      slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
      if (repeatsFirstPageForever.contains(libraryId)) _lastServedPage[libraryId] = slice;
    }

    final callNumber = (_callCount[libraryId] ?? 0) + 1;
    _callCount[libraryId] = callNumber;
    final total = totalCountOverride[libraryId]?.call(callNumber) ?? all.length;

    return LibraryPage<MediaItem>(items: slice, totalCount: total, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('_FakeLibraryClient: ${invocation.memberName}');
}

MediaItem _movie(
  String id, {
  required String title,
  required String serverId,
  String? guid,
  int? addedAt,
  int? year,
  int? lastViewedAt,
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  serverId: serverId,
  guid: guid,
  addedAt: addedAt,
  year: year,
  lastViewedAt: lastViewedAt,
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

    group('B6: a mixed library splits correctly by catalog', () {
      // This fake, unlike the plain _FakeLibraryClient above, actually
      // narrows by query.kind — mimicking what PlexLibraryQueryTranslator's
      // `type=` and JellyfinLibraryQueryTranslator's `IncludeItemTypes`
      // already do server-side (both separately tested in
      // library_query_translator_test.dart). The point proven here is the
      // seam: eligibleCatalogLibraries() admits the mixed library, and the
      // service's per-query kind then does the real per-item split, so one
      // physical library correctly becomes zero, one or two logical rows
      // depending which catalog is asking.
      test('a movie and a show in one mixed library each surface under their own catalog only', () async {
        final movie = _movie('m1', title: 'Alpha', serverId: 's1');
        final show = MediaItem(
          id: 's1',
          backend: MediaBackend.plex,
          kind: MediaKind.show,
          title: 'Bravo',
          serverId: 's1',
        );
        final client = _KindFilteringLibraryClient(itemsByLibrary: {
          'mixed': [movie, show],
        });
        final eligibleForFilms = eligibleCatalogLibraries(
          libraries: [
            MediaLibrary(id: 'mixed', backend: MediaBackend.plex, title: 'Mixed', kind: MediaKind.unknown, serverId: 's1'),
          ],
          kind: MediaKind.movie,
          isServerVisible: (_) => true,
          hiddenLibraryKeys: const {},
        );
        final eligibleForSeries = eligibleCatalogLibraries(
          libraries: [
            MediaLibrary(id: 'mixed', backend: MediaBackend.plex, title: 'Mixed', kind: MediaKind.unknown, serverId: 's1'),
          ],
          kind: MediaKind.show,
          isServerVisible: (_) => true,
          hiddenLibraryKeys: const {},
        );

        final filmsService = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: eligibleForFilms,
          clientFor: (_) => client,
        );
        final seriesService = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.show),
          libraries: eligibleForSeries,
          clientFor: (_) => client,
        );

        final filmsSnapshot = await filmsService.loadMore();
        final seriesSnapshot = await seriesService.loadMore();

        expect(filmsSnapshot.groups.map((g) => g.representativeSource.item.title), ['Alpha']);
        expect(seriesSnapshot.groups.map((g) => g.representativeSource.item.title), ['Bravo']);
      });

      test('a library holding neither kind answers empty for both, rather than guessing', () {
        final client = _KindFilteringLibraryClient(
          itemsByLibrary: {
            'mixed': [
              MediaItem(id: 'p1', backend: MediaBackend.plex, kind: MediaKind.photo, title: 'A Photo', serverId: 's1'),
            ],
          },
        );

        Future<UnifiedCatalogSnapshot> snapshotFor(MediaKind kind) {
          final eligible = eligibleCatalogLibraries(
            libraries: [
              MediaLibrary(id: 'mixed', backend: MediaBackend.plex, title: 'Mixed', kind: MediaKind.unknown, serverId: 's1'),
            ],
            kind: kind,
            isServerVisible: (_) => true,
            hiddenLibraryKeys: const {},
          );
          return UnifiedCatalogService(
            query: UnifiedCatalogQuery(kind: kind),
            libraries: eligible,
            clientFor: (_) => client,
          ).loadMore();
        }

        expect(
          Future.wait([snapshotFor(MediaKind.movie), snapshotFor(MediaKind.show)]).then(
            (snapshots) => snapshots.every((s) => s.groups.isEmpty),
          ),
          completion(isTrue),
        );
      });
    });

    group('E12: cancelInFlight (hoofdstuk 22, profile switch)', () {
      test('aborts every cursor\'s outstanding fetch', () async {
        final gate = Completer<void>();
        final client = _FakeLibraryClient(itemsByLibrary: {'A': [_movie('a1', title: 'Alpha', serverId: 's1')]})
          ..gate['A'] = gate;

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
        );
        final pending = service.loadMore(); // stuck on the gate

        service.cancelInFlight();

        expect(client.lastAbortController?.isAborted, isTrue);
        gate.complete();
        await pending;
      });

      test('is safe to call with nothing in flight', () async {
        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: const [],
          clientFor: (_) => null,
        );

        expect(service.cancelInFlight, returnsNormally);
      });

      test('does not change loadMore\'s outward exhaustion/error accounting', () async {
        // cancelInFlight is a teardown-only call, not a second `_reset` — it
        // must not, for example, bump the generation and quietly turn a
        // legitimate response into a "superseded" no-op for the very call
        // that is already resolving with the gate below.
        final client = _FakeLibraryClient(itemsByLibrary: {'A': [_movie('a1', title: 'Alpha', serverId: 's1')]});

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
        );

        service.cancelInFlight(); // nothing was in flight yet — must be a no-op
        final snapshot = await service.loadMore();

        expect(snapshot.groups, hasLength(1));
      });
    });

    group('E5: a slow source does not block the fast ones (hoofdstuk 12.6)', () {
      test('a fast library\'s items appear without waiting out a slow sibling', () async {
        final fast = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a1', title: 'Alpha', serverId: 's1'), _movie('a2', title: 'Bravo', serverId: 's1')],
          },
        );
        final slow = _FakeLibraryClient(itemsByLibrary: {'B': [_movie('b1', title: 'Charlie', serverId: 's2')]})
          ..gate['B'] = Completer<void>(); // never released in this test — genuinely stuck

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A'), _library('s2', 'B')],
          clientFor: (id) => id.value == 's1' ? fast : slow,
          groupsPerPage: 20,
          progressiveLoadingGrace: const Duration(milliseconds: 10),
        );
        addTearDown(() => slow.gate['B']?.complete());

        final stopwatch = Stopwatch()..start();
        final snapshot = await service.loadMore();
        stopwatch.stop();

        expect(
          snapshot.groups.map((g) => g.representativeSource.item.title),
          containsAll(['Alpha', 'Bravo']),
          reason: 'the fast library\'s own two items must not wait on the stuck one',
        );
        expect(
          stopwatch.elapsed,
          lessThan(const Duration(seconds: 1)),
          reason: 'bounded by progressiveLoadingGrace, not the slow fetch actually resolving',
        );
      });

      test('the slow source is not abandoned — its answer merges in on a later call', () async {
        final fast = _FakeLibraryClient(itemsByLibrary: {'A': [_movie('a1', title: 'Alpha', serverId: 's1')]});
        final gate = Completer<void>();
        final slow = _FakeLibraryClient(itemsByLibrary: {'B': [_movie('b1', title: 'Charlie', serverId: 's2')]})
          ..gate['B'] = gate;

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A'), _library('s2', 'B')],
          clientFor: (id) => id.value == 's1' ? fast : slow,
          groupsPerPage: 20,
          progressiveLoadingGrace: const Duration(milliseconds: 10),
        );

        final first = await service.loadMore();
        expect(first.groups.map((g) => g.representativeSource.item.title), ['Alpha']);
        expect(first.isComplete, isFalse, reason: 'B has not answered yet, so this is not the whole catalogue');

        gate.complete();
        // Give the still-running fetch a chance to actually land before the
        // next loadMore() call looks for it.
        await Future<void>.delayed(const Duration(milliseconds: 20));
        final second = await service.loadMore();

        expect(
          second.groups.map((g) => g.representativeSource.item.title),
          containsAll(['Alpha', 'Charlie']),
          reason: 'B is in-place merged once it answers, with no extra fetch needed to notice it',
        );
        expect(second.isComplete, isTrue);
      });

      test('a cursor still in flight past the grace period is never asked for the same page twice', () async {
        final gate = Completer<void>();
        final slow = _FakeLibraryClient(itemsByLibrary: {'A': [_movie('a1', title: 'Alpha', serverId: 's1')]})
          ..gate['A'] = gate;

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => slow,
          groupsPerPage: 20,
          progressiveLoadingGrace: const Duration(milliseconds: 10),
        );

        // Two rounds inside one loadMore() call both find A already in
        // flight and not buffered — a naive re-check could fire a second,
        // redundant request for the same page while the first is still out.
        final result = await service.loadMore();
        expect(result.groups, isEmpty);
        expect(slow.calls, hasLength(1), reason: 'still in flight must exclude the cursor, not invite a duplicate ask');

        gate.complete();
      });
    });

    group('E10: a group\'s sort position follows the aggregate rule, not pop order', () {
      // Hoofdstuk 12.4: "Toegevoegd: hoogste addedAt van deelnemende
      // bronnen" / "Recent bekeken: meest recente geldige watch-state". Both
      // duplicates are available in the same round here (no gating), so this
      // is the case the k-way merge's own comparator decides directly: the
      // position a group lands at is the position of whichever member the
      // configured sort field ranks first, which is exactly the aggregate
      // rule when both members are visible to the comparator at once.
      test('addedAt descending: the group sorts on the higher of the two, not whichever server answered first', () async {
        // Server A alone would sort Bravo before Alpha (its own addedAt is
        // higher for Bravo); the duplicate on server B carries a materially
        // higher addedAt for Alpha, so the merged Alpha card must still lead.
        final serverA = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [
              _movie('a-bravo', title: 'Bravo', serverId: 's1', addedAt: 2000, guid: 'plex://movie/bravo'),
              _movie('a-alpha', title: 'Alpha', serverId: 's1', addedAt: 1000, guid: 'plex://movie/alpha'),
            ],
          },
        );
        final serverB = _FakeLibraryClient(
          itemsByLibrary: {
            'B': [_movie('b-alpha', title: 'Alpha', serverId: 's2', addedAt: 5000, guid: 'plex://movie/alpha')],
          },
        );

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(
            kind: MediaKind.movie,
            sortField: UnifiedCatalogSortField.addedAt,
            sortDirection: LibrarySortDirection.descending,
          ),
          libraries: [_library('s1', 'A'), _library('s2', 'B')],
          clientFor: (id) => id.value == 's1' ? serverA : serverB, // both fetch in the same first round
          pageSize: 50,
          groupsPerPage: 20,
        );

        final snapshot = await service.loadMore();

        expect(
          snapshot.groups.map((g) => g.representativeSource.item.title),
          ['Alpha', 'Bravo'],
          reason: 'the duplicate\'s higher addedAt must win the position, not server A\'s own internal order',
        );
        expect(snapshot.groups.first.sources, hasLength(2));
      });

      test('recentlyWatched descending: the group sorts on the most recently watched of its sources', () async {
        final serverA = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [
              _movie('a-bravo', title: 'Bravo', serverId: 's1', lastViewedAt: 5000, guid: 'plex://movie/bravo'),
              _movie('a-alpha', title: 'Alpha', serverId: 's1', lastViewedAt: 1000, guid: 'plex://movie/alpha'),
            ],
          },
        );
        final serverB = _FakeLibraryClient(
          itemsByLibrary: {
            'B': [_movie('b-alpha', title: 'Alpha', serverId: 's2', lastViewedAt: 9000, guid: 'plex://movie/alpha')],
          },
        );

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(
            kind: MediaKind.movie,
            sortField: UnifiedCatalogSortField.recentlyWatched,
            sortDirection: LibrarySortDirection.descending,
          ),
          libraries: [_library('s1', 'A'), _library('s2', 'B')],
          clientFor: (id) => id.value == 's1' ? serverA : serverB,
          pageSize: 50,
          groupsPerPage: 20,
        );

        final snapshot = await service.loadMore();

        expect(snapshot.groups.map((g) => g.representativeSource.item.title), ['Alpha', 'Bravo']);
      });

      test('a tie on the sort field itself falls back to the stable group id', () async {
        // 12.4's own fallback tie-break. Two genuinely different titles that
        // happen to share an addedAt must still land in a deterministic,
        // repeatable order rather than whichever the merge race favoured.
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [
              _movie('a-zulu', title: 'Zulu', serverId: 's1', addedAt: 1000),
              _movie('a-alpha', title: 'Alpha', serverId: 's1', addedAt: 1000),
            ],
          },
        );

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie, sortDirection: LibrarySortDirection.descending),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 50,
          groupsPerPage: 20,
        );

        final first = (await service.loadMore()).groups.map((g) => g.groupId).toList();

        final again = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie, sortDirection: LibrarySortDirection.descending),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 50,
          groupsPerPage: 20,
        );
        final second = (await again.loadMore()).groups.map((g) => g.groupId).toList();

        expect(second, first, reason: 'a genuine tie must resolve the same way every time');
      });
    });

    group('E8: totalCount is advisory, never sole exhaustion authority', () {
      test('a total that shrinks mid-session never drops a not-yet-fetched item', () async {
        // 5 real items over pageSize 2. The reported total starts honest and
        // then shrinks to 3 on the second call — a raw `offset >= total`
        // check would call this exhausted after only 4 items.
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [for (var i = 0; i < 5; i++) _movie('a$i', title: 'Film $i', serverId: 's1')],
          },
        )..totalCountOverride['A'] = (call) => call == 1 ? 5 : 3;

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 2,
          groupsPerPage: 20,
        );

        await service.loadMore();

        expect(service.snapshot.groups.map((g) => g.representativeSource.item.id), ['a0', 'a1', 'a2', 'a3', 'a4']);
        expect(service.isComplete, isTrue);
      });

      test('a total that grows mid-session still terminates on the short final page', () async {
        // The total starts at 2 (as if that were the whole library) and
        // grows to 5 once the caller has already fetched further — the
        // short/empty-page signal must be what actually ends this, not a
        // total that happened to look satisfied early.
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [for (var i = 0; i < 5; i++) _movie('a$i', title: 'Film $i', serverId: 's1')],
          },
        )..totalCountOverride['A'] = (call) => call == 1 ? 2 : 5;

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 2,
          groupsPerPage: 20,
        );

        await service.loadMore();

        expect(service.snapshot.groups, hasLength(5));
        expect(service.isComplete, isTrue);
      });

      test('an empty final page ends the cursor regardless of what the total claims', () async {
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a0', title: 'Alpha', serverId: 's1'), _movie('a1', title: 'Bravo', serverId: 's1')],
          },
          // A total that overclaims forever — only the empty page can end this.
        )..totalCountOverride['A'] = (_) => 999;

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 2,
          groupsPerPage: 20,
        );

        await service.loadMore();

        expect(service.isComplete, isTrue);
        expect(service.snapshot.groups, hasLength(2));
      });

      test('a repeated identical page marks the cursor exhausted instead of looping', () async {
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [_movie('a0', title: 'Alpha', serverId: 's1'), _movie('a1', title: 'Bravo', serverId: 's1')],
          },
        )
          ..repeatsFirstPageForever.add('A')
          ..totalCountOverride['A'] = (_) => 999; // never honest, never short either

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 2,
          groupsPerPage: 20,
          maxRawItemsPerLoadMore: 40,
        );

        await service.loadMore();

        expect(service.isComplete, isTrue, reason: 'a repeating page must not spin forever');
        expect(service.snapshot.groups, hasLength(2), reason: 'the repeated items are the same two, not duplicated');
        expect(client.calls.length, lessThan(5), reason: 'detected on the very next fetch, not after many retries');
      });

      test('no premature exhaustion: a genuinely large library still delivers every page', () async {
        // The negative control for all of the above: normal offset paging,
        // an honest total, must still terminate correctly and deliver
        // everything — none of the new guards may fire on ordinary data.
        final client = _FakeLibraryClient(
          itemsByLibrary: {
            'A': [for (var i = 0; i < 11; i++) _movie('a$i', title: 'Film $i', serverId: 's1')],
          },
        );

        final service = UnifiedCatalogService(
          query: const UnifiedCatalogQuery(kind: MediaKind.movie),
          libraries: [_library('s1', 'A')],
          clientFor: (_) => client,
          pageSize: 3,
          groupsPerPage: 20,
        );

        while (!service.isComplete) {
          await service.loadMore();
        }

        expect(service.snapshot.groups, hasLength(11));
        expect(service.snapshot.groups.map((g) => g.representativeSource.item.id), [for (var i = 0; i < 11; i++) 'a$i']);
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


/// A fake that actually narrows its answer by `query.kind`, unlike
/// `_FakeLibraryClient` above — the shape a mixed library's own server-side
/// filter (Plex `type=`, Jellyfin `IncludeItemTypes`) produces. Only the
/// per-library item pool and the kind filter matter for B6's tests; paging,
/// gating and error injection are `_FakeLibraryClient`'s job.
class _KindFilteringLibraryClient implements MediaServerClient {
  _KindFilteringLibraryClient({this.itemsByLibrary = const {}});

  final Map<String, List<MediaItem>> itemsByLibrary;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    final all = (itemsByLibrary[libraryId] ?? const <MediaItem>[])
        .where((item) => query.kind == null || item.kind == query.kind)
        .toList();
    final end = (query.offset + query.limit).clamp(0, all.length);
    final slice = query.offset >= all.length ? const <MediaItem>[] : all.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: all.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
