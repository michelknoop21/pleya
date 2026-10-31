/// A copy gets its state without a viewing: on the wire that means no
/// `/Sessions/Playing`, no `/:/timeline`, and only what the write is about
/// (hoofdstuk 13.2 of docs/tvos-unified-experience.md).
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/database/download_operations.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/offline_watch_sync_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/utils/watch_state_notifier.dart';
import 'package:pleya/models/plex/plex_config.dart';

JellyfinConnection _connection({bool isEmby = false}) => JellyfinConnection(
  id: 'srv-1/user-1',
  baseUrl: 'https://jf.example.com',
  serverName: 'Home',
  serverMachineId: 'srv-1',
  userId: 'user-1',
  userName: 'edde',
  accessToken: 'tok-abc',
  deviceId: 'dev-xyz',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  isEmby: isEmby,
);

MediaItem _film(MediaBackend backend) =>
    MediaItem(id: 'film', backend: backend, kind: MediaKind.movie, title: 'Sintel', serverId: 'srv-1');

void main() {
  http.Response ok(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

  group('Jellyfin', () {
    test('a position goes to UserData and carries nothing else', () async {
      final requests = <http.Request>[];
      final client = JellyfinClient.forTesting(
        connection: _connection(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return ok({'Key': 'k'});
        }),
      );
      addTearDown(client.close);

      await client.writeCopyState(
        _film(MediaBackend.jellyfin),
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 90),
        watched: false,
      );

      expect(requests.single.method, 'POST');
      expect(requests.single.url.path, '/UserItems/film/UserData');
      expect(requests.single.url.queryParameters['userId'], 'user-1');
      expect(jsonDecode(requests.single.body), {'PlaybackPositionTicks': 3000000000});
    });

    test('a finished viewing is a mark', () async {
      final requests = <http.Request>[];
      final client = JellyfinClient.forTesting(
        connection: _connection(),
        httpClient: MockClient((request) async {
          requests.add(request);
          return ok({});
        }),
      );
      addTearDown(client.close);

      await client.writeCopyState(
        _film(MediaBackend.jellyfin),
        position: const Duration(minutes: 90),
        duration: const Duration(minutes: 90),
        watched: true,
      );

      expect(requests.single.url.path, '/UserPlayedItems/film');
    });

    test('a server that does not know the route says so', () async {
      final client = JellyfinClient.forTesting(
        connection: _connection(),
        httpClient: MockClient((request) async => http.Response('', 404)),
      );
      addTearDown(client.close);

      await expectLater(
        client.writeCopyState(_film(MediaBackend.jellyfin), position: const Duration(minutes: 5), watched: false),
        throwsA(anything),
      );
    });
  });

  group('reading a copy', () {
    setUp(() {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);
    });

    JellyfinClient jellyfin(http.Response Function() answer) {
      final client = JellyfinClient.forTesting(
        connection: _connection(),
        httpClient: MockClient((_) async => answer()),
      );
      addTearDown(client.close);
      return client;
    }

    test('Jellyfin: a 404 is gone', () async {
      expect(await jellyfin(() => http.Response('', 404)).readCopyState('film'), isNull);
    });

    test('Jellyfin: a server error is no answer', () async {
      await expectLater(jellyfin(() => http.Response('', 503)).readCopyState('film'), throwsA(anything));
    });

    test('Jellyfin: a page that is no item is no answer', () async {
      await expectLater(jellyfin(() => http.Response('<html>', 200)).readCopyState('film'), throwsA(anything));
    });

    test('Jellyfin: offline is no answer', () async {
      final client = jellyfin(() => http.Response('', 404))..setOfflineMode(true);

      await expectLater(client.readCopyState('film'), throwsStateError);
    });

    PlexClient plexAnswering(http.Response Function() answer) {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://pms.example.com',
          token: 'tok',
          clientIdentifier: 'client',
          product: 'Pleya',
          version: 'test',
        ),
        serverId: ServerId('srv-1'),
        httpClient: MockClient((_) async => answer()),
      );
      addTearDown(client.close);
      return client;
    }

    test('Plex: a 404 is gone', () async {
      expect(await plexAnswering(() => http.Response('', 404)).readCopyState('film'), isNull);
    });

    test('Plex: a server error is no answer', () async {
      await expectLater(plexAnswering(() => http.Response('', 503)).readCopyState('film'), throwsA(anything));
    });

    test('Plex: offline is no answer', () async {
      final client = plexAnswering(() => http.Response('', 404))..setOfflineMode(true);

      await expectLater(client.readCopyState('film'), throwsStateError);
    });
  });

  group('Emby', () {
    test('gets its own user data back with a new position', () async {
      final requests = <http.Request>[];
      const stored = {'Played': true, 'PlayCount': 3, 'IsFavorite': true, 'LastPlayedDate': '2026-01-01T00:00:00Z'};
      final client = JellyfinClient.forTesting(
        connection: _connection(isEmby: true),
        httpClient: MockClient((request) async {
          requests.add(request);
          return request.method == 'GET'
              ? ok({
                  'UserData': {...stored, 'PlaybackPositionTicks': 0},
                })
              : ok({});
        }),
      );
      addTearDown(client.close);

      await client.writeCopyState(_film(MediaBackend.jellyfin), position: const Duration(minutes: 5), watched: false);

      expect(requests.first.url.path, '/Users/user-1/Items/film');
      expect(requests.last.url.path, '/Users/user-1/Items/film/UserData');
      expect(jsonDecode(requests.last.body), {...stored, 'PlaybackPositionTicks': 3000000000});
    });

    test('writes nothing when it cannot read what stands there', () async {
      var writes = 0;
      final client = JellyfinClient.forTesting(
        connection: _connection(isEmby: true),
        httpClient: MockClient((request) async {
          if (request.method == 'POST') writes++;
          return ok({'Id': 'film'});
        }),
      );
      addTearDown(client.close);

      await expectLater(
        client.writeCopyState(_film(MediaBackend.jellyfin), position: const Duration(minutes: 5), watched: false),
        throwsStateError,
      );
      expect(writes, 0);
    });
  });

  group('Plex', () {
    setUp(() {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);
    });

    PlexClient plex(List<Uri> urls) => PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://pms.example.com',
        token: 'tok',
        clientIdentifier: 'client',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('srv-1'),
      httpClient: MockClient((request) async {
        urls.add(request.url);
        return http.Response('', 200);
      }),
    );

    test('a position goes to /:/progress, not to the timeline of a viewing', () async {
      final urls = <Uri>[];
      final client = plex(urls);
      addTearDown(client.close);

      await client.writeCopyState(
        _film(MediaBackend.plex),
        position: const Duration(minutes: 5),
        duration: const Duration(minutes: 90),
        watched: false,
      );

      expect(urls.single.path, '/:/progress');
      expect(urls.single.queryParameters, {
        'key': 'film',
        'identifier': 'com.plexapp.plugins.library',
        'time': '300000',
        'state': 'stopped',
      });
    });

    test('a finished viewing is a scrobble', () async {
      final urls = <Uri>[];
      final client = plex(urls);
      addTearDown(client.close);

      await client.writeCopyState(_film(MediaBackend.plex), position: Duration.zero, watched: true);

      expect(urls.single.path, '/:/scrobble');
    });
  });

  group('a read through the queue', () {
    late AppDatabase db;
    late MultiServerManager manager;
    late OfflineWatchSyncService queue;

    setUp(() {
      db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      manager = MultiServerManager();
      queue = OfflineWatchSyncService(database: db, serverManager: manager);
    });

    tearDown(() async {
      queue.dispose();
      manager.dispose();
      await db.close();
    });

    void plexAnswering(http.Response Function(http.Request request) answer) {
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://pms.example.com',
          token: 'tok',
          clientIdentifier: 'client',
          product: 'Pleya',
          version: 'test',
        ),
        serverId: ServerId('srv-1'),
        httpClient: MockClient((request) async => answer(request)),
      );
      addTearDown(client.close);
      manager
        ..debugMarkAdministeredForTesting(client.serverId)
        ..debugRegisterClientForTesting(client);
    }

    void jellyfinAnswering(http.Response Function(http.Request request) answer, {bool isEmby = false}) {
      final client = JellyfinClient.forTesting(
        connection: _connection(isEmby: isEmby),
        httpClient: MockClient((request) async => answer(request)),
      );
      addTearDown(client.close);
      manager
        ..debugMarkAdministeredForTesting(client.serverId)
        ..debugRegisterJellyfinClientForTesting(client);
    }

    Future<void> row({bool watched = true}) => queue.queueMirroredProgress(
      serverId: ServerId('srv-1'),
      itemId: 'film',
      viewOffset: 1800000,
      duration: 7200000,
      watched: watched,
      profileId: queue.activeProfileId,
    );

    final backends = <String, void Function(http.Response Function(http.Request) answer)>{
      'Plex': plexAnswering,
      'Jellyfin': jellyfinAnswering,
      'Emby': (answer) => jellyfinAnswering(answer, isEmby: true),
    };

    for (final MapEntry(key: name, value: connect) in backends.entries) {
      for (final status in const [400, 401, 403, 410, 429, 503]) {
        test('$name: a $status says nothing about the copy, so the row stays', () async {
          connect((_) => http.Response('nope', status));
          await row();

          await queue.syncPendingItems();

          expect((await db.getLatestWatchAction('srv-1:film'))?.syncAttempts, 1);
        });
      }

      test('$name: a 404 ends the row', () async {
        connect((_) => http.Response('', 404));
        await row();

        await queue.syncPendingItems();

        expect(await db.getLatestWatchAction('srv-1:film'), isNull);
      });
    }

    test('Jellyfin: a 200 without an item keeps the row', () async {
      jellyfinAnswering((_) => ok({'error': 'maintenance'}));
      await row();

      await queue.syncPendingItems();

      expect((await db.getLatestWatchAction('srv-1:film'))?.syncAttempts, 1);
    });

    test('Plex: a 200 without an item keeps the row', () async {
      plexAnswering(
        (_) => ok({
          'MediaContainer': {'size': 0},
        }),
      );
      await row();

      await queue.syncPendingItems();

      expect((await db.getLatestWatchAction('srv-1:film'))?.syncAttempts, 1);
    });

    test('Plex: a pull reports a film that changed since the last pull, once', () async {
      var viewCount = 0;
      plexAnswering(
        (_) => ok({
          'MediaContainer': {
            'Metadata': [
              {'ratingKey': 'film', 'type': 'movie', 'title': 'Sintel', 'duration': 7200000, 'viewCount': viewCount},
            ],
          },
        }),
      );
      await db.insertDownload(
        serverId: ServerId('srv-1'),
        ratingKey: 'film',
        globalKey: 'srv-1:film',
        type: 'movie',
        status: 3,
      );
      await db.addDownloadOwner(profileId: 'p', globalKey: 'srv-1:film');
      queue.setActiveProfileId('p');
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);

      await queue.syncWatchStatesFromServer();
      viewCount = 1;
      await queue.syncWatchStatesFromServer();
      await queue.syncWatchStatesFromServer();
      await pumpEventQueue();

      expect(events.where((e) => e.changeType == WatchStateChangeType.watched), hasLength(1));
    });

    test('Plex: the copy reports itself as a copy, on its own server', () async {
      plexAnswering(
        (request) => request.url.path.startsWith('/library/metadata')
            ? ok({
                'MediaContainer': {
                  'Metadata': [
                    {'ratingKey': 'film', 'type': 'movie', 'title': 'Sintel', 'duration': 7200000, 'viewCount': 0},
                  ],
                },
              })
            : ok({}),
      );
      final events = <WatchStateEvent>[];
      final subscription = WatchStateNotifier().stream.listen(events.add);
      addTearDown(subscription.cancel);
      await row();

      await queue.syncPendingItems();
      await pumpEventQueue();

      final copy = events.singleWhere((e) => e.changeType == WatchStateChangeType.watched);
      expect(copy.globalKey, 'srv-1:film');
      expect(copy.isCopy, isTrue);
    });
  });
}
