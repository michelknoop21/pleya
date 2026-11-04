import 'dart:convert';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/watchlist_key.dart';
import 'package:pleya/services/watchlist/watchlist_repository.dart';
import 'package:pleya/services/watchlist/watchlist_source_factory.dart';
import 'package:pleya/services/watchlist_actions.dart';
import 'package:pleya/services/pleya_server_client.dart';

import '../pleya_server/pleya_fake_server.dart';

void main() {
  test('production favorites can add, reload and remove a title without an external identity', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    server.addItem(id: 'm', kind: 'movie', title: 'Same title');
    final client = PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.srv-1.user-1',
        baseUrl: 'http://nas.lan:8832',
        serverId: 'srv-1',
        serverName: 'Test',
        userName: 'michel',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026),
      ),
      httpClientFactory: server.asHttpClient,
    );
    addTearDown(client.close);
    await client.refreshCapabilities();
    final factory = WatchlistSourceFactory(
      profileId: 'p1',
      resolvePlexAuth: () async => null,
      clientIdentifier: 'test',
      clientsById: () => {'srv-1': client},
      verifyWatchlist: false,
    );
    addTearDown(factory.dispose);
    final sources = await factory.build();
    expect(sources, hasLength(1));
    expect(sources.single.scope.userId, 'user-1');
    final item = (await client.fetchItem('m'))!;
    final repository = WatchlistRepository(sources: sources);
    expect(await WatchlistActions.add(repository: repository, item: item, isOffline: false), WatchlistOutcome.added);
    final fetched = await repository.fetch();
    expect(fetched.complete, isTrue);
    expect(fetched.entries, hasLength(1));
    expect(fetched.entries.single.key, watchlistKeyForItem(item));
    expect(fetched.entries.single.lastKnownMatch?.id, 'm');
    expect(
      await WatchlistActions.remove(sources: sources, entry: fetched.entries.single, isOffline: false),
      WatchlistOutcome.removed,
    );
    expect((await repository.fetch()).entries, isEmpty);
    expect(server.requests.where((p) => p.contains('/verify/')), isEmpty);
  });

  test('identity-free favorites from different servers never merge by title or item id', () {
    final a = MediaItem(
      id: 'same',
      backend: MediaBackend.pleyaServer,
      kind: MediaKind.movie,
      title: 'Same',
      serverId: ServerId('a'),
    );
    final b = a.copyWith(serverId: ServerId('b'));
    expect(watchlistKeyForItem(a), isNotNull);
    expect(watchlistKeyForItem(a), isNot(watchlistKeyForItem(b)));
  });

  test('a retained source cannot write to another account after rebinding', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    PleyaServerClient account(String user) => PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.srv-1.$user',
        baseUrl: 'http://nas.lan:8832',
        serverId: 'srv-1',
        serverName: 'Test',
        userName: 'same display name',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026),
      ),
      httpClientFactory: server.asHttpClient,
    );
    final first = account('u1');
    final second = account('u2');
    addTearDown(first.close);
    addTearDown(second.close);
    await first.refreshCapabilities();
    await second.refreshCapabilities();
    final clients = <String, MediaServerClient>{'srv-1': first};
    final factory = WatchlistSourceFactory(
      profileId: 'p1',
      resolvePlexAuth: () async => null,
      clientIdentifier: 'test',
      clientsById: () => clients,
      verifyWatchlist: false,
    );
    addTearDown(factory.dispose);
    final old = (await factory.build()).single;
    clients['srv-1'] = second;
    final item = MediaItem(id: 'm', backend: MediaBackend.pleyaServer, kind: MediaKind.movie, serverId: 'srv-1');
    await expectLater(old.add(item), throwsA(anything));
    expect(server.favoriteIds, isEmpty);
    expect((await factory.build()).single.scope.userId, 'u2');
  });

  test('an underestimated count cannot truncate a complete favorites fetch', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    for (var n = 0; n < 101; n++) {
      server.addItem(id: 'm$n', kind: 'movie', title: 'Movie $n');
      server.favoriteIds.add('m$n');
    }
    final client = PleyaServerClient.create(
      PleyaServerConnection(
        id: 'pleyaServer.srv-1.u1',
        baseUrl: 'http://nas.lan:8832',
        serverId: 'srv-1',
        serverName: 'Test',
        userName: 'one',
        refreshToken: 'rt-1',
        createdAt: DateTime.utc(2026),
      ),
      httpClientFactory: () => MockClient((request) async {
        final response = await server.handle(request);
        if (!request.url.path.endsWith('/favorites')) return response;
        final page = jsonDecode(response.body) as Map<String, dynamic>;
        page['total_estimate'] = 100;
        return http.Response(jsonEncode(page), 200, headers: {'content-type': 'application/json'});
      }),
    );
    addTearDown(client.close);
    await client.refreshCapabilities();
    final factory = WatchlistSourceFactory(
      profileId: 'p1',
      resolvePlexAuth: () async => null,
      clientIdentifier: 'test',
      clientsById: () => {'srv-1': client},
      verifyWatchlist: false,
    );
    addTearDown(factory.dispose);
    final result = await WatchlistRepository(sources: await factory.build()).fetch();
    expect(result.complete, isTrue);
    expect(result.entries, hasLength(101));
  });

  test('legacy account identity and old server do not create a production source', () async {
    final server = PleyaFakeServer()..personalCapability = true;
    final client = server.client();
    addTearDown(client.close);
    await client.refreshCapabilities();
    final factory = WatchlistSourceFactory(
      profileId: 'p1',
      resolvePlexAuth: () async => null,
      clientIdentifier: 'test',
      clientsById: () => <String, MediaServerClient>{'srv-1': client},
      verifyWatchlist: false,
    );
    addTearDown(factory.dispose);
    expect(await factory.build(), isEmpty);
  });
}
