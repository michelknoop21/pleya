import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/watchlist_entry.dart';
import 'package:pleya/media/watchlist_scope.dart';
import 'package:pleya/media/watchlist_source.dart';
import 'package:pleya/services/plex_watchlist_client.dart';
import 'package:pleya/services/watchlist/jellyfin_favorites_source.dart';
import 'package:pleya/services/watchlist/plex_account_watchlist_source.dart';

import 'fake_favorites_client.dart';

String fixture(String name) => File('test/fixtures/watchlist/$name').readAsStringSync();

http.Response ok(String body) => http.Response(body, 200, headers: {'content-type': 'application/json'});

typedef PlexAuth = ({String token, String profileId, String accountId, String userId, bool isUserScoped});

PlexAuth auth({
  String token = 'user-token',
  String profileId = 'profile-1',
  String accountId = 'account-uuid',
  String userId = 'home-user-uuid',
  bool isUserScoped = true,
}) => (token: token, profileId: profileId, accountId: accountId, userId: userId, isUserScoped: isUserScoped);

final plexScope = WatchlistScopeId(
  profileId: 'profile-1',
  backend: MediaBackend.plex,
  accountId: 'account-uuid',
  userId: 'home-user-uuid',
);

PlexAccountWatchlistSource plexSource({
  required http.Client httpClient,
  PlexAuth? resolved,
  bool nullAuth = false,
}) {
  return PlexAccountWatchlistSource(
    client: PlexWatchlistClient.forTesting(httpClient: httpClient),
    resolveAuth: () async => nullAuth ? null : (resolved ?? auth()),
    scope: plexScope,
  );
}

MediaItem plexItem({String? guid = 'plex://movie/abc', MediaKind kind = MediaKind.movie}) =>
    MediaItem(id: '4711', backend: MediaBackend.plex, kind: kind, guid: guid, serverId: 'machine-1');

void main() {
  group('PlexAccountWatchlistSource scope check', () {
    test('refuses to fetch when the token is not user-scoped', () async {
      var requests = 0;
      final source = plexSource(
        httpClient: MockClient((_) async {
          requests++;
          return ok(fixture('watchlist_empty.json'));
        }),
        resolved: auth(isUserScoped: false),
      );

      await expectLater(source.fetch(), throwsA(isA<WatchlistScopeUnavailable>()));
      expect(requests, 0, reason: 'the owner fallback must never reach the network');
    });

    test('refuses to add or remove when the token is not user-scoped', () async {
      final source = plexSource(
        httpClient: MockClient((_) async => ok(fixture('action_success.json'))),
        resolved: auth(isUserScoped: false),
      );

      await expectLater(source.add(plexItem()), throwsA(isA<WatchlistScopeUnavailable>()));
      await expectLater(
        source.remove(WatchlistMembership(scope: plexScope, remoteKey: 'abc')),
        throwsA(isA<WatchlistScopeUnavailable>()),
      );
    });

    test('refuses when the active identity moved to another user', () async {
      final source = plexSource(
        httpClient: MockClient((_) async => ok(fixture('watchlist_empty.json'))),
        resolved: auth(userId: 'someone-else'),
      );

      await expectLater(source.fetch(), throwsA(isA<WatchlistScopeUnavailable>()));
    });

    test('refuses when another profile became active', () async {
      final source = plexSource(
        httpClient: MockClient((_) async => ok(fixture('watchlist_empty.json'))),
        resolved: auth(profileId: 'profile-2'),
      );

      await expectLater(source.fetch(), throwsA(isA<WatchlistScopeUnavailable>()));
    });

    test('refuses when there is no Plex account at all', () async {
      final source = plexSource(httpClient: MockClient((_) async => ok('{}')), nullAuth: true);

      await expectLater(source.fetch(), throwsA(isA<WatchlistScopeUnavailable>()));
    });

    test('asks again on every operation instead of trusting a resolved token', () async {
      var resolves = 0;
      final source = PlexAccountWatchlistSource(
        client: PlexWatchlistClient.forTesting(
          httpClient: MockClient((request) async {
            return ok(fixture(request.method == 'PUT' ? 'action_success.json' : 'watchlist_empty.json'));
          }),
        ),
        resolveAuth: () async {
          resolves++;
          return auth();
        },
        scope: plexScope,
      );

      await source.fetch();
      await source.add(plexItem());
      await source.remove(WatchlistMembership(scope: plexScope, remoteKey: 'abc'));

      expect(resolves, 3);
    });

    test('passes only the bare token on to the client', () async {
      late Map<String, String> headers;
      final source = plexSource(
        httpClient: MockClient((request) async {
          headers = request.headers;
          return ok(fixture('watchlist_empty.json'));
        }),
        resolved: auth(token: 'the-token'),
      );

      await source.fetch();

      expect(headers['X-Plex-Token'], 'the-token');
    });
  });

  group('PlexAccountWatchlistSource.resolveScope', () {
    test('builds a scope from user-scoped auth', () async {
      final scope = await PlexAccountWatchlistSource.resolveScope(
        resolveAuth: () async => auth(),
        profileId: 'profile-1',
      );

      expect(scope, plexScope);
    });

    test('answers null rather than a scope built on the owner fallback', () async {
      expect(
        await PlexAccountWatchlistSource.resolveScope(
          resolveAuth: () async => auth(isUserScoped: false),
          profileId: 'profile-1',
        ),
        isNull,
      );
      expect(
        await PlexAccountWatchlistSource.resolveScope(resolveAuth: () async => null, profileId: 'profile-1'),
        isNull,
      );
    });
  });

  group('PlexAccountWatchlistSource.accepts', () {
    final source = plexSource(httpClient: MockClient((_) async => ok('{}')));

    test('takes a Plex movie or show with a plex guid', () {
      expect(source.accepts(plexItem()), isTrue);
      expect(source.accepts(plexItem(kind: MediaKind.show)), isTrue);
    });

    test('refuses what the endpoint cannot address', () {
      expect(source.accepts(plexItem(guid: null)), isFalse);
      expect(source.accepts(plexItem(guid: 'com.plexapp.agents.imdb://tt1?lang=en')), isFalse);
      expect(source.accepts(plexItem(kind: MediaKind.episode)), isFalse);
      expect(source.accepts(MediaItem(id: 'x', backend: MediaBackend.jellyfin, kind: MediaKind.movie)), isFalse);
    });
  });

  group('PlexAccountWatchlistSource.fetch', () {
    test('turns the cloud list into entries with exactly one membership each', () async {
      final source = plexSource(
        httpClient: MockClient((request) async {
          final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
          return ok(fixture(start == 0 ? 'watchlist_page1.json' : 'watchlist_page2.json'));
        }),
      );

      final entries = await source.fetch();

      expect(entries, hasLength(3));
      for (final entry in entries) {
        expect(entry.memberships, hasLength(1));
        expect(entry.memberships.single.scope, plexScope);
        expect(entry.memberships.single.remoteKey, isNotEmpty);
        expect(entry.posterRef, startsWith('https://'));
      }
      expect(entries.map((e) => e.key), contains('plex:5d77688123d5a3001f4ed3df'));
    });

    test('keeps the order the server returned, because that is the added order', () async {
      final source = plexSource(
        httpClient: MockClient((request) async {
          final start = int.parse(request.url.queryParameters['X-Plex-Container-Start']!);
          return ok(fixture(start == 0 ? 'watchlist_page1.json' : 'watchlist_page2.json'));
        }),
      );

      final titles = (await source.fetch()).map((e) => e.item.title).toList();

      expect(titles, ['Sintel', 'Pioneer One', 'Big Buck Bunny']);
    });
  });

  group('JellyfinFavoritesSource', () {
    final jellyfinScope = WatchlistScopeId(
      profileId: 'profile-1',
      backend: MediaBackend.jellyfin,
      accountId: 'jf-machine',
      userId: 'jf-user',
    );

    JellyfinFavoritesSource sourceFor(FakeFavoritesClient client) =>
        JellyfinFavoritesSource(client: client, serverId: ServerId('jf-machine'), scope: jellyfinScope);

    MediaItem favorite(String id, {String? imdb, MediaKind kind = MediaKind.movie}) => MediaItem(
      id: id,
      backend: MediaBackend.jellyfin,
      kind: kind,
      title: 'Title $id',
      serverId: 'jf-machine',
      raw: imdb == null
          ? null
          : {
              'ProviderIds': {'Imdb': imdb},
            },
    );

    test('walks every page of favorites', () async {
      final client = FakeFavoritesClient(
        favorites: [
          favorite('a', imdb: 'tt1'),
          favorite('b', imdb: 'tt2'),
          favorite('c', imdb: 'tt3'),
        ],
        pageSize: 2,
      );

      final entries = await sourceFor(client).fetch();

      expect(entries, hasLength(3));
      expect(client.pagesServed, 2);
    });

    test('identifies favorites by their inline provider ids', () async {
      final client = FakeFavoritesClient(favorites: [favorite('a', imdb: 'tt0111161')]);

      expect((await sourceFor(client).fetch()).single.key, 'imdb:tt0111161');
    });

    test('drops a favorite with no cross-server identity', () async {
      final client = FakeFavoritesClient(favorites: [favorite('a')]);

      expect(await sourceFor(client).fetch(), isEmpty);
    });

    test('add and remove go through the per-user favorite flag', () async {
      final client = FakeFavoritesClient(favorites: []);
      final source = sourceFor(client);

      final membership = await source.add(favorite('a', imdb: 'tt1'));
      expect(membership.remoteKey, 'a');
      expect(client.setCalls, [('a', true)]);

      await source.remove(membership);
      expect(client.setCalls, [('a', true), ('a', false)]);
    });

    test('only accepts movies and shows from its own server', () {
      final source = sourceFor(FakeFavoritesClient(favorites: []));

      expect(source.accepts(favorite('a')), isTrue);
      expect(source.accepts(favorite('a', kind: MediaKind.show)), isTrue);
      expect(source.accepts(favorite('a', kind: MediaKind.episode)), isFalse);
      expect(
        source.accepts(
          MediaItem(id: 'a', backend: MediaBackend.jellyfin, kind: MediaKind.movie, serverId: 'other-machine'),
        ),
        isFalse,
      );
      expect(source.accepts(plexItem()), isFalse);
    });

    test('asks for movies and series only, never for favorited channels', () async {
      final client = FakeFavoritesClient(favorites: []);

      await sourceFor(client).fetch();

      expect(client.kindsRequested, [null]);
    });
  });
}
