/// One merge, one round at a time. A second `loadMore` beside a running one pops
/// past a cursor that is refilling, and grows the popped history under a round
/// that is still waiting for external ids.
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

class _Server implements MediaServerClient {
  _Server(this.items);

  final List<MediaItem> items;
  Completer<void>? pageGate;

  /// Holds back the first external-id lookup and no other.
  Completer<void>? idGate;
  int pages = 0;
  int idLookups = 0;

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    pages++;
    final gate = pageGate;
    if (gate != null) await gate.future;
    final ordered = query.sort?.direction == LibrarySortDirection.descending ? items.reversed.toList() : items;
    final end = (query.offset + query.limit).clamp(0, ordered.length);
    final slice = query.offset >= ordered.length ? const <MediaItem>[] : ordered.sublist(query.offset, end);
    return LibraryPage<MediaItem>(items: slice, totalCount: ordered.length, offset: query.offset);
  }

  @override
  Future<ExternalIds> fetchExternalIds(String itemId) async {
    if (idLookups++ == 0 && idGate != null) await idGate!.future;
    return const ExternalIds();
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

CatalogLibrary _library(String server) =>
    (serverId: ServerId(server), serverName: server, libraryId: 'lib', libraryTitle: 'lib', backend: MediaBackend.plex);

MediaItem _film(String title, String server) =>
    PlexMediaItem(id: '$server-$title', kind: MediaKind.movie, title: title, year: 2000, serverId: server);

/// The same titles on two servers, which is what sends the merge for ids.
List<MediaItem> _films(String server, int count) => [
  for (var i = 0; i < count; i++) _film('T${i.toString().padLeft(3, '0')}', server),
];

const _titleUp = UnifiedCatalogQuery(kind: MediaKind.movie);
const _titleDown = UnifiedCatalogQuery(kind: MediaKind.movie, sortDirection: LibrarySortDirection.descending);

List<String?> _titles(UnifiedCatalogService service) => [
  for (final group in service.snapshot.groups) group.representativeSource.item.title,
];

UnifiedCatalogService _service(Map<String, _Server> servers, {int pageSize = 50, int groupsPerPage = 3}) =>
    UnifiedCatalogService(
      query: _titleUp,
      libraries: [for (final id in servers.keys) _library(id)],
      clientFor: (id) => servers[id.value],
      pageSize: pageSize,
      groupsPerPage: groupsPerPage,
      progressiveLoadingGrace: const Duration(seconds: 5),
    );

void main() {
  test('a second call while one runs is that same round, not a second one', () async {
    final servers = {'p': _Server(_films('p', 30))};
    final service = _service(servers);

    final first = service.loadMore();
    final second = service.loadMore();
    expect(identical(first, second), isTrue);
    await Future.wait([first, second]);

    expect(_titles(service), ['T000', 'T001', 'T002']);
    expect(servers['p']!.pages, 1);
  });

  test('a round that ended leaves the way open for the next', () async {
    final service = _service({'p': _Server(_films('p', 30))});
    await service.loadMore();
    await service.loadMore();
    expect(_titles(service), hasLength(6));
  });

  test('a failed round leaves the way open too', () async {
    final server = _Server(_films('p', 30));
    final service = _service({'p': server});
    server.pageGate = Completer<void>()..completeError(StateError('offline'));
    await service.loadMore();
    server.pageGate = null;
    await service.loadMore();
    expect(_titles(service), ['T000', 'T001', 'T002']);
  });

  test('a second call cannot pop past a cursor that is refilling', () async {
    final slow = _Server([_film('A', 'x'), _film('C', 'x')])..pageGate = Completer<void>();
    final fast = _Server([_film('B', 'y'), _film('D', 'y')]);
    final service = _service({'x': slow, 'y': fast}, groupsPerPage: 4);

    final first = service.loadMore();
    final second = service.loadMore();
    await pumpEventQueue();
    slow.pageGate!.complete();
    await Future.wait([first, second]);

    expect(_titles(service), ['A', 'B', 'C', 'D']);
  });

  test('duplicate titles with ids on their way: a second call does not throw a RangeError', () async {
    final servers = {'p': _Server(_films('p', 30)), 'q': _Server(_films('q', 30))};
    servers['p']!.idGate = Completer<void>();
    final service = _service(servers);

    final first = service.loadMore();
    await pumpEventQueue();
    final second = service.loadMore();
    await pumpEventQueue();
    servers['p']!.idGate!.complete();

    await expectLater(Future.wait([first, second]), completes);
    expect(_titles(service).first, 'T000');
  });

  test('a round overtaken by a new query keeps its hands off the new history', () async {
    final servers = {'p': _Server(_films('p', 30)), 'q': _Server(_films('q', 30))};
    servers['p']!.idGate = Completer<void>();
    final service = _service(servers);
    final libraries = service.libraries;

    final old = service.loadMore();
    await pumpEventQueue();

    service.updateQuery(query: _titleDown, libraries: libraries);
    await service.loadMore();
    await service.loadMore();
    final settled = _titles(service);
    expect(settled.first, 'T029');

    servers['p']!.idGate!.complete();
    await expectLater(old, completes);
    expect(_titles(service), settled);
  });

  test('a new query does not wait for the round it replaced', () async {
    final gate = Completer<void>();
    final server = _Server(_films('p', 30))..pageGate = gate;
    final service = _service({'p': server});

    final old = service.loadMore();
    await pumpEventQueue();
    service.updateQuery(query: _titleDown, libraries: service.libraries);
    server.pageGate = null;
    await service.loadMore();
    expect(_titles(service).first, 'T029');

    gate.complete();
    await old;
    expect(_titles(service).first, 'T029');
  });
}
