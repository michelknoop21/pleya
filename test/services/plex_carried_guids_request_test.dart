/// The Plex list requests behind related rows, hub overviews, playlists and
/// collections ask for the `Guid` array, so a title from one of those lists is
/// recognised on another server by its provider number and not by its name.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/unified/carried_external_ids.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';

class _RecordingClient extends http.BaseClient {
  final requests = <Uri>[];

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    requests.add(request.url);
    final movie = {
      'ratingKey': '7',
      'type': 'movie',
      'title': 'Léon',
      'guid': 'plex://movie/5d7768296f4521001ea9c1a5',
      'Guid': [
        {'id': 'tmdb://101'},
      ],
    };
    final body = request.url.path.endsWith('/related')
        ? {
            'MediaContainer': {
              'Hub': [
                {
                  'hubKey': '/hubs/x',
                  'key': '/hubs/x',
                  'title': 'More',
                  'type': 'movie',
                  'hubIdentifier': 'movie.similar',
                  'size': 1,
                  'Metadata': [movie],
                },
              ],
            },
          }
        : {
            'MediaContainer': {
              'size': 1,
              'totalSize': 1,
              'Metadata': [movie],
            },
          };
    return http.StreamedResponse(
      Stream.value(utf8.encode(jsonEncode(body))),
      200,
      headers: {'content-type': 'application/json'},
    );
  }
}

void main() {
  late _RecordingClient httpClient;
  late PlexClient client;

  setUp(() {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    addTearDown(db.close);
    httpClient = _RecordingClient();
    client = PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'http://server:32400',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('server-id'),
      serverName: 'Server',
      httpClient: httpClient,
    );
    addTearDown(client.close);
  });

  Uri requestFor(String pathPart) => httpClient.requests.firstWhere((u) => u.path.contains(pathPart));

  test('related hubs ask for the numbers and the items carry them', () async {
    final hubs = await client.fetchRelatedHubs('42');

    expect(requestFor('/hubs/metadata/42/related').queryParameters['includeGuids'], '1');
    expect(externalIdsCarriedBy(hubs.single.items.single)?.tmdb, 101);
  });

  test('a hub overview page asks for the numbers', () async {
    final page = await client.fetchMoreHubItemsPage('/hubs/sections/1/recent', start: 0, size: 20);

    expect(requestFor('/hubs/sections/1/recent').queryParameters['includeGuids'], '1');
    expect(externalIdsCarriedBy(page.items.single)?.tmdb, 101);
  });

  test('the full hub overview asks for the numbers', () async {
    await client.fetchHubContent('/hubs/sections/1/recent');

    expect(requestFor('/hubs/sections/1/recent').queryParameters['includeGuids'], '1');
  });

  test('playlist items ask for the numbers', () async {
    await client.fetchPlaylistPage('9', start: 0, size: 20);

    expect(requestFor('/playlists/9/items').queryParameters['includeGuids'], '1');
  });

  test('collection items ask for the numbers', () async {
    await client.fetchCollectionPage('5', start: 0, size: 20);

    expect(requestFor('/library/collections/5/children').queryParameters['includeGuids'], '1');
  });
}
