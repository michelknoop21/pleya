import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/media/server_capabilities.dart';
import 'package:pleya/models/pleya_server/pleya_wire.dart';
import 'package:pleya/services/pleya_server_capabilities.dart';
import 'package:pleya/services/pleya_server_client.dart';

/// PS-3 acceptance criterion 4: no UI surface shows an empty or broken state
/// because of an unsupported capability. The gate for that is here, so the test
/// is here too.
void main() {
  PleyaCapabilities caps({
    bool browse = true,
    bool search = true,
    bool artwork = true,
    bool watchState = false,
    bool playbackPlan = false,
    bool transcode = false,
    bool downloads = false,
    bool liveTv = false,
    bool realtime = false,
    bool users = false,
  }) => PleyaCapabilities(
    browse: browse,
    search: search,
    artwork: artwork,
    watchState: watchState,
    playbackPlan: playbackPlan,
    transcode: transcode,
    downloads: downloads,
    liveTv: liveTv,
    realtime: realtime,
    users: users,
  );

  group('before /info has answered', () {
    test('the client claims nothing', () {
      const unknown = PleyaServerCapabilityResolver.unknown;
      expect(unknown.videoTranscoding, isFalse, reason: 'the ServerCapabilities default is true and would be a lie');
      expect(unknown.liveTv, isFalse);
      expect(unknown.serverSidePlaylists, isFalse);
      expect(unknown.serverFavorites, isFalse);
      expect(unknown.richMetadataEdit, isFalse);
      expect(unknown.alphaBar, AlphaBarMode.none);
      expect(unknown.folderGrouping, isFalse);
    });
  });

  group('a PS-2 era server', () {
    final resolved = PleyaServerCapabilityResolver.resolve(caps());

    test('offers nothing PS-3 has not built', () {
      expect(resolved.videoTranscoding, isFalse);
      expect(resolved.serverSidePlayQueue, isFalse);
      expect(resolved.serverSidePlaylists, isFalse);
      expect(resolved.liveTv, isFalse);
      expect(resolved.liveTvDvr, isFalse);
      expect(resolved.serverSideSync, isFalse);
      expect(resolved.offlineWatchQueue, isFalse);
      expect(resolved.continueWatchingRemoval, isFalse);
      expect(resolved.trackPreferencePersistence, isFalse);
      expect(resolved.serverFavorites, isFalse);
      expect(resolved.numericUserRating, isFalse);
      expect(resolved.richMetadataEdit, isFalse);
      expect(resolved.richHubs, isFalse);
      expect(resolved.scrubThumbnails, isFalse);
      expect(resolved.discordRpc, isFalse);
      expect(resolved.endpointFailover, isFalse);
      expect(resolved.subtitleSearch, isFalse);
      expect(resolved.externalSubtitleSearch, isFalse);
    });

    test('has no alpha bar, because the contract has no first-character endpoint', () {
      expect(resolved.alphaBar, AlphaBarMode.none);
    });

    test('has no folder grouping, because the contract exposes no folder listing', () {
      expect(resolved.folderGrouping, isFalse);
    });
  });

  group('a server that runs ahead of this build', () {
    test('still gets nothing the client cannot do', () {
      final resolved = PleyaServerCapabilityResolver.resolve(
        caps(watchState: true, playbackPlan: true, transcode: true, downloads: true, liveTv: true, users: true),
      );
      expect(
        resolved.videoTranscoding,
        isFalse,
        reason: 'quality presets with nothing behind them is criterion 4 failing',
      );
      expect(resolved.liveTv, isFalse, reason: 'a Live TV tab that opens on an empty screen is the same failure');
      expect(resolved.serverSideSync, isFalse);
      expect(resolved.serverFavorites, isFalse);
      expect(
        resolved.trackPreferencePersistence,
        isFalse,
        reason: 'a stored language needs the playback plan to resolve it, and that is PS-9T',
      );
      // The two that PS-4 did implement. They are here as the counter-example:
      // this group proves the resolver gates on the client half, not that the
      // client half is always false.
      expect(resolved.offlineWatchQueue, isTrue);
      expect(resolved.continueWatchingRemoval, isTrue);
    });
  });

  group('PleyaServerClient', () {
    PleyaServerConnection connection() => PleyaServerConnection(
      id: 'pleyaServer.srv-1',
      baseUrl: 'http://nas.lan:8832',
      serverId: 'srv-1',
      serverName: 'Zolder',
      userName: 'michel',
      refreshToken: 'rt-1',
      createdAt: DateTime.utc(2026, 8, 19),
    );

    Map<String, dynamic> infoBody({bool setupRequired = false, bool watchState = false}) => {
      'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
      'server': {'id': 'srv-1'},
      'capabilities': {'browse': true, 'search': true, 'artwork': true, 'watch_state': watchState},
      'auth': {
        'methods': ['password'],
        'setup_required': setupRequired,
      },
    };

    http.Response json(Object body, {int status = 200}) =>
        http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

    test('starts incapable and only becomes capable after /info', () async {
      final client = PleyaServerClient.create(
        connection(),
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody());
          if (request.url.path.endsWith('/auth/refresh')) {
            return json(const {
              'access_token': 'at',
              'refresh_token': 'rt-2',
              'token_type': 'bearer',
              'expires_in_ms': 900000,
            });
          }
          return json(const {
            'id': 'srv-1',
            'name': 'Zolder',
            'version': '0.2.0',
            'started_at': '2026-08-18T19:25:33Z',
          });
        }),
      );
      expect(client.backend, MediaBackend.pleyaServer);
      expect(client.wireCapabilities.browse, isFalse, reason: 'nothing is known before the first answer');
      await client.refreshCapabilities();
      expect(client.wireCapabilities.browse, isTrue);
      expect(client.wireCapabilities.watchState, isFalse);
      expect(client.capabilities.videoTranscoding, isFalse);
      client.close();
    });

    test('a healthy server is online, and /info plus /server both run', () async {
      final paths = <String>[];
      final client = PleyaServerClient.create(
        connection(),
        httpClientFactory: () => MockClient((request) async {
          paths.add(request.url.path);
          if (request.url.path.endsWith('/info')) return json(infoBody());
          if (request.url.path.endsWith('/auth/refresh')) {
            return json(const {
              'access_token': 'at',
              'refresh_token': 'rt-2',
              'token_type': 'bearer',
              'expires_in_ms': 900000,
            });
          }
          return json(const {
            'id': 'srv-1',
            'name': 'Zolder',
            'version': '0.2.0',
            'started_at': '2026-08-18T19:25:33Z',
          });
        }),
      );
      expect(await client.checkHealth(), HealthStatus.online);
      expect(paths.where((p) => p.endsWith('/info')), isNotEmpty);
      expect(paths.where((p) => p.endsWith('/server')), isNotEmpty);
      client.close();
    });

    test('a reachable server with a dead token is authError, not offline', () async {
      final client = PleyaServerClient.create(
        connection(),
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody());
          return json(const {
            'error': {'code': 'auth.invalid_token', 'message': 'no', 'retryable': false},
          }, status: 401);
        }),
      );
      expect(await client.checkHealth(), HealthStatus.authError);
      client.close();
    });

    test('an unreachable server is offline, not authError', () async {
      final client = PleyaServerClient.create(
        connection(),
        httpClientFactory: () => MockClient((_) async => throw Exception('no route to host')),
      );
      expect(await client.checkHealth(), HealthStatus.offline);
      client.close();
    });

    test('a server that was reset back to setup is authError', () async {
      final client = PleyaServerClient.create(
        connection(),
        httpClientFactory: () => MockClient((request) async {
          if (request.url.path.endsWith('/info')) return json(infoBody(setupRequired: true));
          return json(const {
            'id': 'srv-1',
            'name': 'Zolder',
            'version': '0.2.0',
            'started_at': '2026-08-18T19:25:33Z',
          });
        }),
      );
      expect(
        await client.checkHealth(),
        HealthStatus.authError,
        reason: 'a server with no owner has invalidated every stored token, and "offline" hides that',
      );
      client.close();
    });

    test('every write member answers "not applicable" rather than throwing', () async {
      final client = PleyaServerClient.create(
        connection(),
        httpClientFactory: () => MockClient((_) async => json(const {})),
      );
      await expectLater(client.markWatched(_dummyItem), completes);
      await expectLater(client.rate(_dummyItem, 8), completes);
      expect(await client.deleteMediaItem(_dummyItem), isFalse);
      expect(await client.addToPlaylist(playlistId: 'p', items: const []), isFalse);
      expect(await client.createPlaylist(title: 't', items: const []), isNull);
      expect((await client.fetchPlaylists()), isEmpty);
      expect((await client.fetchCollections('lib-1')), isEmpty);
      expect((await client.fetchFirstCharacters('lib-1')), isEmpty);
      expect((await client.fetchLibraryFiltersWithValues('lib-1')).filters, isEmpty);
      expect(client.liveTvDvr, isNull);
      client.close();
    });
  });
}

MediaItem _item() => MediaItem(
  id: 'item-1',
  backend: MediaBackend.pleyaServer,
  kind: MediaKind.movie,
  title: 'Grease',
  serverId: 'srv-1',
);

final _dummyItem = _item();
