import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/models/livetv_channel.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/livetv/plex_favorite_channels_service.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/plex_epg_client.dart';

/// The server token must never leave the media server. This test spends its
/// whole length proving that negative, because the bug it replaces was
/// invisible: `PlexClient` carries `config.headers` as defaults and
/// `MediaServerHttpClient` merges those into absolute-URL requests too, so a
/// single `_http.get('https://epg.provider.plex.tv/...')` was enough to hand a
/// PMS token to a Plex cloud host.
void main() {
  const serverSecret = 'SERVER_SECRET';
  const accountToken = 'ACCOUNT_TOKEN';

  late AppDatabase db;
  late List<http.BaseRequest> serverRequests;
  late List<http.Request> cloudRequests;

  setUp(() {
    db = AppDatabase.forTesting(NativeDatabase.memory());
    PlexApiCache.initialize(db);
    serverRequests = [];
    cloudRequests = [];
  });

  tearDown(() async => db.close());

  PlexClient plexClient() {
    return PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example.com',
        token: serverSecret,
        clientIdentifier: 'device-1',
        product: 'Pleya',
        version: '1',
        machineIdentifier: 'machine-1',
      ),
      serverId: ServerId('machine-1'),
      httpClient: MockClient((request) async {
        serverRequests.add(request);
        return http.Response('{}', 200, headers: {'content-type': 'application/json'});
      }),
      epgProviders: const [(identifier: 'tv.plex.provider.epg', gridEndpoint: '/grid')],
    );
  }

  PlexFavoriteChannelsService favoritesService() {
    final epg = PlexEpgClient.forTesting(
      httpClient: MockClient((request) async {
        cloudRequests.add(request);
        return http.Response(
          jsonEncode({
            'MediaContainer': {'size': 0},
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return PlexFavoriteChannelsService(
      profileId: 'profile-1',
      resolveAuth: () async =>
          (token: accountToken, profileId: 'profile-1', accountId: 'account-1', userId: 'user-1', isUserScoped: true),
      clientIdentifier: () async => 'device-1',
      clientBuilder: (_) => epg,
    );
  }

  test('the server token never reaches the EPG host, and the account token always does', () async {
    final client = plexClient();
    final service = favoritesService();
    addTearDown(client.close);
    addTearDown(service.dispose);

    final store = await service.resolveStore();
    await store!.fetchFavoriteChannels();
    await store.setFavoriteChannels([FavoriteChannel(source: 'server://machine-1/tv.plex.provider.epg', id: 'a')]);

    // The Plex server client is not involved at all, so the call cannot ride on
    // its default headers and cannot trip its endpoint failover either.
    expect(serverRequests, isEmpty);
    expect(cloudRequests, hasLength(2));

    for (final request in cloudRequests) {
      expect(request.url.host, 'epg.provider.plex.tv');
      expect(request.url.toString(), isNot(contains(serverSecret)));
      expect(request.body, isNot(contains(serverSecret)));
      for (final entry in request.headers.entries) {
        expect(entry.value, isNot(contains(serverSecret)), reason: 'header ${entry.key} carried the server token');
      }

      // The positive half: exactly one auth header, and it is the account one.
      // Without this a request with no token, a stale token or a second auth
      // header would still pass the checks above.
      final authHeaders = request.headers.entries.where((e) => e.key.toLowerCase() == 'x-plex-token').toList();
      expect(authHeaders, hasLength(1));
      expect(authHeaders.single.value, accountToken);
    }
  });

  test('a Plex client no longer offers a favorites store at all', () {
    final client = plexClient();
    addTearDown(client.close);

    expect(client.liveTv.favorites, isNull);
    expect(serverRequests, isEmpty);
  });

  group('the boundary holds at source level', () {
    test('no plex.tv host is named anywhere inside PlexClient', () {
      final offenders = <String>[];
      for (final entity in Directory('lib/services/plex_client').listSync(recursive: true)) {
        if (entity is! File || !entity.path.endsWith('.dart')) continue;
        final lines = entity.readAsLinesSync();
        for (var i = 0; i < lines.length; i++) {
          final line = lines[i];
          // Comments may explain the rule; code may not break it.
          if (line.trimLeft().startsWith('//')) continue;
          if (line.contains('.plex.tv') || line.contains('X-Plex-Provider-Version')) {
            offenders.add('${entity.path}:${i + 1}: ${line.trim()}');
          }
        }
      }
      final clientFile = File('lib/services/plex_client.dart').readAsLinesSync();
      for (var i = 0; i < clientFile.length; i++) {
        final line = clientFile[i];
        if (line.trimLeft().startsWith('//')) continue;
        if (line.contains('.plex.tv')) offenders.add('lib/services/plex_client.dart:${i + 1}: ${line.trim()}');
      }

      expect(
        offenders,
        isEmpty,
        reason:
            'A plex.tv call from PlexClient inherits the server token through defaultHeaders. '
            'Cloud calls belong in PlexCloudHttpClient. See DEC-021.',
      );
    });

    test('the favorites service knows nothing about servers or their tokens', () {
      final source = File('lib/services/livetv/plex_favorite_channels_service.dart').readAsStringSync();

      expect(source, isNot(contains('PlexClient')));
      expect(source, isNot(contains('PlexConfig')));
      expect(source, isNot(contains('defaultHeaders')));
    });
  });
}
