import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/exceptions/identity_lookup_exceptions.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/library_query.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
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
  @override
  Future<LibraryPage<MediaItem>> fetchChildrenPage(
    String parentId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async {
    if (childrenFail) throw StateError('Unverified child page');
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
  @override
  Future<MediaItem?> fetchItem(String id) async {
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

    test('one title whose detail call fails does not fail the scan (Pleya answers such a call with null)', () async {
      final (fake, rescan) = await live(reportsExternalIds: true);
      fake.addItem(id: 'other', kind: 'show', title: 'D', libraryId: 'lib-series', year: 2023);
      fake.queueFailure(pathPrefix: '/items/later', status: 500, errorCode: 'server.internal');

      final first = await rescan();

      expect(first.keys, ['other']);
      expect(fake.requests.where((r) => r.contains('/items/later/children')), isEmpty);
      expect(store.isComplete(store.libraries.single.globalKey), isFalse);
      expect((await rescan()).keys.toSet(), {'later', 'other'});
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

  test('on a first scan a failing title is left for the next scan, which leaves the library incomplete', () async {
    client.itemErrors['b'] = MediaServerHttpException(type: MediaServerHttpErrorType.unknown, statusCode: 500);

    await LocalLibrarySync(store: store).syncLibrary(library, client);

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

    await LocalLibrarySync(store: store).syncLibrary(library, client);

    expect(store.items.map((i) => i.id), ['a'], reason: 'a keeps its row, b is left for the next scan');
    expect(store.items.single.summary, 'stored a');
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
      await LocalLibrarySync(store: store).syncLibrary(shows, client);

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
}
