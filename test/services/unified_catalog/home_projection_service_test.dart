/// Covers [HomeProjectionService]'s fase-6 contract: stable row ids, fair
/// interleave over merged sources (hoofdstuk 17.3), dedup scoped to one row
/// (17.4), Continue Watching keeping its exact episode identity (11.8/13.3),
/// and one failing server never emptying a healthy row (21.4).
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_hub.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/unified_media_hub.dart';
import 'package:pleya/services/unified_catalog/home_projection_service.dart';
import 'package:pleya/utils/external_ids.dart';

MediaItem _movie(
  String id, {
  required String serverId,
  String title = 'Dune',
  int? year = 2021,
  String? guid,
  String serverName = 'Plex Familie',
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.movie,
  title: title,
  year: year,
  guid: guid,
  serverId: serverId,
  serverName: serverName,
);

MediaItem _episode(
  String id, {
  required String serverId,
  String show = 'Severance',
  String showId = 'show-1',
  int? season = 1,
  int? episode = 3,
  int? lastViewedAt,
  int? viewOffsetMs = 600000,
  String? guid,
  String serverName = 'Plex Familie',
}) => MediaItem(
  id: id,
  backend: MediaBackend.plex,
  kind: MediaKind.episode,
  title: 'Episode $episode',
  guid: guid,
  grandparentId: showId,
  grandparentTitle: show,
  parentIndex: season,
  index: episode,
  durationMs: 2400000,
  viewOffsetMs: viewOffsetMs,
  lastViewedAt: lastViewedAt,
  serverId: serverId,
  serverName: serverName,
);

MediaHub _hub({
  required String id,
  String? identifier,
  String title = 'Top Picks',
  String type = 'movie',
  String? libraryId,
  required String serverId,
  String serverName = 'Plex Familie',
  required List<MediaItem> items,
}) => MediaHub(
  id: id,
  identifier: identifier,
  title: title,
  type: type,
  items: items,
  libraryId: libraryId,
  serverId: serverId,
  serverName: serverName,
);

HomeProjectionService _service({Map<String, ExternalIds> ids = const {}, List<String>? fetchLog}) =>
    HomeProjectionService(
      fetchExternalIds: (serverId, targetId) async {
        fetchLog?.add('$serverId:$targetId');
        return ids['$serverId:$targetId'] ?? const ExternalIds();
      },
    );

void main() {
  group('projectHubs — row identity', () {
    test('the same topology projects byte-identical row ids twice over', () async {
      final hubs = [
        _hub(
          id: '/hubs/home/continue',
          identifier: 'home.continue',
          serverId: 'a',
          items: [_movie('1', serverId: 'a')],
        ),
        _hub(
          id: '/hubs/home/toppicks',
          identifier: 'home.toppicks',
          serverId: 'b',
          items: [_movie('2', serverId: 'b')],
        ),
      ];

      final first = await _service().projectHubs(hubs);
      final second = await _service().projectHubs(hubs);

      expect([for (final hub in first) hub.hubId], [for (final hub in second) hub.hubId]);
      expect(first.first.hubId, isNot(first.last.hubId));
    });

    test('a row id survives the same row arriving from a different server first', () async {
      final fromA = _hub(
        id: 'x',
        identifier: 'home.continue',
        serverId: 'a',
        items: [_movie('1', serverId: 'a')],
      );
      final fromB = _hub(
        id: 'y',
        identifier: 'home.continue',
        serverId: 'b',
        serverName: 'Jellyfin',
        items: [_movie('2', serverId: 'b', title: 'Arrival', year: 2016, serverName: 'Jellyfin')],
      );

      final aFirst = await _service().projectHubs([fromA, fromB]);
      final bFirst = await _service().projectHubs([fromB, fromA]);

      expect(aFirst.single.hubId, bFirst.single.hubId);
      expect(
        aFirst.single.title,
        bFirst.single.title,
        reason: 'title comes from the ranked contributor, not the fastest',
      );
    });
  });

  group('projectHubs — merging', () {
    test('two servers sharing an identifier become one global row that names no server', () async {
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.continue',
          serverId: 'a',
          items: [_movie('1', serverId: 'a')],
        ),
        _hub(
          id: 'y',
          identifier: 'home.continue',
          serverId: 'b',
          serverName: 'Jellyfin',
          items: [_movie('2', serverId: 'b', title: 'Arrival', year: 2016, serverName: 'Jellyfin')],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(rows, hasLength(1));
      expect(rows.single.serverName, isNull);
      expect(rows.single.isServerSpecific, isFalse);
    });

    test('a merged row keeps both legacy home-layout ids so a hidden row stays hidden', () async {
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.continue',
          serverId: 'a',
          items: [_movie('1', serverId: 'a')],
        ),
        _hub(
          id: 'y',
          identifier: 'home.continue',
          serverId: 'b',
          serverName: 'Jellyfin',
          items: [_movie('2', serverId: 'b', title: 'Arrival', year: 2016, serverName: 'Jellyfin')],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(rows.single.contributingRowIds, containsAll(['a:home.continue', 'b:home.continue']));
    });

    test('one server contributing two hubs under one key is ambiguous and never merges them', () async {
      // Several "Because you watched" rows share one identifier; the reason
      // that tells them apart is not on MediaHub.
      final hubs = [
        _hub(
          id: '/hubs/byw/1',
          identifier: 'home.becausewatched',
          title: 'Because you watched Dune',
          serverId: 'a',
          items: [_movie('1', serverId: 'a')],
        ),
        _hub(
          id: '/hubs/byw/2',
          identifier: 'home.becausewatched',
          title: 'Because you watched Arrival',
          serverId: 'a',
          items: [_movie('2', serverId: 'a', title: 'Sicario', year: 2015)],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(rows, hasLength(2));
      expect(rows.map((r) => r.hubId).toSet(), hasLength(2));
      expect(rows.every((r) => r.serverName == 'Plex Familie'), isTrue);
    });

    test('an identifier-less hub stays server-specific and keeps its server name', () async {
      final hubs = [
        _hub(
          id: '/hubs/sections/3/recent',
          serverId: 'a',
          items: [_movie('1', serverId: 'a')],
        ),
        _hub(
          id: '/hubs/sections/3/recent',
          serverId: 'b',
          serverName: 'Jellyfin',
          items: [_movie('2', serverId: 'b', title: 'Arrival', year: 2016, serverName: 'Jellyfin')],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(rows, hasLength(2));
      expect(rows.first.serverName, 'Plex Familie');
      expect(rows.last.serverName, 'Jellyfin');
    });
  });

  group('projectHubs — ranking', () {
    test('merged sources interleave fairly instead of one server taking the row', () async {
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.toppicks',
          serverId: 'a',
          serverName: 'Aaa',
          items: [
            _movie('a1', serverId: 'a', title: 'A One', serverName: 'Aaa'),
            _movie('a2', serverId: 'a', title: 'A Two', serverName: 'Aaa'),
            _movie('a3', serverId: 'a', title: 'A Three', serverName: 'Aaa'),
          ],
        ),
        _hub(
          id: 'y',
          identifier: 'home.toppicks',
          serverId: 'b',
          serverName: 'Bbb',
          items: [
            _movie('b1', serverId: 'b', title: 'B One', serverName: 'Bbb'),
            _movie('b2', serverId: 'b', title: 'B Two', serverName: 'Bbb'),
          ],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(
        [for (final group in rows.single.groups) group.representativeSource.item.id],
        ['a1', 'b1', 'a2', 'b2', 'a3'],
      );
    });

    test('contributor order comes from server identity, never from input order', () async {
      final fromA = _hub(
        id: 'x',
        identifier: 'home.toppicks',
        serverId: 'a',
        serverName: 'Aaa',
        items: [_movie('a1', serverId: 'a', title: 'A One', serverName: 'Aaa')],
      );
      final fromB = _hub(
        id: 'y',
        identifier: 'home.toppicks',
        serverId: 'b',
        serverName: 'Bbb',
        items: [_movie('b1', serverId: 'b', title: 'B One', serverName: 'Bbb')],
      );

      final bAnswersFirst = await _service().projectHubs([fromB, fromA]);

      expect([for (final group in bAnswersFirst.single.groups) group.representativeSource.item.id], ['a1', 'b1']);
    });
  });

  group('projectHubs — dedup scope', () {
    test('one title on two servers is one card with two sources inside a row', () async {
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.toppicks',
          serverId: 'a',
          items: [_movie('a1', serverId: 'a', guid: 'plex://movie/5d776')],
        ),
        _hub(
          id: 'y',
          identifier: 'home.toppicks',
          serverId: 'b',
          serverName: 'Jellyfin',
          items: [_movie('b1', serverId: 'b', guid: 'plex://movie/5d776', serverName: 'Jellyfin')],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(rows.single.groups, hasLength(1));
      expect(rows.single.groups.single.sources, hasLength(2));
      expect(rows.single.groups.single.hasMultipleSources, isTrue);
    });

    test('the same title may appear in two different rows — dedup is per row, not per Home', () async {
      final dune = _movie('a1', serverId: 'a', guid: 'plex://movie/5d776');
      final hubs = [
        _hub(id: 'x', identifier: 'home.continue', title: 'Continue Watching', serverId: 'a', items: [dune]),
        _hub(id: 'y', identifier: 'home.toppicks', title: 'Top Picks', serverId: 'a', items: [dune]),
      ];

      final rows = await _service().projectHubs(hubs);

      expect(rows, hasLength(2));
      expect(rows.every((row) => row.groups.length == 1), isTrue);
      expect(rows.first.groups.single.representativeSource.item.title, 'Dune');
      expect(rows.last.groups.single.representativeSource.item.title, 'Dune');
    });
  });

  group('projectHubs — partial failure and boundaries', () {
    test('a failed server marks a global row partial but never empties it', () async {
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.toppicks',
          serverId: 'a',
          items: [
            _movie('a1', serverId: 'a'),
            _movie('a2', serverId: 'a', title: 'Arrival', year: 2016),
          ],
        ),
      ];

      final rows = await _service().projectHubs(hubs, failedServerIds: {'b'});

      expect(rows.single.isPartial, isTrue);
      expect(rows.single.groups, hasLength(2));
    });

    test('a server-specific row is not partial: its own server plainly answered', () async {
      final hubs = [
        _hub(
          id: '/hubs/sections/3/recent',
          serverId: 'a',
          items: [_movie('a1', serverId: 'a')],
        ),
      ];

      final rows = await _service().projectHubs(hubs, failedServerIds: {'b'});

      expect(rows.single.isPartial, isFalse);
    });

    test('an external-id fetch that throws degrades that item, it does not fail the row', () async {
      final service = HomeProjectionService(
        fetchExternalIds: (serverId, targetId) async => throw StateError('server $serverId is offline'),
      );
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.toppicks',
          serverId: 'a',
          items: [
            _movie('a1', serverId: 'a'),
            _movie('a2', serverId: 'a'),
          ],
        ),
      ];

      final rows = await service.projectHubs(hubs);

      expect(rows.single.groups, hasLength(2), reason: 'no evidence means no merge, not no row');
    });

    test('no title leaves a projection that did not enter it', () async {
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.toppicks',
          serverId: 'a',
          items: [_movie('a1', serverId: 'a')],
        ),
      ];

      final rows = await _service().projectHubs(hubs);

      final projectedKeys = {
        for (final row in rows)
          for (final group in row.groups)
            for (final source in group.sources) source.sourceKey,
      };
      expect(projectedKeys, {'a:a1'});
    });

    test('projection never fetches beyond the injected external-id callback', () async {
      final fetchLog = <String>[];
      final hubs = [
        _hub(
          id: 'x',
          identifier: 'home.toppicks',
          serverId: 'a',
          items: [
            _movie('a1', serverId: 'a'),
            _movie('a2', serverId: 'a', title: 'Arrival', year: 2016),
          ],
        ),
      ];

      await _service(fetchLog: fetchLog).projectHubs(hubs);

      // Two distinct titles: no duplicate bucket, so hoofdstuk 11.2 fase A
      // already answers and nothing at all is fetched.
      expect(fetchLog, isEmpty);
    });

    test('a row that projects to nothing is dropped rather than rendered empty', () async {
      final hubs = [_hub(id: 'x', identifier: 'home.toppicks', serverId: 'a', items: const [])];

      expect(await _service().projectHubs(hubs), isEmpty);
    });

    test('empty input projects to no rows', () async {
      expect(await _service().projectHubs(const []), isEmpty);
    });
  });

  group('projectContinueWatching', () {
    // Hoofdstuk 11.8, binding: Continue Watching groups on the exact episode —
    // `show identity + season + episode`. Every fixture below hands both rows
    // the *same* series-wide tmdb on purpose, so nothing here is green merely
    // because the external ids came back empty.
    test('C: the same episode on two servers is one card, and its sources stay the concrete episodes', () async {
      final onDeck = [
        _episode('a-e4', serverId: 'a', season: 2, episode: 4, lastViewedAt: 200),
        _episode('b-e4', serverId: 'b', season: 2, episode: 4, lastViewedAt: 100, serverName: 'Jellyfin'),
      ];
      final service = _service(
        ids: {'a:show-1': const ExternalIds(tmdb: 95396), 'b:show-1': const ExternalIds(tmdb: 95396)},
      );

      final row = await service.projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(1), reason: 'one card per logical episode');
      final sources = row.groups.single.sources;
      expect(sources, hasLength(2));
      expect(sources.every((s) => s.item.kind == MediaKind.episode), isTrue);
      expect(sources.map((s) => s.item.id), ['a-e4', 'b-e4']);
      expect(sources.map((s) => (s.item.parentIndex, s.item.index)), [(2, 4), (2, 4)]);
    });

    test('A/E: two episodes of one series stay two cards, on one shared series-wide id', () async {
      final onDeck = [
        _episode('a-e4', serverId: 'a', season: 2, episode: 4, lastViewedAt: 200),
        _episode('b-e5', serverId: 'b', season: 2, episode: 5, lastViewedAt: 100, serverName: 'Jellyfin'),
      ];
      // The same series tmdb *and* tvdb on both sides: the exact evidence the
      // old series-wide fold merged on.
      final service = _service(
        ids: {
          'a:show-1': const ExternalIds(tmdb: 95396, tvdb: 371980),
          'b:show-1': const ExternalIds(tmdb: 95396, tvdb: 371980),
        },
      );

      final row = await service.projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(2), reason: 'S02E04 and S02E05 are two Continue Watching cards');
      expect([for (final g in row.groups) g.representativeSource.item.id], ['a-e4', 'b-e5']);
      expect(row.groups.first.groupId, isNot(row.groups.last.groupId));
    });

    test('B: two seasons of one series stay two cards', () async {
      final onDeck = [
        _episode('a-s1e4', serverId: 'a', season: 1, episode: 4, lastViewedAt: 200),
        _episode('b-s2e4', serverId: 'b', season: 2, episode: 4, lastViewedAt: 100, serverName: 'Jellyfin'),
      ];
      final service = _service(
        ids: {'a:show-1': const ExternalIds(tmdb: 95396), 'b:show-1': const ExternalIds(tmdb: 95396)},
      );

      final row = await service.projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(2), reason: 'S01E04 and S02E04 are two Continue Watching cards');
      expect(
        {for (final g in row.groups) (g.representativeSource.item.parentIndex, g.representativeSource.item.index)},
        {(1, 4), (2, 4)},
      );
    });

    test('D: two servers reporting the same strong episode guid merge without any external id', () async {
      final onDeck = [
        _episode('a-e4', serverId: 'a', season: 2, episode: 4, guid: 'plex://episode/5d9c08', lastViewedAt: 200),
        _episode(
          'b-e4',
          serverId: 'b',
          season: 2,
          episode: 4,
          guid: 'plex://episode/5d9c08',
          lastViewedAt: 100,
          serverName: 'Plex Zolder',
        ),
      ];

      // No external ids at all: the episode guid is the whole case.
      final row = await _service().projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(1));
      expect(row.groups.single.sources.map((s) => s.item.id), ['a-e4', 'b-e4']);
    });

    test('D/E: a strong episode guid never merges two different episodes of one series', () async {
      final onDeck = [
        _episode('a-e4', serverId: 'a', season: 2, episode: 4, guid: 'plex://episode/5d9c08'),
        _episode('a-e5', serverId: 'a', season: 2, episode: 5, guid: 'plex://episode/5d9c09'),
      ];
      final service = _service(ids: {'a:show-1': const ExternalIds(tmdb: 95396)});

      final row = await service.projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(2));
    });

    test('F: distinct episodes with no external ids at all stay distinct', () async {
      final onDeck = [
        _episode('a-e4', serverId: 'a', season: 2, episode: 4),
        _episode('a-e5', serverId: 'a', season: 2, episode: 5),
      ];

      final row = await _service().projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(2));
      expect({for (final g in row.groups) g.groupId}, hasLength(2), reason: 'two cards need two stable ids');
    });

    test('G: episodes with no usable season or episode index never merge on their series alone', () async {
      // Hoofdstuk 11.8: ontbrekende indexen vereisen een sterk episode-ID.
      // Both rows resolve the same series tmdb and neither can prove which
      // episode it is, so the false-merge-is-worse-than-false-negative
      // invariant keeps them apart.
      final fetchLog = <String>[];
      final onDeck = [
        _episode('a-unknown', serverId: 'a', season: null, episode: null),
        _episode('b-unknown', serverId: 'b', season: null, episode: null, serverName: 'Jellyfin'),
      ];
      final service = _service(
        ids: {'a:show-1': const ExternalIds(tmdb: 95396), 'b:show-1': const ExternalIds(tmdb: 95396)},
        fetchLog: fetchLog,
      );

      final row = await service.projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(2));
      expect(fetchLog, isEmpty, reason: 'no exact-episode bucket means no series-wide id is even fetched');
    });

    test('J: the exact-episode identity leaves progress, ordering and the activation source alone', () async {
      // The identity fix must not become a watch-state or ordering change by
      // accident: every source keeps its own offset, cards stay in recency
      // order, and the group still activates through its own sources.
      final onDeck = [
        _episode('a-e4', serverId: 'a', season: 2, episode: 4, viewOffsetMs: 100, lastViewedAt: 300),
        _episode('b-e4', serverId: 'b', season: 2, episode: 4, viewOffsetMs: 800, lastViewedAt: 200, serverName: 'JF'),
        _episode('a-e5', serverId: 'a', season: 2, episode: 5, viewOffsetMs: 400, lastViewedAt: 900),
      ];
      final service = _service(
        ids: {'a:show-1': const ExternalIds(tmdb: 95396), 'b:show-1': const ExternalIds(tmdb: 95396)},
      );

      final row = await service.projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(
        [for (final g in row.groups) (g.representativeSource.item.parentIndex, g.representativeSource.item.index)],
        [(2, 5), (2, 4)],
        reason: 'newest recency first, unchanged by the identity fix',
      );
      final merged = row.groups.last;
      expect({for (final s in merged.sources) s.item.serverId!: s.item.viewOffsetMs}, {'a': 100, 'b': 800});
      expect(
        merged.sources.map((s) => s.sourceKey),
        contains(merged.representativeSourceKey),
        reason: 'the representative is one of the group\'s own sources, never a substitute',
      );
    });

    test('cards sort on the newest recency among their own sources', () async {
      final onDeck = [
        _episode('old', serverId: 'a', show: 'Andor', showId: 'show-9', lastViewedAt: 50),
        _episode('new', serverId: 'a', show: 'Severance', showId: 'show-1', lastViewedAt: 900),
        _episode('none', serverId: 'a', show: 'Fallout', showId: 'show-7', lastViewedAt: null),
      ];

      final row = await _service().projectContinueWatching(onDeck, title: 'Continue Watching');

      expect([for (final group in row.groups) group.representativeSource.item.id], ['new', 'old', 'none']);
    });

    test('undated cards keep their incoming order among themselves', () async {
      final onDeck = [
        _episode('first', serverId: 'a', show: 'Andor', showId: 'show-9', lastViewedAt: null),
        _episode('second', serverId: 'a', show: 'Fallout', showId: 'show-7', lastViewedAt: null),
      ];

      final row = await _service().projectContinueWatching(onDeck, title: 'Continue Watching');

      expect([for (final group in row.groups) group.representativeSource.item.id], ['first', 'second']);
    });

    test('two same-titled films with no shared identity stay two cards', () async {
      final onDeck = [
        _movie('a1', serverId: 'a', title: 'Dune', year: 2021),
        _movie('b1', serverId: 'b', title: 'Dune', year: 1984, serverName: 'Jellyfin'),
      ];

      final row = await _service().projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(2), reason: 'Continue Watching has never merged on title alone');
    });

    test('a row with no serverId is set aside instead of throwing', () async {
      final onDeck = [
        _episode('healthy', serverId: 'a', lastViewedAt: 100),
        MediaItem(id: 'orphan', backend: MediaBackend.plex, kind: MediaKind.movie, title: 'Dune', year: 2021),
      ];

      final row = await _service().projectContinueWatching(onDeck, title: 'Continue Watching');

      expect(row.groups, hasLength(1));
      expect(row.groups.single.representativeSource.item.id, 'healthy');
    });

    test('the row is synthesized, translated by its caller and keyed on its slug', () async {
      final row = await _service().projectContinueWatching(
        [_episode('a-e3', serverId: 'a', lastViewedAt: 100)],
        title: 'Verder kijken',
        failedServerIds: {'b'},
      );

      expect(row.title, 'Verder kijken');
      expect(row.hubId, UnifiedMediaHub.synthesizedHubId('continueWatching'));
      expect(row.serverName, isNull);
      expect(row.kind, UnifiedHubKind.episode);
      expect(row.isPartial, isTrue);
    });

    test('an empty on-deck list projects to an empty row rather than throwing', () async {
      final row = await _service().projectContinueWatching(const [], title: 'Continue Watching');

      expect(row.isEmpty, isTrue);
      expect(row.kind, UnifiedHubKind.other);
    });
  });
}
