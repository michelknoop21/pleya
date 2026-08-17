import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/exceptions/media_server_exceptions.dart';
import 'package:pleya/services/plex_cloud_http_client.dart';

http.Response ok([String body = '{}']) => http.Response(body, 200, headers: {'content-type': 'application/json'});

Set<String> headerKeys(http.BaseRequest request) =>
    request.headers.keys.map((key) => key.toLowerCase()).toSet()..remove('content-type');

void main() {
  group('the boundary itself', () {
    test('carries no base URL and no default headers, so nothing can ride along', () {
      final client = PlexCloudHttpClient.forTesting(httpClient: MockClient((_) async => ok()));
      addTearDown(client.dispose);

      expect(client.injectedBaseUrl, isEmpty);
      expect(client.injectedDefaultHeaders, isEmpty);
    });

    test('an absolute URL goes out unchanged, with the query appended', () async {
      late Uri url;
      final client = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((request) async {
          url = request.url;
          return ok();
        }),
      );
      addTearDown(client.dispose);

      await client.get(
        'https://epg.provider.plex.tv/settings/favoriteChannels',
        token: 'tok',
        queryParameters: {'a': '1'},
      );

      expect(url.host, 'epg.provider.plex.tv');
      expect(url.path, '/settings/favoriteChannels');
      expect(url.queryParameters['a'], '1');
    });
  });

  group('headers', () {
    test('a client without extras sends exactly the four canonical headers', () async {
      late http.BaseRequest sent;
      final client = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request;
          return ok();
        }),
        clientIdentifier: 'client-id',
      );
      addTearDown(client.dispose);

      await client.get('https://discover.provider.plex.tv/x', token: 'secret-token');

      expect(headerKeys(sent), {'accept', 'x-plex-product', 'x-plex-client-identifier', 'x-plex-token'});
      expect(sent.headers['X-Plex-Token'], 'secret-token');
    });

    test('a declared extra header rides along, and only for the client that declared it', () async {
      late http.BaseRequest withExtra;
      late http.BaseRequest without;
      final epg = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((request) async {
          withExtra = request;
          return ok();
        }),
        extraHeaders: const {'X-Plex-Provider-Version': '5.1'},
      );
      final plain = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((request) async {
          without = request;
          return ok();
        }),
      );
      addTearDown(epg.dispose);
      addTearDown(plain.dispose);

      await epg.get('https://epg.provider.plex.tv/x', token: 'tok');
      await plain.get('https://discover.provider.plex.tv/x', token: 'tok');

      expect(headerKeys(withExtra), contains('x-plex-provider-version'));
      expect(withExtra.headers['X-Plex-Provider-Version'], '5.1');
      expect(headerKeys(without), isNot(contains('x-plex-provider-version')));
    });

    test('a PUT sends the same set, plus only the JSON content type', () async {
      late http.BaseRequest sent;
      final client = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((request) async {
          sent = request;
          return ok();
        }),
      );
      addTearDown(client.dispose);

      await client.put(
        'https://epg.provider.plex.tv/x',
        token: 'tok',
        body: const [
          {'id': 'a'},
        ],
      );

      expect(headerKeys(sent), {'accept', 'x-plex-product', 'x-plex-client-identifier', 'x-plex-token'});
      expect(sent.headers['content-type'], contains('application/json'));
      expect(jsonDecode((sent as http.Request).body), [
        {'id': 'a'},
      ]);
    });

    test('the token travels per request, so the client holds no auth state', () async {
      final tokens = <String?>[];
      final client = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((request) async {
          tokens.add(request.headers['X-Plex-Token']);
          return ok();
        }),
      );
      addTearDown(client.dispose);

      await client.get('https://discover.provider.plex.tv/x', token: 'first');
      await client.get('https://discover.provider.plex.tv/x', token: 'second');

      expect(tokens, ['first', 'second']);
    });

    // Header names are case-insensitive over the wire, a Dart map is not. A
    // caller must not be able to slip an auth header past the boundary in
    // either casing, whatever the underlying client does with the merge.
    for (final key in ['X-Plex-Token', 'x-plex-token']) {
      test('an extra header named $key cannot replace the token', () async {
        final seen = <String>[];
        final client = PlexCloudHttpClient.forTesting(
          httpClient: MockClient((request) async {
            request.headers.forEach((name, value) {
              if (name.toLowerCase() == 'x-plex-token') seen.add(value);
            });
            return ok();
          }),
          extraHeaders: {key: 'INJECTED'},
        );
        addTearDown(client.dispose);

        await client.get('https://discover.provider.plex.tv/x', token: 'real-token');

        expect(seen, ['real-token'], reason: 'exactly one auth header, and it is the one the caller passed');
      });
    }
  });

  group('errors', () {
    test('a 503 throws after exactly one request: no failover, no retry', () async {
      var calls = 0;
      final client = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((_) async {
          calls++;
          return http.Response('nope', 503);
        }),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.get('https://epg.provider.plex.tv/x', token: 'tok'),
        throwsA(isA<MediaServerHttpException>()),
      );
      expect(calls, 1);
    });

    test('a failing PUT throws too', () async {
      final client = PlexCloudHttpClient.forTesting(
        httpClient: MockClient((_) async => http.Response('{"error":"bad"}', 400)),
      );
      addTearDown(client.dispose);

      await expectLater(
        client.put('https://epg.provider.plex.tv/x', token: 'tok', body: const []),
        throwsA(isA<MediaServerHttpException>()),
      );
    });
  });
}
