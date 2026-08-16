import 'package:flutter_test/flutter_test.dart';
import 'package:http/testing.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/plex_watchlist_client.dart';
import 'package:pleya/services/watchlist/jellyfin_favorites_source.dart';
import 'package:pleya/services/watchlist/plex_account_watchlist_source.dart';
import 'package:pleya/services/watchlist/watchlist_source_factory.dart';

import 'fake_favorites_client.dart';

typedef PlexAuth = ({String token, String profileId, String accountId, String userId, bool isUserScoped});

PlexAuth auth({bool isUserScoped = true, String profileId = 'p1'}) =>
    (token: 't', profileId: profileId, accountId: 'acc', userId: 'usr', isUserScoped: isUserScoped);

WatchlistSourceFactory factoryWith({
  PlexAuth? plexAuth,
  bool noAuth = false,
  Map<String, MediaServerClient> clients = const {},
}) {
  return WatchlistSourceFactory(
    profileId: 'p1',
    resolvePlexAuth: () async => noAuth ? null : (plexAuth ?? auth()),
    clientIdentifier: 'client-1',
    clientsById: () => clients,
    plexClientBuilder: () =>
        PlexWatchlistClient.forTesting(httpClient: MockClient((_) async => throw StateError('no'))),
  );
}

void main() {
  test('builds a Plex source when the auth is user-scoped', () async {
    final sources = await factoryWith().build();

    expect(sources, hasLength(1));
    expect(sources.single, isA<PlexAccountWatchlistSource>());
    expect(sources.single.scope.backend, MediaBackend.plex);
    expect(sources.single.scope.accountId, 'acc');
    expect(sources.single.scope.userId, 'usr');
  });

  test('builds no Plex source while only the owner token is available', () async {
    expect(await factoryWith(plexAuth: auth(isUserScoped: false)).build(), isEmpty);
  });

  test('builds no Plex source on a Jellyfin-only setup', () async {
    expect(await factoryWith(noAuth: true).build(), isEmpty);
  });

  test('skips a client that is not a Jellyfin server', () async {
    final sources = await factoryWith(noAuth: true, clients: {'s1': FakeFavoritesClient(favorites: const [])}).build();

    expect(sources.whereType<JellyfinFavoritesSource>(), isEmpty);
  });

  test('the Plex source comes first, so its newest-first order survives the merge', () async {
    final sources = await factoryWith().build();

    expect(sources.first, isA<PlexAccountWatchlistSource>());
  });
}
