import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/services/plex_epg_client.dart';

http.Response json(Map<String, dynamic> body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: {'content-type': 'application/json'});

FavoriteChannel channel(String id, {String source = 'server://machine-1/tv.plex.provider.epg'}) =>
    FavoriteChannel(source: source, id: id, title: 'Channel $id', vcn: '1');

void main() {
  group('reading', () {
    test('asks the EPG host for the favorite channel settings', () async {
      late http.BaseRequest sent;
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request;
          return json({
            'MediaContainer': {'size': 0},
          });
        }),
      );
      addTearDown(client.dispose);

      await client.fetchFavoriteChannels(token: 'tok');

      expect(sent.method, 'GET');
      expect(sent.url.host, 'epg.provider.plex.tv');
      expect(sent.url.path, '/settings/favoriteChannels');
    });

    test('sends the four canonical headers plus the provider version, and nothing else', () async {
      late http.BaseRequest sent;
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request;
          return json({
            'MediaContainer': {'size': 0},
          });
        }),
        clientIdentifier: 'client-id',
      );
      addTearDown(client.dispose);

      await client.fetchFavoriteChannels(token: 'account-token');

      final keys = sent.headers.keys.map((k) => k.toLowerCase()).toSet()..remove('content-type');
      expect(keys, {'accept', 'x-plex-product', 'x-plex-client-identifier', 'x-plex-token', 'x-plex-provider-version'});
      expect(sent.headers['X-Plex-Provider-Version'], '5.1');
      expect(sent.headers['X-Plex-Token'], 'account-token');
    });

    test('a container without FavoriteChannel is an empty list, not a failure', () async {
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient(
          (_) async => json({
            'MediaContainer': {'size': 0},
          }),
        ),
      );
      addTearDown(client.dispose);

      expect(await client.fetchFavoriteChannels(token: 'tok'), isEmpty);
    });

    test('parses the entries it does get', () async {
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient(
          (_) async => json({
            'MediaContainer': {
              'size': 2,
              'FavoriteChannel': [
                {'source': 'server://m/p', 'id': '1', 'title': 'One', 'vcn': '101'},
                {'source': 'server://m/p', 'id': '2', 'title': 'Two'},
              ],
            },
          }),
        ),
      );
      addTearDown(client.dispose);

      final channels = await client.fetchFavoriteChannels(token: 'tok');

      expect(channels.map((c) => c.id), ['1', '2']);
      expect(channels.first.title, 'One');
      expect(channels.first.vcn, '101');
      expect(channels.first.stableKey, favoriteChannelKey('server://m/p', '1'));
    });
  });

  group('writing', () {
    test('PUTs the whole list, in the order it was given', () async {
      late http.Request sent;
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request;
          return json({
            'MediaContainer': {'size': 0},
          });
        }),
      );
      addTearDown(client.dispose);

      await client.setFavoriteChannels(token: 'tok', channels: [channel('b'), channel('a')]);

      expect(sent.method, 'PUT');
      expect(sent.url.host, 'epg.provider.plex.tv');
      // The order is the user's own, straight out of the reorder sheet. It must
      // not be sorted or deduplicated on the way out.
      expect(jsonDecode(sent.body), [
        {'source': 'server://machine-1/tv.plex.provider.epg', 'id': 'b', 'title': 'Channel b', 'vcn': '1'},
        {'source': 'server://machine-1/tv.plex.provider.epg', 'id': 'a', 'title': 'Channel a', 'vcn': '1'},
      ]);
    });

    test('an empty list is a legitimate write', () async {
      late http.Request sent;
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request;
          return json({
            'MediaContainer': {'size': 0},
          });
        }),
      );
      addTearDown(client.dispose);

      await client.setFavoriteChannels(token: 'tok', channels: const []);

      expect(jsonDecode(sent.body), isEmpty);
    });
  });

  group('errors', () {
    test('400 surfaces the server wording instead of disappearing', () async {
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient(
          (_) async => json({
            'Error': {'error': 'Bad Request', 'message': 'Bad source value: server://x/y', 'statusCode': 400},
          }, status: 400),
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.setFavoriteChannels(token: 'tok', channels: [channel('a')]),
        throwsA(isA<PlexEpgRejected>().having((e) => e.message, 'message', contains('Bad source value'))),
      );
    });

    for (final status in [401, 403]) {
      test('$status throws with its own status code, after exactly one request', () async {
        var calls = 0;
        final client = PlexEpgClient.forTesting(
          httpClient: MockClient((_) async {
            calls++;
            return json({
              'Error': {'error': 'Unauthorized', 'message': 'You must provide a token!', 'statusCode': status},
            }, status: status);
          }),
        );
        addTearDown(client.dispose);

        await expectLater(
          client.fetchFavoriteChannels(token: 'stale'),
          throwsA(isA<PlexEpgUnauthorized>().having((e) => e.statusCode, 'statusCode', status)),
        );
        // No retry and no second token: falling back to another credential is
        // exactly the bug this whole boundary exists to prevent.
        expect(calls, 1);
      });
    }

    test('a write that is refused throws too, so the caller cannot assume it landed', () async {
      final client = PlexEpgClient.forTesting(
        httpClient: MockClient(
          (_) async => json({
            'Error': {'message': 'nope'},
          }, status: 403),
        ),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.setFavoriteChannels(token: 'tok', channels: const []),
        throwsA(isA<PlexEpgUnauthorized>().having((e) => e.statusCode, 'statusCode', 403)),
      );
    });

    test('any other failure keeps its transport type', () async {
      final client = PlexEpgClient.forTesting(httpClient: MockClient((_) async => http.Response('boom', 503)));
      addTearDown(client.dispose);

      await expectLater(client.fetchFavoriteChannels(token: 'tok'), throwsA(isA<MediaServerHttpException>()));
    });
  });
}
