import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/live_tv_support.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/services/livetv/plex_favorite_channels_service.dart';
import 'package:pleya/services/plex_account_auth.dart';
import 'package:pleya/services/plex_epg_client.dart';

PlexAccountAuth auth({
  String token = 'account-token',
  String profileId = 'profile-1',
  String accountId = 'account-1',
  String userId = 'user-1',
  bool isUserScoped = true,
}) => (token: token, profileId: profileId, accountId: accountId, userId: userId, isUserScoped: isUserScoped);

void main() {
  late List<http.BaseRequest> requests;

  /// Records every request, so a test can prove that nothing left the app.
  PlexEpgClient recordingClient({Map<String, dynamic>? body}) {
    return PlexEpgClient.forTesting(
      httpClient: MockClient((request) async {
        requests.add(request);
        return http.Response(
          jsonEncode(
            body ??
                {
                  'MediaContainer': {'size': 0},
                },
          ),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
  }

  PlexFavoriteChannelsService service({
    required PlexAccountAuthResolver resolveAuth,
    PlexEpgClient? client,
    String profileId = 'profile-1',
  }) {
    final epg = client ?? recordingClient();
    return PlexFavoriteChannelsService(
      profileId: profileId,
      resolveAuth: resolveAuth,
      clientIdentifier: () async => 'device-1',
      clientBuilder: (_) => epg,
    );
  }

  setUp(() => requests = []);

  group('no scope, no store, and above all no HTTP', () {
    test('a profile without a Plex account has no store', () async {
      final s = service(resolveAuth: () async => null);
      addTearDown(s.dispose);

      expect(await s.resolveStore(), isNull);
      expect(requests, isEmpty);
    });

    test('an unfinished Home-user binding has no store either', () async {
      final s = service(resolveAuth: () async => auth(isUserScoped: false));
      addTearDown(s.dispose);

      expect(await s.resolveStore(), isNull);
      expect(requests, isEmpty, reason: 'the owner token would work, and that is exactly why it must not be used');
    });

    test('auth for another profile is not this profile', () async {
      final s = service(resolveAuth: () async => auth(profileId: 'other-profile'));
      addTearDown(s.dispose);

      expect(await s.resolveStore(), isNull);
      expect(requests, isEmpty);
    });
  });

  group('store identity', () {
    test('the same user gets the same instance back', () async {
      final s = service(resolveAuth: () async => auth());
      addTearDown(s.dispose);

      final first = await s.resolveStore();
      final second = await s.resolveStore();

      expect(first, isNotNull);
      expect(identical(first, second), isTrue, reason: 'key equality and instance equality must agree');
    });

    test('another Home user gets a different instance', () async {
      var userId = 'user-1';
      final s = service(resolveAuth: () async => auth(userId: userId));
      addTearDown(s.dispose);

      final first = await s.resolveStore();
      userId = 'user-2';
      final second = await s.resolveStore();

      expect(identical(first, second), isFalse);
      expect(first!.favoriteStoreKey, isNot(second!.favoriteStoreKey));
    });

    test('the key carries account and user, not the device', () async {
      final s = service(
        resolveAuth: () async => auth(accountId: 'acc', userId: 'usr'),
      );
      addTearDown(s.dispose);

      final store = await s.resolveStore();

      expect(store!.favoriteStoreKey, 'plex-account:acc:usr');
      expect(store.favoriteStoreKey, isNot(contains('device-1')));
      expect(store.favoritePersistenceMode, FavoriteChannelPersistenceMode.sharedFullList);
    });

    test('hostile ids cannot collide, because every part is encoded on its own', () async {
      final a = service(
        resolveAuth: () async => auth(accountId: 'a', userId: 'b:c'),
      );
      final b = service(
        resolveAuth: () async => auth(accountId: 'a:b', userId: 'c'),
      );
      addTearDown(a.dispose);
      addTearDown(b.dispose);

      final left = await a.resolveStore();
      final right = await b.resolveStore();

      expect(left!.favoriteStoreKey, isNot(right!.favoriteStoreKey));
    });
  });

  group('operations', () {
    test('the account token goes on the wire, per operation', () async {
      var token = 'token-1';
      final client = recordingClient();
      final s = service(
        resolveAuth: () async => auth(token: token),
        client: client,
      );
      addTearDown(s.dispose);

      final store = await s.resolveStore();
      await store!.fetchFavoriteChannels();
      token = 'token-2';
      await store.setFavoriteChannels(const []);

      expect(requests.map((r) => r.headers['X-Plex-Token']), ['token-1', 'token-2']);
    });

    test('reading parses what the cloud returns', () async {
      final client = recordingClient(
        body: {
          'MediaContainer': {
            'size': 1,
            'FavoriteChannel': [
              {'source': 'server://m/p', 'id': '1', 'title': 'One'},
            ],
          },
        },
      );
      final s = service(resolveAuth: () async => auth(), client: client);
      addTearDown(s.dispose);

      final store = await s.resolveStore();

      expect((await store!.fetchFavoriteChannels()).single.id, '1');
    });

    test('identity drift stops both operations before any request', () async {
      var userId = 'user-1';
      final client = recordingClient();
      final s = service(
        resolveAuth: () async => auth(userId: userId),
        client: client,
      );
      addTearDown(s.dispose);

      final store = await s.resolveStore();
      userId = 'user-2';

      await expectLater(store!.fetchFavoriteChannels(), throwsA(isA<PlexFavoritesUnavailable>()));
      await expectLater(
        store.setFavoriteChannels([FavoriteChannel(source: 's', id: 'x')]),
        throwsA(isA<PlexFavoritesUnavailable>()),
      );
      expect(requests, isEmpty, reason: 'a store never slides over to another user');
    });

    test('losing scope mid-session stops the store too', () async {
      var scoped = true;
      final client = recordingClient();
      final s = service(
        resolveAuth: () async => auth(isUserScoped: scoped),
        client: client,
      );
      addTearDown(s.dispose);

      final store = await s.resolveStore();
      scoped = false;

      await expectLater(store!.fetchFavoriteChannels(), throwsA(isA<PlexFavoritesUnavailable>()));
      expect(requests, isEmpty);
    });

    test('a refused write throws and is not retried with another credential', () async {
      var calls = 0;
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient((request) async {
          calls++;
          requests.add(request);
          return http.Response('{"Error":{"message":"nope"}}', 401, headers: {'content-type': 'application/json'});
        }),
      );
      final s = service(resolveAuth: () async => auth(), client: client);
      addTearDown(s.dispose);

      final store = await s.resolveStore();

      await expectLater(store!.setFavoriteChannels(const []), throwsA(isA<PlexEpgUnauthorized>()));
      expect(calls, 1);
      expect(requests.map((r) => r.headers['X-Plex-Token']).toSet(), {'account-token'});
    });
  });
}
