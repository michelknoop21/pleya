/// Which library maintenance a library's menu offers, and on which client it
/// runs. Real Plex, Jellyfin and Pleya Server clients over a mocked HTTP
/// client, so the gate is the clients' own capabilities and rights, not a
/// backend switch.
library;

import 'dart:convert';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/media_library.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/screens/libraries/library_maintenance.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';

http.Response _json(Object? body, {int status = 200}) =>
    http.Response(body == null ? '' : jsonEncode(body), status, headers: const {'content-type': 'application/json'});

MediaLibrary _library(String serverId, MediaBackend backend) =>
    MediaLibrary(id: 'lib-1', backend: backend, title: 'Films', kind: MediaKind.movie, serverId: serverId);

Future<PleyaServerClient> _pleya({required String role, bool administration = true, List<String>? requests}) async {
  final client = PleyaServerClient.create(
    PleyaServerConnection(
      id: 'pleyaServer.srv-1',
      baseUrl: 'http://nas.lan:8832',
      serverId: 'srv-1',
      serverName: 'Zolder',
      userName: 'michel',
      refreshToken: 'rt-1',
      role: role,
      createdAt: DateTime.utc(2026, 10, 2),
    ),
    httpClientFactory: () => MockClient((request) async {
      final path = request.url.path.replaceFirst('/pleya/v1', '');
      if (path == '/auth/refresh') {
        return _json(const {
          'access_token': 'at',
          'refresh_token': 'rt-2',
          'token_type': 'bearer',
          'expires_in_ms': 900000,
        });
      }
      if (path == '/info') {
        return _json({
          'protocol': {'major': 1, 'feature_level': 1, 'profile': 'full'},
          'server': {'id': 'srv-1'},
          'capabilities': {
            'browse': true,
            'search': true,
            'artwork': true,
            'watch_state': true,
            'users': true,
            'administration': administration,
          },
          'auth': {
            'methods': ['password'],
            'setup_required': false,
          },
        });
      }
      requests?.add('${request.method} $path');
      if (path == '/libraries/lib-1/scan') return _json({'id': 'scan-1', 'state': 'queued'}, status: 202);
      return _json(null, status: 404);
    }),
  );
  await client.refreshCapabilities();
  return client;
}

JellyfinClient _jellyfin({required bool admin}) => JellyfinClient.forTesting(
  connection: JellyfinConnection(
    id: 'jf-1/user-a',
    baseUrl: 'https://jellyfin.example',
    serverName: 'Jelly',
    serverMachineId: 'jf-1',
    userId: 'user-a',
    userName: 'User A',
    accessToken: 'token',
    deviceId: 'device',
    isAdministrator: admin,
    createdAt: DateTime.fromMillisecondsSinceEpoch(0),
  ),
  httpClient: MockClient((_) async => _json(null, status: 404)),
);

Future<void> _registerOwnedPlex(MultiServerManager m) async {
  final db = AppDatabase.forTesting(NativeDatabase.memory());
  PlexApiCache.initialize(db);
  addTearDown(db.close);
  m.debugRegisterClientForTesting(
    PlexClient.forTesting(
      config: PlexConfig(
        baseUrl: 'https://plex.example',
        token: 'token',
        clientIdentifier: 'client-id',
        product: 'Pleya',
        version: 'test',
      ),
      serverId: ServerId('plex-1'),
      serverName: 'Woonkamer',
      httpClient: MockClient((_) async => _json({'MediaContainer': <String, Object?>{}})),
    ),
  );
  await m.refreshTokensForProfile(
    PlexAccountConnection(
      id: 'account-1',
      accountToken: 'account-token',
      clientIdentifier: 'account-client',
      accountLabel: 'Account',
      servers: [
        PlexServer(
          name: 'Woonkamer',
          clientIdentifier: 'plex-1',
          accessToken: 'token',
          connections: const [],
          owned: true,
        ),
      ],
      createdAt: DateTime.fromMillisecondsSinceEpoch(0),
    ),
  );
}

MultiServerManager _manager() {
  final m = MultiServerManager();
  addTearDown(m.dispose);
  return m;
}

List<LibraryMaintenance> _offered(MultiServerManager m, MediaLibrary library) =>
    libraryMaintenanceFor(libraryMaintenanceClient(m, library));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('libraryMaintenanceFor', () {
    test('a Pleya Server admin can scan the library (and refresh, which starts the same scan)', () async {
      final m = _manager()..debugRegisterClientForTesting(await _pleya(role: 'admin'));

      expect(_offered(m, _library('srv-1', MediaBackend.pleyaServer)), [
        LibraryMaintenance.scan,
        LibraryMaintenance.refreshMetadata,
      ]);
    });

    test('a Pleya Server owner gets the same', () async {
      final m = _manager()..debugRegisterClientForTesting(await _pleya(role: 'owner'));

      expect(_offered(m, _library('srv-1', MediaBackend.pleyaServer)), contains(LibraryMaintenance.scan));
    });

    test('a Pleya Server member gets nothing', () async {
      final m = _manager()..debugRegisterClientForTesting(await _pleya(role: 'member'));

      expect(_offered(m, _library('srv-1', MediaBackend.pleyaServer)), isEmpty);
    });

    test('a Pleya Server without the administration capability gets nothing', () async {
      final m = _manager()..debugRegisterClientForTesting(await _pleya(role: 'owner', administration: false));

      expect(_offered(m, _library('srv-1', MediaBackend.pleyaServer)), isEmpty);
    });

    test('an owned Plex server keeps all four, in menu order', () async {
      final m = _manager();
      await _registerOwnedPlex(m);

      expect(_offered(m, _library('plex-1', MediaBackend.plex)), [
        LibraryMaintenance.scan,
        LibraryMaintenance.analyze,
        LibraryMaintenance.refreshMetadata,
        LibraryMaintenance.emptyTrash,
      ]);
    });

    test('a Jellyfin administrator can scan and refresh, not analyze or empty trash', () {
      final m = _manager()..debugRegisterJellyfinClientForTesting(_jellyfin(admin: true));

      expect(_offered(m, _library('jf-1', MediaBackend.jellyfin)), [
        LibraryMaintenance.scan,
        LibraryMaintenance.refreshMetadata,
      ]);
    });

    test('a Jellyfin user without admin rights gets nothing', () {
      final m = _manager()..debugRegisterJellyfinClientForTesting(_jellyfin(admin: false));

      expect(_offered(m, _library('jf-1', MediaBackend.jellyfin)), isEmpty);
    });

    test('a library whose own server is gone never borrows another administered server', () async {
      final m = _manager()..debugRegisterClientForTesting(await _pleya(role: 'owner'));
      await _registerOwnedPlex(m);

      expect(libraryMaintenanceClient(m, _library('gone', MediaBackend.plex)), isNull);
      expect(_offered(m, _library('gone', MediaBackend.plex)), isEmpty);
    });
  });

  test('a Pleya Server scan posts to that library on that server', () async {
    final requests = <String>[];
    final m = _manager()..debugRegisterClientForTesting(await _pleya(role: 'admin', requests: requests));
    final library = _library('srv-1', MediaBackend.pleyaServer);

    await runLibraryMaintenance(libraryMaintenanceClient(m, library)!, LibraryMaintenance.scan, library.id);

    expect(requests, ['POST /libraries/lib-1/scan']);
  });
}
