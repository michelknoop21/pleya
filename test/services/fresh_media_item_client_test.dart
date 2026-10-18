import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/jellyfin_api_cache.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/pleya_server_api_cache.dart';

import '../pleya_server/pleya_fake_server.dart';

const _cachedPosition = 10 * 60 * 1000;
const _serverPosition = 45 * 60 * 1000;

enum _ServerKind { plex, jellyfin, emby }

void main() {
  for (final kind in _ServerKind.values) {
    group('${kind.name} fresh item reads', () {
      test('a transport failure cannot make a fresh read return cached metadata', () async {
        final server = _ItemServer(kind);
        final client = _clientFor(server);
        expect(client, isA<FreshMediaItemClient>());

        // Seed the real in-memory ApiCache through the real mapper/write path.
        expect((await client.fetchItem('movie_1'))?.viewOffsetMs, _cachedPosition);
        server.failTransport = true;
        final connectionError = throwsA(
          isA<MediaServerHttpException>().having(
            (error) => error.type,
            'type',
            MediaServerHttpErrorType.connectionError,
          ),
        );
        if (kind == _ServerKind.plex) {
          expect((await client.fetchItem('movie_1'))?.viewOffsetMs, _cachedPosition);
        } else {
          // The HTTP layer wraps ClientException; Jellyfin/Emby's existing
          // typed-error branch propagates it even with a cached item present.
          await expectLater(client.fetchItem('movie_1'), connectionError);
        }
        final callsBeforeFresh = server.requests.length;

        final freshClient = client as FreshMediaItemClient;
        await expectLater(freshClient.fetchFreshItem('movie_1'), connectionError);
        expect(server.requests.length, greaterThan(callsBeforeFresh), reason: 'the fresh read attempted the network');
        client.setOfflineMode(true);
        expect(
          (await client.fetchItem('movie_1'))?.viewOffsetMs,
          _cachedPosition,
          reason: 'the cached answer still exists',
        );
      });

      test('a fresh read replaces a cached position with the server position without lastViewedAt', () async {
        final server = _ItemServer(kind);
        final client = _clientFor(server);
        expect((await client.fetchItem('movie_1'))?.viewOffsetMs, _cachedPosition);
        server.positionMs = _serverPosition;
        final callsBeforeFresh = server.requests.length;

        final fresh = await (client as FreshMediaItemClient).fetchFreshItem('movie_1');

        expect(fresh, isNotNull);
        expect(fresh!.id, 'movie_1');
        expect(fresh.backend, server.backend);
        expect(fresh.viewOffsetMs, _serverPosition);
        expect(fresh.lastViewedAt, isNull);
        expect(server.requests.length, greaterThan(callsBeforeFresh));
      });

      test('offline mode returns no fresh result and makes no HTTP call even with a cached item', () async {
        final server = _ItemServer(kind);
        final client = _clientFor(server);
        expect((await client.fetchItem('movie_1'))?.viewOffsetMs, _cachedPosition);
        client.setOfflineMode(true);
        final callsBeforeFresh = server.requests.length;

        expect(await (client as FreshMediaItemClient).fetchFreshItem('movie_1'), isNull);
        expect(server.requests, hasLength(callsBeforeFresh));
        expect((await client.fetchItem('movie_1'))?.viewOffsetMs, _cachedPosition);
        expect(server.requests, hasLength(callsBeforeFresh), reason: 'ordinary offline reads still use the cache');
      });
    });
  }

  test('Pleya Server fresh reads use the network and never answer from cache during offline mode or failure', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PleyaServerApiCache.initialize(db);
    addTearDown(db.close);
    final server = PleyaFakeServer(watchState: true);
    final state = <String, dynamic>{
      'position_ms': _cachedPosition,
      'watched': false,
      'play_count': 0,
      'updated_at': '2026-10-18T10:00:00Z',
    };
    final cachedItem = server.addItem(
      id: 'movie_1',
      kind: 'movie',
      title: 'Movie 1',
      durationMs: 2 * 60 * 60 * 1000,
      userState: state,
    );
    final client = server.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final cacheScope = ServerId(client.scopedServerId);
    await client.cache.put(cacheScope, PleyaServerApiCache.itemEndpoint('movie_1'), cachedItem);
    expect((await client.cache.getMetadata(cacheScope, 'movie_1'))?.viewOffsetMs, _cachedPosition);
    server.items['movie_1'] = {
      ...cachedItem,
      'user_state': {...state, 'position_ms': _serverPosition},
    };

    final FreshMediaItemClient freshClient = client;
    final fresh = await freshClient.fetchFreshItem('movie_1');
    expect(fresh?.viewOffsetMs, _serverPosition);
    expect(fresh?.backend, MediaBackend.pleyaServer);
    expect(server.requests, contains('/pleya/v1/items/movie_1'));

    client.setOfflineMode(true);
    final callsBeforeOffline = server.requests.length;
    expect(await freshClient.fetchFreshItem('movie_1'), isNull);
    expect(server.requests, hasLength(callsBeforeOffline));

    client.setOfflineMode(false);
    server.unreachable = true;
    expect(await freshClient.fetchFreshItem('movie_1'), isNull);
    expect((await client.cache.getMetadata(cacheScope, 'movie_1'))?.viewOffsetMs, _cachedPosition);
  });
}

MediaServerClient _clientFor(_ItemServer server) {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  addTearDown(db.close);
  final MediaServerClient client;
  if (server.backend == MediaBackend.plex) {
    PlexApiCache.initialize(db);
    client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.test',
        token: 'test-token',
        clientIdentifier: 'test-client',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('server_1'),
      httpClient: server.httpClient,
    );
  } else {
    JellyfinApiCache.initialize(db);
    client = JellyfinClient.forTesting(
      connection: JellyfinConnection(
        id: 'server_1/user_1',
        baseUrl: 'https://jellyfin.example.test',
        serverName: 'Server',
        serverMachineId: 'server_1',
        userId: 'user_1',
        userName: 'Test viewer',
        accessToken: 'test-token',
        deviceId: 'test-client',
        isEmby: server.kind == _ServerKind.emby,
        createdAt: DateTime.utc(2026, 10, 18),
      ),
      httpClient: server.httpClient,
    );
  }
  if (server.kind == _ServerKind.emby) addTearDown(() => embyServerIds.remove('server_1'));
  addTearDown(client.close);
  return client;
}

class _ItemServer {
  _ItemServer(this.kind);

  final _ServerKind kind;
  MediaBackend get backend => kind == _ServerKind.plex ? MediaBackend.plex : MediaBackend.jellyfin;
  int positionMs = _cachedPosition;
  bool failTransport = false;
  final requests = <Uri>[];
  late final httpClient = MockClient((request) async {
    requests.add(request.url);
    expect(
      request.url.path,
      backend == MediaBackend.plex ? '/library/metadata/movie_1' : '/Users/user_1/Items/movie_1',
    );
    if (failTransport) throw http.ClientException('synthetic transport failure', request.url);
    final body = backend == MediaBackend.plex
        ? {
            'MediaContainer': {
              'Metadata': [
                {
                  'ratingKey': 'movie_1',
                  'type': 'movie',
                  'title': 'Movie 1',
                  'duration': 2 * 60 * 60 * 1000,
                  'viewOffset': positionMs,
                },
              ],
            },
          }
        : {
            'Id': 'movie_1',
            'Type': 'Movie',
            'Name': 'Movie 1',
            'RunTimeTicks': 2 * 60 * 60 * 1000 * 10000,
            'UserData': {'PlaybackPositionTicks': positionMs * 10000, 'Played': false},
          };
    return http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});
  });
}
