import 'dart:convert';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_kind.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

http.Response _json(Object body) => http.Response(jsonEncode(body), 200, headers: {'content-type': 'application/json'});

void main() {
  late AppDatabase db;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
  });

  tearDown(() async {
    await db.close();
  });

  PlexClient makeClient(Future<http.Response> Function(http.Request request) handler) {
    return PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Plezy',
        version: 'test',
      ),
      serverId: ServerId('plex-1'),
      serverName: 'Plex',
      httpClient: MockClient(handler),
    );
  }

  test('search defaults to 100 movie and TV candidates', () async {
    final captured = <Uri>[];
    final client = makeClient((request) async {
      captured.add(request.url);
      if (request.url.path == '/library/search') {
        return _json({
          'MediaContainer': {
            'SearchResult': [
              {
                'score': 90,
                'Metadata': {'ratingKey': 'movie-1', 'type': 'movie', 'title': 'The Movie'},
              },
            ],
          },
        });
      }
      return http.Response('unexpected request', 500);
    });
    addTearDown(client.close);

    final results = await client.searchItems('the');

    expect(results.map((item) => item.id), ['movie-1']);
    expect(captured, hasLength(1));
    expect(captured.single.path, '/library/search');
    expect(captured.single.queryParameters['limit'], '100');
    expect(captured.single.queryParameters['X-Plex-Container-Size'], '100');
    expect(captured.single.queryParameters['searchTypes'], 'movies,tv');
  });

  group('searchPeople (SRCH-2)', () {
    test('reads the actor hub from /hubs/search, ignoring every other hub', () async {
      final captured = <Uri>[];
      final client = makeClient((request) async {
        captured.add(request.url);
        if (request.url.path == '/hubs/search') {
          return _json({
            'MediaContainer': {
              'Hub': [
                {
                  'type': 'movie',
                  'Metadata': [
                    {'ratingKey': 'movie-1', 'type': 'movie', 'title': 'Dune'},
                  ],
                },
                {
                  'type': 'actor',
                  'Directory': [
                    {'id': '9001', 'tag': 'Denzel Washington', 'thumb': '/library/metadata/9001/thumb/123'},
                    {'id': '9002', 'tag': 'Timothée Chalamet'},
                  ],
                },
              ],
            },
          });
        }
        return http.Response('unexpected request', 500);
      });
      addTearDown(client.close);

      final results = await client.searchPeople('denzel');

      expect(captured.single.path, '/hubs/search');
      expect(results.map((item) => item.id), ['9001', '9002']);
      expect(results.first.title, 'Denzel Washington');
      expect(results.first.thumbPath, '/library/metadata/9001/thumb/123');
      expect(results.first.kind, MediaKind.unknown);
      expect(results.first.serverId, 'plex-1');
    });

    test('no actor hub in the response yields no people', () async {
      final client = makeClient((request) async {
        return _json({
          'MediaContainer': {
            'Hub': [
              {
                'type': 'movie',
                'Metadata': [
                  {'ratingKey': 'movie-1', 'type': 'movie', 'title': 'Dune'},
                ],
              },
            ],
          },
        });
      });
      addTearDown(client.close);

      expect(await client.searchPeople('dune'), isEmpty);
    });

    test('a failing hub search degrades to no people rather than throwing', () async {
      final client = makeClient((request) async => http.Response('server error', 500));
      addTearDown(client.close);

      expect(await client.searchPeople('anything'), isEmpty);
    });
  });
}
