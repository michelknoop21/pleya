/// Identity decides, the title only gathers candidates.
///
/// The numbers a server's list answer already carries (Plex `includeGuids`,
/// Jellyfin and Emby `ProviderIds`, Pleya Server `external_ids`) are read off
/// the item, so the same title under another name or year on another server is
/// one card, and nothing costs a request per title. These tests also count the
/// requests, as a measurement of cost and not as a proof of efficiency.
library;

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/services/jellyfin_mappers.dart';
import 'package:pleya/services/plex_mappers.dart';
import 'package:pleya/services/pleya_server_mappers.dart';
import 'package:pleya/models/pleya_server/pleya_wire_library.dart';
import 'package:pleya/services/unified_catalog/catalog_service.dart';
import 'package:pleya/services/unified_catalog/source_cursor.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_query.dart';
import 'package:pleya/services/unified_catalog/unified_catalog_snapshot.dart';
import 'package:pleya/utils/external_ids.dart';
import 'package:pleya/utils/media_server_http_client.dart';

MediaItem _plexShow(
  String id,
  String title,
  int year, {
  int? tmdb,
  int? tvdb,
  String server = 'srv-plex',
  bool guids = true,
}) => MediaItem.plex(
  id: id,
  kind: MediaKind.show,
  title: title,
  year: year,
  serverId: server,
  serverName: server,
  raw: guids
      ? {
          'Guid': [
            if (tmdb != null) {'id': 'tmdb://$tmdb'},
            if (tvdb != null) {'id': 'tvdb://$tvdb'},
          ],
        }
      : null,
);

MediaItem _jellyfinShow(String id, String title, int year, {int? tmdb, String server = 'srv-jf'}) => MediaItem.jellyfin(
  id: id,
  kind: MediaKind.show,
  title: title,
  year: year,
  serverId: server,
  serverName: server,
  raw: {
    'ProviderIds': {if (tmdb != null) 'Tmdb': '$tmdb'},
  },
);

MediaItem _pleyaShow(String id, String title, int year, {int? tmdb, MediaKind kind = MediaKind.show}) => MediaItem(
  id: id,
  backend: MediaBackend.pleyaServer,
  kind: kind,
  title: title,
  year: year,
  serverId: 'srv-pleya',
  serverName: 'srv-pleya',
  raw: {pleyaExternalIdsRawKey: ExternalIds(tmdb: tmdb).toJson()},
);

class _Client implements MediaServerClient {
  _Client(this._backend, this.shows);

  final MediaBackend _backend;
  final List<MediaItem> shows;
  int pageRequests = 0;
  final List<String> idLookups = [];

  @override
  MediaBackend get backend => _backend;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    pageRequests++;
    final sorted = [...shows]..sort((a, b) => (a.title ?? '').compareTo(b.title ?? ''));
    final end = (query.offset + query.limit).clamp(0, sorted.length);
    return LibraryPage(
      items: query.offset >= sorted.length ? const [] : sorted.sublist(query.offset, end),
      totalCount: sorted.length,
      offset: query.offset,
    );
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    idLookups.add(itemId);
    return const ExternalIds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('_Client: ${invocation.memberName}');
}

CatalogLibrary _library(String serverId, MediaBackend backend) =>
    (serverId: ServerId(serverId), serverName: serverId, libraryId: 'lib', backend: backend, libraryTitle: 'lib');

Future<UnifiedCatalogSnapshot> _drain(UnifiedCatalogService service) async {
  var snapshot = await service.loadMore();
  for (var i = 0; i < 100 && !snapshot.isComplete; i++) {
    snapshot = await service.loadMore();
  }
  expect(snapshot.isComplete, isTrue);
  return snapshot;
}

void main() {
  group('the numbers survive the list answer', () {
    test('Plex keeps the Guid array of an includeGuids answer', () {
      final item = PlexMappers.mediaItemFromJson({
        'ratingKey': '1',
        'type': 'show',
        'title': 'The Office (US)',
        'year': 2005,
        'Guid': [
          {'id': 'imdb://tt0386676'},
          {'id': 'tmdb://2316'},
          {'id': 'tvdb://73244'},
        ],
      });
      expect(externalIdsCarriedBy(item), const ExternalIds(imdb: 'tt0386676', tmdb: 2316, tvdb: 73244));
    });

    test('a Plex answer without Guid carries nothing, so the title is looked up as before', () {
      final item = PlexMappers.mediaItemFromJson({'ratingKey': '1', 'type': 'show', 'title': 'X', 'year': 2005});
      expect(externalIdsCarriedBy(item), isNull);
    });

    test('Jellyfin and Emby keep ProviderIds', () {
      final item = JellyfinMappers.mediaItem(
        {
          'Id': 'j1',
          'Type': 'Series',
          'Name': 'The Office',
          'ProductionYear': 2005,
          'ProviderIds': {'Tmdb': '2316', 'Imdb': 'tt0386676'},
        },
        serverId: ServerId('srv-jf'),
        absolutizer: null,
      )!;
      expect(externalIdsCarriedBy(item), const ExternalIds(imdb: 'tt0386676', tmdb: 2316));
    });

    test('Pleya Server carries numbers only when the server sent the key', () {
      PleyaItem wire(Map<String, dynamic> extra) => PleyaItem.fromJson({
        'id': 'p1',
        'kind': 'show',
        'title': 'The Office',
        'added_at': '2026-06-18T21:34:02Z',
        ...extra,
      });
      expect(
        externalIdsCarriedBy(
          PleyaServerMappers.mediaItem(
            wire({
              'external_ids': {'tmdb': 2316},
            }),
            serverId: 's',
          ),
        ),
        const ExternalIds(tmdb: 2316),
      );
      expect(
        externalIdsCarriedBy(PleyaServerMappers.mediaItem(wire({'external_ids': null}), serverId: 's')),
        const ExternalIds(),
        reason: 'the server knows the field and says: no numbers',
      );
      expect(
        externalIdsCarriedBy(PleyaServerMappers.mediaItem(wire({}), serverId: 's')),
        isNull,
        reason: 'older server',
      );
    });

    test('episodes never carry their own numbers into identity', () {
      final episode = MediaItem.plex(
        id: 'e',
        kind: MediaKind.episode,
        title: 'Pilot',
        raw: {
          'Guid': [
            {'id': 'tmdb://1'},
          ],
        },
      );
      expect(externalIdsCarriedBy(episode), isNull);
    });
  });

  group('identity decides, the title only gathers candidates', () {
    const query = UnifiedCatalogQuery(kind: MediaKind.show);

    Future<(UnifiedCatalogSnapshot, _Client, _Client, _Client)> run(
      List<MediaItem> plexShows,
      List<MediaItem> jellyfinShows,
      List<MediaItem> pleyaShows,
    ) async {
      final plex = _Client(MediaBackend.plex, plexShows);
      final jellyfin = _Client(MediaBackend.jellyfin, jellyfinShows);
      final pleya = _Client(MediaBackend.pleyaServer, pleyaShows);
      final clients = {'srv-plex': plex, 'srv-jf': jellyfin, 'srv-pleya': pleya};
      final service = UnifiedCatalogService(
        query: query,
        libraries: [
          _library('srv-plex', MediaBackend.plex),
          _library('srv-jf', MediaBackend.jellyfin),
          _library('srv-pleya', MediaBackend.pleyaServer),
        ],
        clientFor: (id) => clients[id.value],
      );
      return (await _drain(service), plex, jellyfin, pleya);
    }

    test('the same series under another title and year on each server is one card with all sources', () async {
      final (snapshot, plex, jellyfin, pleya) = await run(
        [_plexShow('p1', 'The Office (US)', 2005, tmdb: 2316)],
        [_jellyfinShow('j1', 'The Office', 2005, tmdb: 2316)],
        [_pleyaShow('s1', 'Het Kantoor', 2004, tmdb: 2316)],
      );

      expect(snapshot.groups, hasLength(1));
      expect(snapshot.groups.single.sources.map((s) => s.backend).toSet(), {
        MediaBackend.plex,
        MediaBackend.jellyfin,
        MediaBackend.pleyaServer,
      });
      expect([...plex.idLookups, ...jellyfin.idLookups, ...pleya.idLookups], isEmpty, reason: 'no request per title');
    });

    test('same-named remakes and different series with the same name stay apart', () async {
      final (snapshot, _, _, _) = await run(
        [_plexShow('p-bsg78', 'Battlestar Galactica', 1978, tmdb: 1), _plexShow('p-ghosts', 'Ghosts', 2021, tmdb: 120)],
        [_jellyfinShow('j-ghosts', 'Ghosts', 2019, tmdb: 99)],
        [_pleyaShow('s-bsg04', 'Battlestar Galactica', 2004, tmdb: 71)],
      );

      expect(snapshot.groups, hasLength(4));
      expect(snapshot.groups.every((g) => g.sources.length == 1), isTrue);
    });

    test('the same title and year with different numbers stays apart, also on title-only fallback backends', () async {
      final (snapshot, _, _, _) = await run(
        [_plexShow('p', 'Fargo', 2014, tmdb: 60622)],
        [_jellyfinShow('j', 'Fargo', 2014, tmdb: 5)],
        const [],
      );
      expect(snapshot.groups, hasLength(2));
    });

    test('a movie and a show with the same numeric TMDB id never share a card', () async {
      final plexMovie = MediaItem.plex(
        id: 'pm',
        kind: MediaKind.movie,
        title: 'Twins',
        year: 2020,
        serverId: 'srv-plex',
        serverName: 'srv-plex',
        raw: {
          'Guid': [
            {'id': 'tmdb://1100'},
          ],
        },
      );
      final groups = await UnifiedCatalogService(
        query: const UnifiedCatalogQuery(kind: MediaKind.movie),
        libraries: [_library('srv-plex', MediaBackend.plex)],
        clientFor: (_) => _Client(MediaBackend.plex, [plexMovie]),
      ).loadMore();
      final shows = await run(const [], const [], [_pleyaShow('s', 'Twins', 2020, tmdb: 1100)]);
      // Two catalogs, two kinds: the token scope keeps them apart even if a
      // caller mixed them; a mixed grouping is covered in unified_pleya_server_test.
      expect(groups.groups.single.sources.single.backend, MediaBackend.plex);
      expect(shows.$1.groups.single.sources.single.backend, MediaBackend.pleyaServer);
    });

    test('without carried numbers the title still gathers candidates and the lookup decides', () async {
      final (snapshot, plex, _, _) = await run(
        [_plexShow('p1', 'Severance', 2022, guids: false)],
        const [],
        [_pleyaShow('s1', 'Severance', 2021, tmdb: 95396)],
      );
      expect(plex.idLookups, ['p1'], reason: 'one lookup, only for the title that shares a name with another server');
      // The fake answers with no numbers, so there is no proof: two cards.
      expect(snapshot.groups, hasLength(2));
    });
  });

  group('measured requests (cost, not a proof of efficiency)', () {
    const query = UnifiedCatalogQuery(kind: MediaKind.show);

    List<MediaItem> plexShows(int n, {required bool guids}) => [
      for (var i = 0; i < n; i++) _plexShow('p$i', 'Show $i', 2000, tmdb: 1000 + i, guids: guids),
    ];
    List<MediaItem> pleyaShows(int n) => [
      for (var i = 0; i < n; i += 2) _pleyaShow('s$i', 'Serie $i', 2001, tmdb: 1000 + i),
    ];

    Future<(UnifiedCatalogSnapshot, _Client)> pass(List<MediaItem> plexItems, List<MediaItem> pleyaItems) async {
      final plex = _Client(MediaBackend.plex, plexItems);
      final pleya = _Client(MediaBackend.pleyaServer, pleyaItems);
      final service = UnifiedCatalogService(
        query: query,
        libraries: [_library('srv-plex', MediaBackend.plex), _library('srv-pleya', MediaBackend.pleyaServer)],
        clientFor: (id) => id.value == 'srv-plex' ? plex : pleya,
        pageSize: 200,
        groupsPerPage: 1000,
        maxRawItemsPerLoadMore: 5000,
      );
      final snapshot = await _drain(service);
      service.refresh();
      await _drain(service);
      return (snapshot, plex);
    }

    test('600 Plex + 300 Pleya titles with carried numbers: cold start and a rebuild cost 0 id lookups', () async {
      final (snapshot, plex) = await pass(plexShows(600, guids: true), pleyaShows(600));

      expect(snapshot.groups, hasLength(600));
      expect(
        snapshot.groups.where((g) => g.sources.length == 2),
        hasLength(300),
        reason: 'titles differ, numbers match',
      );
      expect(plex.idLookups, isEmpty);
    });

    test(
      'the same set from a Plex server that sends no Guid: the titles differ, so nothing is gathered and nothing folds',
      () async {
        final (snapshot, plex) = await pass(plexShows(600, guids: false), pleyaShows(600));

        expect(plex.idLookups, isEmpty, reason: 'no shared title, no candidate, no lookup');
        expect(snapshot.groups, hasLength(900), reason: 'without numbers different titles are never merged');
      },
    );

    test('an account switch builds new clients: the new pass again costs 0 id lookups', () async {
      await pass(plexShows(100, guids: true), pleyaShows(100));
      final (_, plexAfterSwitch) = await pass(plexShows(100, guids: true), pleyaShows(100));
      expect(plexAfterSwitch.idLookups, isEmpty);
    });
  });
}
