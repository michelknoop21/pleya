import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/identity_lookup_exceptions.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/media/media_role.dart';
import 'package:pleya/media/media_version.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/local_library/local_library_store.dart';
import 'package:pleya/services/local_library/local_library_sync.dart';
import 'package:pleya/utils/media_server_http_client.dart';
import 'package:pleya/utils/external_ids.dart';
import '../../pleya_server/pleya_fake_server.dart';
import 'local_library_store_test.dart' show library, film;

class Client implements MediaServerClient {
  List<MediaItem> rows = [film('a'), film('b')];
  int? failOffset;
  Completer<void>? gate;
  final entered = Completer<void>();
  bool repeat = false;
  bool childrenFail = false;
  Object? idsError;
  int idLookups = 0;
  int rootPages = 0;

  /// What a detail or children call waits for before it answers, and the most
  /// of those calls ever open at once. A root task has at most one call open.
  Future<void> Function(String id)? pacer;
  int open = 0;
  int maxOpen = 0;
  final Set<String> childrenFailFor = {};
  Future<void> pace(String id) async {
    final wait = pacer?.call(id);
    if (wait == null) return;
    open++;
    if (open > maxOpen) maxOpen = open;
    await wait;
    open--;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    await pace(parentId);
    if (childrenFail || childrenFailFor.contains(parentId)) throw StateError('Unverified child page');
    childrenAsked.add(parentId);
    final rows = childRows[parentId] ?? const <MediaItem>[];
    return LibraryPage(
      items: rows.skip(start ?? 0).take(size ?? rows.length).toList(),
      totalCount: rows.length,
      offset: start ?? 0,
    );
  }

  @override
  ServerId get serverId => ServerId('one');
  @override
  bool get isOfflineMode => false;
  @override
  Future<ExternalIds> fetchExternalIds(String id) async {
    idLookups++;
    final error = idsError;
    if (error != null) throw error;
    return const ExternalIds();
  }

  final Map<String, List<MediaItem>> childRows = {};
  final List<String> childrenAsked = [];
  final Map<String, Object> itemErrors = {};
  // Ids whose detail call answers null, the way Pleya Server and Jellyfin
  // report a failed call.
  final Set<String> itemNull = {};
  final List<String> itemsAsked = [];
  @override
  Future<MediaItem?> fetchItem(String id) async {
    await pace(id);
    itemsAsked.add(id);
    final error = itemErrors[id];
    if (error != null) throw error;
    if (itemNull.contains(id)) return null;
    return [...rows, for (final c in childRows.values) ...c].where((i) => i.id == id).firstOrNull;
  }

  @override
  Future<LibraryPage<MediaItem>> fetchLibraryPagedContent(
    String libraryId, {
    required LibraryQuery query,
    MediaKind? libraryKind,
    AbortController? abort,
  }) async {
    if (!entered.isCompleted) entered.complete();
    rootPages++;
    await gate?.future;
    if (query.offset == failOffset) throw const SocketException('fixture offline');
    final start = repeat ? 0 : query.offset;
    return LibraryPage(
      items: rows.skip(start).take(query.limit).toList(),
      totalCount: rows.length,
      offset: query.offset,
    );
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

void main() {
  late Directory root;
  late LocalLibraryStore store;
  late Client client;
  setUp(() async {
    root = await Directory.systemTemp.createTemp('pleya-library-sync-test-');
    store = LocalLibraryStore(root);
    await store.load();
    client = Client();
  });
  tearDown(() async => root.delete(recursive: true));

  test('unverified children preserve descendants; confirmed empty children remove them', () async {
    final shows = library.copyWith(kind: MediaKind.show);
    final show = film('show').copyWith(kind: MediaKind.show);
    final episode = film('ep').copyWith(kind: MediaKind.episode, parentId: 'season', grandparentId: 'show');
    await store.saveLibrary(shows, [show, episode], complete: true);
    client.rows = [show];
    client.childrenFail = true;
    await expectLater(LocalLibrarySync(store: store).syncLibrary(shows, client), throwsStateError);
    expect(store.items.map((i) => i.id), contains('ep'));
    client.childrenFail = false;
    await LocalLibrarySync(store: store).syncLibrary(shows, client);
    expect(store.items.map((i) => i.id), ['show']);
  });

  test('a show and season that fit one page are listed once, without a second request to recheck them', () async {
    final shows = library.copyWith(kind: MediaKind.show);
    final show = film('show').copyWith(kind: MediaKind.show);
    final season = film('season').copyWith(kind: MediaKind.season, parentId: 'show');
    client.rows = [show];
    client.childRows['show'] = [season];
    client.childRows['season'] = [
      film('ep').copyWith(kind: MediaKind.episode, parentId: 'season', grandparentId: 'show'),
    ];

    await LocalLibrarySync(store: store).syncLibrary(shows, client);

    expect(client.childrenAsked, ['show', 'season']);
    expect(store.items.map((i) => i.id).toSet(), {'show', 'season', 'ep'});
  });

  test('a scan reads no detail for seasons and episodes on any backend', () async {
    final shows = library.copyWith(kind: MediaKind.show);
    final show = film('show').copyWith(kind: MediaKind.show);
    client.rows = [show];
    client.childRows['show'] = [film('season').copyWith(kind: MediaKind.season, parentId: 'show')];
    client.childRows['season'] = [
      film('ep').copyWith(
        kind: MediaKind.episode,
        parentId: 'season',
        grandparentId: 'show',
        roles: const [MediaRole(tag: 'Actor')],
        mediaVersions: const [MediaVersion(id: 'v1')],
      ),
    ];

    await LocalLibrarySync(store: store).syncLibrary(shows, client);

    expect(client.itemsAsked, ['show']);
    final rows = {for (final i in store.items) i.id: i};
    expect(rows.keys.toSet(), {'show', 'season', 'ep'});
    expect(rows['ep']?.roles, isNull, reason: 'the index stores an episode as a list row');
    expect(rows['ep']?.mediaVersions, isNull);
    expect(store.isComplete(shows.globalKey), isTrue);
  });

  test('a rescan shrinks an episode row stored with cast and versions', () async {
    final shows = library.copyWith(kind: MediaKind.show);
    final show = film('show').copyWith(kind: MediaKind.show, updatedAt: 1);
    final ep = film('ep').copyWith(kind: MediaKind.episode, parentId: 'show', updatedAt: 1);
    await store.saveLibrary(shows, [
      show,
      ep.copyWith(
        roles: const [MediaRole(tag: 'Actor')],
        mediaVersions: const [MediaVersion(id: 'v1')],
      ),
    ], complete: true);
    client.rows = [show];
    client.childRows['show'] = [ep];

    await LocalLibrarySync(store: store).syncLibrary(shows, client);

    final stored = store.items.firstWhere((i) => i.id == 'ep');
    expect(stored.roles, isNull);
    expect(stored.mediaVersions, isNull);
  });

  test('scanstats count exactly the requests the server answered', () async {
    final shows = library.copyWith(kind: MediaKind.show);
    MediaItem row(String id, MediaKind kind, [String? parent]) =>
        film(id).copyWith(kind: kind, parentId: parent, thumbPath: '/poster/$id');
    client.rows = [row('s1', MediaKind.show), row('s2', MediaKind.show)];
    client.childRows['s1'] = [row('season', MediaKind.season, 's1')];
    client.childRows['season'] = [row('e1', MediaKind.episode, 'season'), row('e2', MediaKind.episode, 'season')];
    var posters = 0;
    final sync = LocalLibrarySync(
      store: store,
      pageSize: 1,
      posterLoader: (_, _) async {
        posters++;
        return Uint8List(1);
      },
    );

    await sync.syncLibrary(shows, client);

    final stats = sync.stats;
    expect(
      [stats.root, stats.children, stats.detail, stats.extIds, stats.posters],
      [client.rootPages, client.childrenAsked.length, client.itemsAsked.length, client.idLookups, posters],
    );
    // Root and the season: two pages plus the head recheck each; s1 and s2 one
    // page each; a detail for the two shows only, and posters for the shows and
    // the season, not for the episode stills.
    expect([stats.root, stats.children, stats.detail, stats.posters], [3, 5, 2, 3]);
  });

  test('a failed Plex id lookup does not fail the scan: the row is kept without ids', () async {
    client.idsError = MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 502);

    await LocalLibrarySync(store: store).syncLibrary(library, client);

    expect(store.items.map((i) => i.id), ['a', 'b']);
  });

  test('a Pleya Server lookup that did not answer does not fail the scan, and stores no final answer', () async {
    client.idsError = const IdentityLookupUnavailable('503');

    await LocalLibrarySync(store: store).syncLibrary(library, client);

    expect(store.items.map((i) => i.id), ['a', 'b']);
  });

  group('against a Pleya Server', () {
    Future<Map<String, Map<String, Object?>?>> scan({required bool reportsExternalIds}) async {
      final fake = PleyaFakeServer()..reportsExternalIds = reportsExternalIds;
      fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
      fake.addItem(
        id: 'matched',
        kind: 'show',
        title: 'A',
        libraryId: 'lib-series',
        year: 2020,
        externalIds: {'tmdb': 5},
      );
      fake.addItem(id: 'unmatched', kind: 'show', title: 'B', libraryId: 'lib-series', year: 2021);
      final pleya = fake.client();
      addTearDown(pleya.close);
      await pleya.refreshCapabilities();
      const pleyaLibrary = MediaLibrary(
        id: 'lib-series',
        backend: MediaBackend.pleyaServer,
        title: 'Series',
        kind: MediaKind.show,
        serverId: 'srv-1',
      );
      await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, pleya);
      return {for (final i in store.items) i.id: i.raw};
    }

    Future<(PleyaFakeServer, Future<Map<String, Map<String, Object?>?>> Function())> live({
      required bool reportsExternalIds,
    }) async {
      final fake = PleyaFakeServer()..reportsExternalIds = reportsExternalIds;
      fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
      fake.addItem(id: 'later', kind: 'show', title: 'C', libraryId: 'lib-series', year: 2022);
      final pleya = fake.client();
      addTearDown(pleya.close);
      await pleya.refreshCapabilities();
      const pleyaLibrary = MediaLibrary(
        id: 'lib-series',
        backend: MediaBackend.pleyaServer,
        title: 'Series',
        kind: MediaKind.show,
        serverId: 'srv-1',
      );
      Future<Map<String, Map<String, Object?>?>> rescan() async {
        await pleya.refreshCapabilities();
        pleya.debugForgetExternalIds();
        await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, pleya);
        return {for (final i in store.items) i.id: i.raw};
      }

      return (fake, rescan);
    }

    test('a final empty answer does not hide a match the server makes later: the next scan picks it up', () async {
      final (fake, rescan) = await live(reportsExternalIds: true);
      expect((await rescan())['later']?['pleyaLocalExternalIds'], isEmpty);

      fake.items['later']!['external_ids'] = {'tmdb': 42};

      final after = await rescan();
      expect(after['later']?['pleyaLocalExternalIds'], {'tmdb': 42});
      expect(after['later']?['pleyaLocalExternalIdsFinal'], isTrue);
    });

    test('a server upgrade turns a non-final answer into a final one on the next scan', () async {
      final (fake, rescan) = await live(reportsExternalIds: false);
      expect((await rescan())['later']?['pleyaLocalExternalIdsFinal'], isNot(isTrue));

      // The upgraded server sends the key and the capability.
      fake.reportsExternalIds = true;
      fake.items['later']!['external_ids'] = {'tmdb': 42};

      final after = await rescan();
      expect(after['later']?['pleyaLocalExternalIds'], {'tmdb': 42});
      expect(after['later']?['pleyaLocalExternalIdsFinal'], isTrue);
    });

    test('a server that knows the field stores final answers, also an empty one', () async {
      final raw = await scan(reportsExternalIds: true);

      expect(raw['matched']?['pleyaLocalExternalIds'], {'tmdb': 5});
      expect(raw['matched']?['pleyaLocalExternalIdsFinal'], isTrue);
      expect(raw['unmatched']?['pleyaLocalExternalIds'], isEmpty);
      expect(raw['unmatched']?['pleyaLocalExternalIdsFinal'], isTrue, reason: 'no refetch on every screen build');
    });

    test(
      'a second scan replaces a non-final stored answer with a final one (the Pleya mapper sets no updatedAt, so the row is never retained; the guard in the sync only covers a future updatedAt)',
      () async {
        final fake = PleyaFakeServer();
        fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
        fake.addItem(
          id: 'matched',
          kind: 'show',
          title: 'A',
          libraryId: 'lib-series',
          year: 2020,
          externalIds: {'tmdb': 5},
        );
        final pleya = fake.client();
        addTearDown(pleya.close);
        await pleya.refreshCapabilities();
        const pleyaLibrary = MediaLibrary(
          id: 'lib-series',
          backend: MediaBackend.pleyaServer,
          title: 'Series',
          kind: MediaKind.show,
          serverId: 'srv-1',
        );
        await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, pleya);
        final first = store.items.single;
        // An older build stored an empty, non-final answer for this unchanged row.
        await store.saveLibrary(pleyaLibrary, [
          first.copyWith(raw: {'pleyaLocalExternalIds': <String, Object?>{}, 'pleyaLocalExternalIdsFinal': false}),
        ], complete: true);

        await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, pleya);

        expect(store.items.single.raw?['pleyaLocalExternalIds'], {'tmdb': 5});
        expect(store.items.single.raw?['pleyaLocalExternalIdsFinal'], isTrue);
      },
    );

    test('a Pleya title whose children fail keeps the stored snapshot, and the next scan completes', () async {
      final (fake, rescan) = await live(reportsExternalIds: true);
      expect((await rescan()).keys, ['later']);
      final key = store.libraries.single.globalKey;
      fake.addItem(id: 'other', kind: 'show', title: 'D', libraryId: 'lib-series', year: 2023);
      fake.queueFailure(pathPrefix: '/items/later/children', status: 500, errorCode: 'server.internal');

      // Pleya Server reads no detail per title, so a failing server shows up on
      // the children page, and a page that did not arrive is never an empty one.
      await expectLater(rescan(), throwsA(isA<StateError>()));

      expect(store.items.map((i) => i.id), ['later'], reason: 'a failed scan saves nothing over the snapshot');
      expect(store.isComplete(key), isTrue);
      expect((await rescan()).keys.toSet(), {'later', 'other'});
    });

    test('a Pleya rescan asks no detail per title: the list row is the detail row', () async {
      final fake = PleyaFakeServer();
      fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
      fake.addItem(id: 'show', kind: 'show', title: 'Show', libraryId: 'lib-series', year: 2020);
      fake.addItem(id: 'season', kind: 'season', title: 'Season 1', parentId: 'show', index: 1);
      fake.addItem(id: 'episode', kind: 'episode', title: 'Pilot', parentId: 'season', index: 1);
      final pleya = fake.client();
      addTearDown(pleya.close);
      await pleya.refreshCapabilities();
      const pleyaLibrary = MediaLibrary(
        id: 'lib-series',
        backend: MediaBackend.pleyaServer,
        title: 'Series',
        kind: MediaKind.show,
        serverId: 'srv-1',
      );
      await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, pleya);
      fake.items['episode']!['title'] = 'Pilot, renamed';
      fake.requests.clear();
      // A new session: nothing read before is held in memory.
      final next = fake.client();
      addTearDown(next.close);
      await next.refreshCapabilities();

      await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, next);

      final detailIds = [
        for (final r in fake.requests)
          if (RegExp(r'/items/([^/?]+)$').firstMatch(r.split('?').first) case final m?) m.group(1),
      ];
      expect(detailIds, isEmpty, reason: 'the list pages carry the ancestor names; never a read per title');
      final rows = {for (final i in store.items) i.id: i};
      expect(rows.keys.toSet(), {'show', 'season', 'episode'});
      expect(rows['episode']?.title, 'Pilot, renamed', reason: 'the fresh list row wins over the stored one');
      expect(rows['episode']?.grandparentTitle, 'Show');
      expect(rows['episode']?.parentTitle, 'Season 1');
    });

    test('a first Pleya scan asks no detail per title: the list row is the detail row', () async {
      final fake = PleyaFakeServer();
      fake.addLibrary(id: 'lib-series', title: 'Series', kind: 'shows');
      fake.addItem(id: 'show', kind: 'show', title: 'Show', libraryId: 'lib-series', year: 2020);
      fake.addItem(id: 'season', kind: 'season', title: 'Season 1', parentId: 'show', index: 1);
      fake.addItem(id: 'episode', kind: 'episode', title: 'Pilot', parentId: 'season', index: 1);
      final pleya = fake.client();
      addTearDown(pleya.close);
      await pleya.refreshCapabilities();
      const pleyaLibrary = MediaLibrary(
        id: 'lib-series',
        backend: MediaBackend.pleyaServer,
        title: 'Series',
        kind: MediaKind.show,
        serverId: 'srv-1',
      );
      fake.requests.clear();

      // Empty store: every title is new on this scan.
      await LocalLibrarySync(store: store).syncLibrary(pleyaLibrary, pleya);

      final detailIds = [
        for (final r in fake.requests)
          if (RegExp(r'/items/([^/?]+)$').firstMatch(r.split('?').first) case final m?) m.group(1),
      ];
      expect(detailIds, isEmpty, reason: 'the list pages carry the ancestor names; never a read per title');
      final rows = {for (final i in store.items) i.id: i};
      expect(rows.keys.toSet(), {'show', 'season', 'episode'});
      expect(rows['episode']?.grandparentTitle, 'Show');
      expect(rows['episode']?.parentTitle, 'Season 1');
      expect(rows['show']?.raw?['pleyaLocalExternalIds'], isNotNull);
      expect(store.isComplete(pleyaLibrary.globalKey), isTrue);
    });

    test('a server that predates the field stores nothing final', () async {
      final raw = await scan(reportsExternalIds: false);

      expect(raw['unmatched']?['pleyaLocalExternalIdsFinal'], isFalse);
    });
  });

  test('rescan cost: a list answer that carried the numbers needs no lookup per title, one without does', () async {
    client.rows = [
      for (final id in ['a', 'b'])
        film(id).copyWith(
          raw: {
            'Guid': [
              {'id': 'tmdb://${id.codeUnitAt(0)}'},
            ],
          },
        ),
    ];
    await LocalLibrarySync(store: store).syncLibrary(library, client);
    expect(client.idLookups, 0);
    expect(store.items.map((i) => i.raw?['pleyaLocalExternalIds']), [
      {'tmdb': 97},
      {'tmdb': 98},
    ]);

    client
      ..rows = [film('a'), film('b')]
      ..idLookups = 0;
    await LocalLibrarySync(store: store).syncLibrary(library, client);
    expect(client.idLookups, 2, reason: 'no carried numbers: one lookup per title, as before');
  });

  test('a retained row takes the numbers the fresh list answer carries, instead of its old stored answer', () async {
    // A Plex row with the same updatedAt is kept as it was. When the server
    // has matched the title since, the list answer carries the number; the
    // old stored "no numbers" must not win over it.
    const stamp = 1759276800;
    client.rows = [film('a').copyWith(updatedAt: stamp)];
    await LocalLibrarySync(store: store).syncLibrary(library, client);
    expect(store.items.single.raw?['pleyaLocalExternalIds'], isNot(containsPair('tmdb', anything)));

    client.rows = [
      film('a').copyWith(
        updatedAt: stamp,
        raw: {
          'Guid': [
            {'id': 'tmdb://603'},
          ],
        },
      ),
    ];
    await LocalLibrarySync(store: store).syncLibrary(library, client);
    expect(store.items.single.raw?['pleyaLocalExternalIds'], containsPair('tmdb', 603));
  });

  test('a timed out lookup does not fail the scan', () async {
    client.idsError = TimeoutException('slow');

    await LocalLibrarySync(store: store).syncLibrary(library, client);

    expect(store.items.map((i) => i.id), ['a', 'b']);
    expect(
      store.items.every((i) => i.raw?['pleyaLocalExternalIds'] == null),
      isTrue,
      reason: 'nothing stored as final',
    );
  });

  test('a title whose detail times out keeps its stored row, with fresh watch state, and the scan completes', () async {
    final stored = film('b').copyWith(summary: 'stored detail', viewOffsetMs: 100);
    await store.saveLibrary(library, [film('a'), stored], complete: true);
    client.rows = [film('a'), film('b').copyWith(viewCount: 1, viewOffsetMs: 5000)];
    client.itemErrors['b'] = TimeoutException('slow');

    await LocalLibrarySync(store: store).syncLibrary(library, client);

    expect(store.items.map((i) => i.id), ['a', 'b']);
    final b = store.items.firstWhere((i) => i.id == 'b');
    expect(b.summary, 'stored detail');
    expect((b.viewCount, b.viewOffsetMs), (1, 5000), reason: 'the list answer carries the current watch state');
    expect(store.isComplete(library.globalKey), isTrue);
  });

  final partialScan = throwsA(isA<LocalLibraryPartialScan>().having((e) => e.skipped, 'skipped', 1));

  test('on a first scan a failing title is left for the next scan, which leaves the library incomplete', () async {
    client.itemErrors['b'] = MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 500);

    await expectLater(LocalLibrarySync(store: store).syncLibrary(library, client), partialScan);

    expect(store.items.map((i) => i.id), ['a']);
    expect(store.isComplete(library.globalKey), isFalse, reason: 'the catalog keeps reading the server');

    client.itemErrors.clear();
    await LocalLibrarySync(store: store).syncLibrary(library, client);
    expect(store.items.map((i) => i.id), ['a', 'b']);
    expect(store.isComplete(library.globalKey), isTrue);
  });

  test('a detail call that answers null counts as a failed call, not as a failed scan', () async {
    await store.saveLibrary(library, [film('a').copyWith(summary: 'stored a')], complete: true);
    client.itemNull.addAll({'a', 'b'});

    await expectLater(LocalLibrarySync(store: store).syncLibrary(library, client), partialScan);

    expect(store.items.map((i) => i.id), ['a'], reason: 'a keeps its row, b is left for the next scan');
    expect(store.items.single.summary, 'stored a');
  });

  test('a complete library with a skipped new title still drops what the server deleted, and stays complete', () async {
    await store.saveLibrary(library, [film('a'), film('gone')], complete: true);
    client.itemErrors['b'] = TimeoutException('slow');

    await expectLater(LocalLibrarySync(store: store).syncLibrary(library, client), partialScan);

    expect(store.items.map((i) => i.id), ['a'], reason: 'the enumeration proved gone is gone');
    expect(store.isComplete(library.globalKey), isTrue);
    expect(store.lastScan(library.globalKey), isNotNull, reason: 'the attempt counts for the rescan window');
  });

  group('a show whose detail fails', () {
    final shows = library.copyWith(kind: MediaKind.show);
    final show = film('show').copyWith(kind: MediaKind.show);
    final season = film('season').copyWith(kind: MediaKind.season, parentId: 'show');
    setUp(() {
      client.rows = [show];
      client.childRows['show'] = [season];
      client.itemErrors['show'] = TimeoutException('slow');
    });

    test('on a first scan stores none of its seasons or episodes', () async {
      await expectLater(LocalLibrarySync(store: store).syncLibrary(shows, client), partialScan);

      expect(store.items, isEmpty);
      expect(client.childrenAsked, isEmpty);
    });

    test('with a stored row still scans its children', () async {
      await store.saveLibrary(shows, [show], complete: true);

      await LocalLibrarySync(store: store).syncLibrary(shows, client);

      expect(store.items.map((i) => i.id), ['show', 'season']);
      expect(client.childrenAsked.toSet(), {'show', 'season'});
    });
  });

  test('an unexpected StateError still fails the scan: only lookup failures are tolerated', () async {
    client.idsError = StateError('programming error');

    await expectLater(LocalLibrarySync(store: store).syncLibrary(library, client), throwsStateError);
  });

  test('successful complete scan removes confirmed missing rows', () async {
    await store.saveLibrary(library, [film('removed')], complete: true);
    await LocalLibrarySync(store: store, pageSize: 1).syncLibrary(library, client);
    expect(store.items.map((i) => i.id), ['a', 'b']);
  });

  test('a checkpoint waits for its interval, however many rows have passed', () async {
    var checkpoints = 0;
    await LocalLibrarySync(
      store: store,
      pageSize: 1,
      checkpointEvery: const Duration(hours: 1),
      onCheckpoint: () => checkpoints++,
    ).syncLibrary(library, client);

    expect(checkpoints, 0);
    expect(store.items.map((i) => i.id), ['a', 'b']);
  });

  test('a scan that has been running past the interval saves its rows before it fails', () async {
    client.failOffset = 1;
    await expectLater(
      LocalLibrarySync(store: store, pageSize: 1, checkpointEvery: Duration.zero).syncLibrary(library, client),
      throwsA(isA<SocketException>()),
    );

    expect(store.items.map((i) => i.id), ['a']);
  });

  test('failed next page never deletes the previous snapshot', () async {
    await store.saveLibrary(library, [film('old')], complete: true);
    client.failOffset = 1;
    await expectLater(
      LocalLibrarySync(store: store, pageSize: 1).syncLibrary(library, client),
      throwsA(isA<SocketException>()),
    );
    expect(store.items.map((i) => i.id), contains('old'));
  });

  test('cancelled response cannot recreate a cleared library', () async {
    client.gate = Completer<void>();
    var current = true;
    final pending = LocalLibrarySync(store: store).syncLibrary(library, client, isCurrent: () => current);
    await client.entered.future;
    final checked = expectLater(pending, throwsA(isA<LocalLibraryPaused>()));
    current = false;
    await store.clear();
    client.gate!.complete();
    await checked;
    expect(store.items, isEmpty);
  });

  test('server ignoring pagination is an error rather than a successful partial scan', () async {
    await store.saveLibrary(library, [film('old')], complete: true);
    client.repeat = true;
    await expectLater(
      LocalLibrarySync(store: store, pageSize: 1).syncLibrary(library, client),
      throwsA(isA<StateError>()),
    );
    expect(store.items.map((i) => i.id), contains('old'));
  });

  test('low storage pauses before fetching and preserves cached rows', () async {
    await store.saveLibrary(library, [film('old')], complete: true);
    await expectLater(
      LocalLibrarySync(store: store, mayContinue: () async => false).syncLibrary(library, client),
      throwsA(isA<LocalLibraryPaused>()),
    );
    expect(store.items.single.id, 'old');
  });

  group('root titles scanned in parallel', () {
    final shows = library.copyWith(kind: MediaKind.show);
    MediaItem show(int i) => film('s$i').copyWith(kind: MediaKind.show);

    /// [count] shows of [seasons] seasons of [episodes] episodes each; show i
    /// answers slower the lower its number, so later shows finish first.
    void addShows(int count, {int seasons = 1, int episodes = 4}) {
      client.rows = [for (var i = 0; i < count; i++) show(i)];
      for (var i = 0; i < count; i++) {
        final seasonRows = [
          for (var j = 0; j < seasons; j++) film('s$i-x$j').copyWith(kind: MediaKind.season, parentId: 's$i'),
        ];
        if (seasons == 0) {
          client.childRows['s$i'] = [
            for (var k = 0; k < episodes; k++) film('s$i-e$k').copyWith(kind: MediaKind.episode, parentId: 's$i'),
          ];
          continue;
        }
        client.childRows['s$i'] = seasonRows;
        for (final season in seasonRows) {
          client.childRows[season.id] = [
            for (var k = 0; k < episodes; k++)
              film('${season.id}-e$k').copyWith(kind: MediaKind.episode, parentId: season.id, grandparentId: 's$i'),
          ];
        }
      }
      int number(String id) => int.parse(RegExp(r'^s(\d+)').firstMatch(id)!.group(1)!);
      client.pacer = (id) => Future<void>.delayed(Duration(milliseconds: (count - number(id)) % 4));
    }

    test('stores the rows in the same order with one task as with four', () async {
      addShows(7, seasons: 2, episodes: 4);
      await LocalLibrarySync(store: store, pageSize: 3, rootConcurrency: 1).syncLibrary(shows, client);
      final sequential = store.items.map((i) => i.id).toList();
      await store.clear();

      await LocalLibrarySync(store: store, pageSize: 3, rootConcurrency: 4).syncLibrary(shows, client);

      expect(sequential, hasLength(7 + 14 + 56));
      expect(store.items.map((i) => i.id).toList(), sequential);
    });

    test('never has more than four root tasks in flight', () async {
      addShows(12, seasons: 1, episodes: 3);

      await LocalLibrarySync(store: store).syncLibrary(shows, client);

      expect(client.maxOpen, 4, reason: 'four at once, and the pool is actually used');
      expect(store.items, hasLength(12 * 5));
    });

    test('nested scans of four root tasks save one checkpoint per window', () async {
      addShows(4, seasons: 0, episodes: 4);
      client.pacer = null;
      final saved = <int>[];
      final counting = _CountingStore(root, saved);
      await counting.load();

      await LocalLibrarySync(store: counting, pageSize: 4, checkpointEvery: Duration.zero).syncLibrary(shows, client);

      expect(saved, isNotEmpty);
      for (var i = 1; i < saved.length; i++) {
        expect(saved[i] - saved[i - 1], greaterThanOrEqualTo(4), reason: 'checkpoints $saved');
      }
    });

    test('a failing task fails the scan, keeps the previous snapshot and leaves nothing running', () async {
      await store.saveLibrary(shows, [film('old')], complete: true);
      addShows(8, seasons: 1, episodes: 2);
      client.childrenFailFor.add('s0');
      // s1 to s3 wait until a timer runs, which is after the failure of s0 has
      // reached the pool through microtasks.
      final hold = Completer<void>();
      client.pacer = (id) {
        if (id.startsWith('s0')) return Future.value();
        Timer.run(() => hold.isCompleted ? null : hold.complete());
        return hold.future;
      };

      await expectLater(LocalLibrarySync(store: store).syncLibrary(shows, client), throwsStateError);
      final asked = [...client.itemsAsked, ...client.childrenAsked];
      await Future<void>.delayed(const Duration(milliseconds: 20));

      expect(store.items.map((i) => i.id), ['old']);
      expect(store.isComplete(shows.globalKey), isTrue);
      expect(client.childrenAsked, containsAll(['s1-x0', 's2-x0', 's3-x0']), reason: 'running tasks finish their show');
      expect(asked, isNot(contains('s4')), reason: 'no new title starts after the failure');
      expect([...client.itemsAsked, ...client.childrenAsked], asked, reason: 'no task outlives the scan');
    });

    test('a pause after a checkpoint keeps the rows of the tasks still in flight', () async {
      addShows(4, seasons: 0, episodes: 4);
      var allowed = true;

      await expectLater(
        LocalLibrarySync(
          store: store,
          pageSize: 4,
          checkpointEvery: Duration.zero,
          mayContinue: () async => allowed,
          onCheckpoint: () => allowed = false,
        ).syncLibrary(shows, client),
        throwsA(isA<LocalLibraryPaused>()),
      );

      // No root page finished, so every stored row came from a buffer in flight.
      final ids = store.items.map((i) => i.id).toSet();
      expect(ids.where((id) => ids.containsAll(['$id-e0', '$id-e3'])), isNotEmpty, reason: 'stored: $ids');
    });
  });
}

class _CountingStore extends LocalLibraryStore {
  _CountingStore(super.directory, this.saved);
  final List<int> saved;
  @override
  Future<void> saveLibrary(
    MediaLibrary library,
    List<MediaItem> items, {
    required bool complete,
    bool partial = false,
    bool Function()? isCurrent,
  }) {
    if (!complete && !partial) saved.add(items.length);
    return super.saveLibrary(library, items, complete: complete, partial: partial, isCurrent: isCurrent);
  }
}
