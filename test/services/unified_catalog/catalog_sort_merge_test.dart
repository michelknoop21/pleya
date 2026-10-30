/// The merge against the two ways a server can place titles without a value,
/// across page boundaries, per sort field and per pair of backends. Where a
/// server puts its nulls is in no API document, so both are tested.
library;

import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/external_rating.dart';
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

class _Server implements MediaServerClient {
  _Server(this.items);

  final List<MediaItem> items;
  int calls = 0;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    calls++;
    final end = (query.offset + query.limit).clamp(0, items.length);
    final slice = query.offset >= items.length ? const <MediaItem>[] : items.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: items.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

CatalogLibrary _library(String serverId, MediaBackend backend) =>
    (serverId: ServerId(serverId), serverName: serverId, libraryId: 'lib', backend: backend, libraryTitle: 'lib');

MediaItem _plex(String title, double? rating, {String server = 'p'}) =>
    PlexMediaItem(id: title, kind: MediaKind.movie, title: title, rating: rating, serverId: server);

MediaItem _jellyfin(String title, double? critic, {String server = 'j'}) => JellyfinMediaItem(
  id: title,
  kind: MediaKind.movie,
  title: title,
  serverId: server,
  externalRatings: [
    if (critic != null) ExternalRating(source: ExternalRatingSource.rottenTomatoesCritic, value: critic),
  ],
);

Future<List<String?>> _merge(
  Map<CatalogLibrary, List<MediaItem>> sources,
  UnifiedCatalogQuery query, {
  int pageSize = 2,
  int groupsPerPage = 3,
}) async {
  final servers = {for (final e in sources.entries) e.key.serverId: _Server(e.value)};
  final service = UnifiedCatalogService(
    query: query,
    libraries: sources.keys.toList(),
    clientFor: (id) => servers[id],
    pageSize: pageSize,
    groupsPerPage: groupsPerPage,
  );
  for (var i = 0; i < 40 && !service.isComplete; i++) {
    await service.loadMore();
  }
  return [for (final group in service.snapshot.groups) group.representativeSource.item.title];
}

const _criticDown = UnifiedCatalogQuery(
  kind: MediaKind.movie,
  sortField: UnifiedCatalogSortField.criticRating,
  sortDirection: LibrarySortDirection.descending,
);
const _criticUp = UnifiedCatalogQuery(
  kind: MediaKind.movie,
  sortField: UnifiedCatalogSortField.criticRating,
  sortDirection: LibrarySortDirection.ascending,
);

void main() {
  group('one library', () {
    test('a server that sends its nulls first still ends on them', () async {
      final titles = await _merge({
        _library('p', MediaBackend.plex): [
          _plex('NoneA', null),
          _plex('NoneB', null),
          _plex('NoneC', null),
          _plex('Low', 2),
          _plex('High', 9),
        ],
      }, _criticUp);
      expect(titles, ['Low', 'High', 'NoneA', 'NoneB', 'NoneC']);
    });

    test('a server that sends its nulls last is not read to its end for a first page', () async {
      final items = [_plex('Top', 9), for (var i = 0; i < 40; i++) _plex('None$i', null)];
      final server = _Server(items);
      final service = UnifiedCatalogService(
        query: _criticDown,
        libraries: [_library('p', MediaBackend.plex)],
        clientFor: (_) => server,
        pageSize: 10,
        groupsPerPage: 5,
      );
      await service.loadMore();
      expect(service.snapshot.groups.first.representativeSource.item.title, 'Top');
      expect(server.calls, 1);
    });

    test('a library without a single value still shows, past the bound', () async {
      final cursor = UnifiedSourceCursor(_library('p', MediaBackend.plex));
      cursor.accept([_plex('A', null), _plex('B', null)], hasSortValue: (_) => false, maxHeldBack: 2);
      expect(cursor.buffer, hasLength(2));
      expect(cursor.heldBack, isEmpty);
    });

    test('a library that is nothing but titles without a value completes', () async {
      final titles = await _merge({
        _library('p', MediaBackend.plex): [_plex('B', null), _plex('A', null), _plex('C', null)],
      }, _criticDown);
      expect(titles, ['B', 'A', 'C']);
    });
  });

  group('a key that does not know what the server sorted on', () {
    const recentSeries = UnifiedCatalogQuery(
      kind: MediaKind.show,
      sortField: UnifiedCatalogSortField.recentlyWatched,
      sortDirection: LibrarySortDirection.descending,
    );

    MediaItem jellyfinSeries(String title, {int? lastViewedAt, String server = 'j'}) =>
        JellyfinMediaItem(id: title, kind: MediaKind.show, title: title, lastViewedAt: lastViewedAt, serverId: server);

    test('Jellyfin series without LastPlayedDate stay in SeriesDatePlayed order', () async {
      final titles = await _merge({
        _library('j', MediaBackend.jellyfin): [
          jellyfinSeries('Zebra'),
          jellyfinSeries('Monk'),
          jellyfinSeries('Alias'),
        ],
      }, recentSeries);
      expect(titles, ['Zebra', 'Monk', 'Alias']);
    });

    test('the first page is the server\'s first page, from one request', () async {
      final server = _Server([for (var i = 0; i < 60; i++) jellyfinSeries('S${99 - i}')]);
      final service = UnifiedCatalogService(
        query: recentSeries,
        libraries: [_library('j', MediaBackend.jellyfin)],
        clientFor: (_) => server,
        pageSize: 50,
        groupsPerPage: 20,
      );
      await service.loadMore();
      expect(service.snapshot.groups.first.representativeSource.item.title, 'S99');
      expect(service.snapshot.groups, hasLength(20));
      expect(server.calls, 1);
    });

    test('one series that does carry a date moves nothing', () async {
      final titles = await _merge({
        _library('j', MediaBackend.jellyfin): [
          jellyfinSeries('Zebra'),
          jellyfinSeries('Monk'),
          jellyfinSeries('Marked', lastViewedAt: 5),
          jellyfinSeries('Alias'),
        ],
      }, recentSeries);
      expect(titles, ['Zebra', 'Monk', 'Marked', 'Alias']);
    });

    test('in a merge each server keeps its own order', () async {
      MediaItem plex(String title, int? at) =>
          PlexMediaItem(id: title, kind: MediaKind.show, title: title, lastViewedAt: at, serverId: 'p');
      final titles = await _merge({
        _library('p', MediaBackend.plex): [plex('P9', 9), plex('P5', 5), plex('PNone', null)],
        _library('j', MediaBackend.jellyfin): [jellyfinSeries('Zebra'), jellyfinSeries('Monk')],
      }, recentSeries);
      expect(titles.where((t) => t!.startsWith('P')), ['P9', 'P5', 'PNone']);
      expect(titles.where((t) => !t!.startsWith('P')), ['Zebra', 'Monk']);
      expect(titles.take(2), ['P9', 'P5']);
    });

    test('Pleya Server series run on episodes the show state does not carry', () async {
      MediaItem pleya(String title) =>
          MediaItem(id: title, backend: MediaBackend.pleyaServer, kind: MediaKind.show, title: title, serverId: 'x');
      final titles = await _merge({
        _library('x', MediaBackend.pleyaServer): [pleya('Zebra'), pleya('Monk'), pleya('Alias')],
      }, recentSeries);
      expect(titles, ['Zebra', 'Monk', 'Alias']);
    });

    test('Jellyfin films carry the date, so a leading gap is still held back', () async {
      MediaItem film(String title, int? at) =>
          JellyfinMediaItem(id: title, kind: MediaKind.movie, title: title, lastViewedAt: at, serverId: 'j');
      final titles = await _merge(
        {
          _library('j', MediaBackend.jellyfin): [film('None', null), film('Seen', 5)],
        },
        const UnifiedCatalogQuery(
          kind: MediaKind.movie,
          sortField: UnifiedCatalogSortField.recentlyWatched,
          sortDirection: LibrarySortDirection.descending,
        ),
      );
      expect(titles, ['Seen', 'None']);
    });

    test('a library with no value at all keeps the order it was sent in, whatever the field', () async {
      final titles = await _merge({
        _library('p', MediaBackend.plex): [_plex('Zebra', null), _plex('Monk', null), _plex('Alias', null)],
      }, _criticDown);
      expect(titles, ['Zebra', 'Monk', 'Alias']);
    });
  });

  group('two backends, one scale', () {
    test('Plex and Jellyfin interleave high to low across pages, nulls last', () async {
      final titles = await _merge({
        _library('p', MediaBackend.plex): [
          _plex('P96', 9.6),
          _plex('P80', 8.0),
          _plex('P40', 4.0),
          _plex('PNone', null),
        ],
        _library('j', MediaBackend.jellyfin): [
          _jellyfin('J91', 91),
          _jellyfin('J60', 60),
          _jellyfin('J10', 10),
          _jellyfin('JNone', null),
        ],
      }, _criticDown);
      expect(titles, ['P96', 'J91', 'P80', 'J60', 'P40', 'J10', 'JNone', 'PNone']);
    });

    test('one server sends nulls first, the other last: low to high, nulls last', () async {
      final titles = await _merge({
        _library('p', MediaBackend.plex): [
          _plex('PNoneA', null),
          _plex('PNoneB', null),
          _plex('PNoneC', null),
          _plex('P20', 2.0),
          _plex('P70', 7.0),
        ],
        _library('j', MediaBackend.jellyfin): [_jellyfin('J10', 10), _jellyfin('J50', 50), _jellyfin('JNone', null)],
      }, _criticUp);
      expect(titles, ['J10', 'P20', 'J50', 'P70', 'JNone', 'PNoneA', 'PNoneB', 'PNoneC']);
    });

    test('Jellyfin and Pleya Server merge on year without either dropping out', () async {
      MediaItem pleya(String title, int year) => MediaItem(
        id: title,
        backend: MediaBackend.pleyaServer,
        kind: MediaKind.movie,
        title: title,
        year: year,
        serverId: 'x',
      );
      MediaItem jelly(String title, int year) =>
          JellyfinMediaItem(id: title, kind: MediaKind.movie, title: title, year: year, serverId: 'j');
      final titles = await _merge(
        {
          _library('x', MediaBackend.pleyaServer): [pleya('X2024', 2024), pleya('X2001', 2001)],
          _library('j', MediaBackend.jellyfin): [jelly('J2020', 2020), jelly('J1999', 1999)],
        },
        const UnifiedCatalogQuery(
          kind: MediaKind.movie,
          sortField: UnifiedCatalogSortField.year,
          sortDirection: LibrarySortDirection.descending,
        ),
      );
      expect(titles, ['X2024', 'J2020', 'X2001', 'J1999']);
    });
  });

  group('page boundaries', () {
    test('a library that ran dry is refilled before the other runs ahead', () async {
      // Page size 2 with groups per page 3: without the refill, A's third item
      // lands behind B's whole buffer.
      final titles = await _merge(
        {
          _library('p', MediaBackend.plex): [_plex('A', 1), _plex('C', 1), _plex('E', 1), _plex('G', 1)],
          _library('q', MediaBackend.plex): [_plex('B', 1), _plex('D', 1), _plex('F', 1), _plex('H', 1)],
        },
        const UnifiedCatalogQuery(kind: MediaKind.movie),
        pageSize: 2,
        groupsPerPage: 8,
      );
      expect(titles, ['A', 'B', 'C', 'D', 'E', 'F', 'G', 'H']);
    });

    test('sorted on title the pages of 500 titles from two libraries stay in order', () async {
      String name(int i) => 'T${i.toString().padLeft(3, '0')}';
      final titles = await _merge(
        {
          _library('p', MediaBackend.plex): [for (var i = 0; i < 500; i += 2) _plex(name(i), null)],
          _library('q', MediaBackend.plex): [for (var i = 1; i < 500; i += 2) _plex(name(i), null)],
        },
        const UnifiedCatalogQuery(kind: MediaKind.movie),
        pageSize: 50,
        groupsPerPage: 20,
      );
      expect(titles, [for (var i = 0; i < 500; i++) name(i)]);
    });
  });
}
