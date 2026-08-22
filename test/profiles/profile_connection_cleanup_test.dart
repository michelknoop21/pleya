import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_cleanup.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

JellyfinConnection _jellyfin({String machineId = 'jf-machine', String userId = 'user-a'}) {
  return JellyfinConnection(
    id: '$machineId/$userId',
    baseUrl: 'https://jellyfin.local',
    serverName: 'Jellyfin',
    serverMachineId: machineId,
    userId: userId,
    userName: userId,
    accessToken: 'token-$userId',
    deviceId: 'device-1',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
    lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  );
}

PlexAccountConnection _plex() {
  return PlexAccountConnection(
    id: 'plex-account',
    accountToken: 'account-token',
    clientIdentifier: 'client-1',
    accountLabel: 'Plex',
    servers: [
      PlexServer(
        name: 'Plex Server',
        clientIdentifier: 'plex-machine',
        accessToken: 'server-token',
        connections: [
          PlexConnection(
            protocol: 'https',
            address: 'plex.example.test',
            port: 443,
            uri: 'https://plex.example.test',
            local: false,
            relay: false,
            ipv6: false,
          ),
        ],
        owned: true,
      ),
    ],
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
    lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  );
}

PleyaShareConnection _pleyaShare({String id = 'share-1'}) {
  return PleyaShareConnection(
    id: id,
    hostName: 'Woonkamer',
    pairId: 'pair-1',
    pairSecret: 'secret-1',
    lastKnownIps: const ['192.168.1.20'],
    port: 48632,
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  );
}

LocalFolderConnection _localFolder({String id = 'local-1'}) {
  return LocalFolderConnection(
    id: id,
    directoryUri: '/tmp/media',
    displayName: 'Films lokaal',
    libraryType: 'movies',
    createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  );
}

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late StorageService storage;

  setUp(() async {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    storage = await StorageService.getInstance();
  });

  tearDown(() async {
    await db.close();
  });

  group('profile connection cleanup', () {
    test('removing the last Jellyfin profile link deletes the connection and profile prefs', () async {
      final conn = _jellyfin();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p1',
          connectionId: conn.id,
          userToken: conn.accessToken,
          userIdentifier: conn.userId,
        ),
      );
      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'jf-machine:movies'});
      await storage.saveLibraryOrder(['jf-machine:movies']);

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
      );

      expect(await profileConnections.listForConnection(conn.id), isEmpty);
      expect(await connections.get(conn.id), isNull);
      expect(storage.getHiddenLibraries(), isEmpty);
      expect(storage.getLibraryOrder(), isNull);
    });

    test('removing one profile link keeps a shared Jellyfin connection and other profile prefs', () async {
      final conn = _jellyfin();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p1',
          connectionId: conn.id,
          userToken: conn.accessToken,
          userIdentifier: conn.userId,
        ),
      );
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p2',
          connectionId: conn.id,
          userToken: conn.accessToken,
          userIdentifier: conn.userId,
        ),
      );

      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'jf-machine:movies'});
      await storage.setActiveProfileId('p2');
      await storage.saveHiddenLibraries({'jf-machine:movies'});

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
      );

      expect(await connections.get(conn.id), isNotNull);
      final remaining = await profileConnections.listForConnection(conn.id);
      expect(remaining, hasLength(1));
      expect(remaining.single.profileId, 'p2');

      await storage.setActiveProfileId('p1');
      expect(storage.getHiddenLibraries(), isEmpty);
      await storage.setActiveProfileId('p2');
      expect(storage.getHiddenLibraries(), {'jf-machine:movies'});
    });

    test('startup prune removes unreferenced Jellyfin rows and stale prefs', () async {
      final conn = _jellyfin();
      await connections.upsert(conn);
      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'jf-machine:movies'});
      await storage.saveLibrarySort('jf-machine:movies', 'titleSort');

      final removed = await pruneUnreferencedJellyfinConnections(
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
      );

      expect(removed, 1);
      expect(await connections.get(conn.id), isNull);
      expect(storage.getHiddenLibraries(), isEmpty);
      expect(storage.getLibrarySort('jf-machine:movies'), isNull);
    });

    test('startup prune does not clear prefs when another user on the same server is still referenced', () async {
      final orphan = _jellyfin(userId: 'user-a');
      final sharedServer = _jellyfin(userId: 'user-b');
      await connections.upsert(orphan);
      await connections.upsert(sharedServer);
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p2',
          connectionId: sharedServer.id,
          userToken: sharedServer.accessToken,
          userIdentifier: sharedServer.userId,
        ),
      );
      await storage.setActiveProfileId('p2');
      await storage.saveHiddenLibraries({'jf-machine:movies'});

      final removed = await pruneUnreferencedJellyfinConnections(
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
      );

      expect(removed, 1);
      expect(await connections.get(orphan.id), isNull);
      expect(await connections.get(sharedServer.id), isNotNull);
      expect(storage.getHiddenLibraries(), {'jf-machine:movies'});
    });

    test('Plex profile unlink clears only that profile because Plex Home access can be implicit', () async {
      final conn = _plex();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: conn.id, userToken: 'user-token', userIdentifier: 'home-user'),
      );

      await storage.setActiveProfileId('p1');
      await storage.saveHiddenLibraries({'plex-machine:movies'});
      await storage.setActiveProfileId('p2');
      await storage.saveHiddenLibraries({'plex-machine:movies'});

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
      );

      expect(await connections.get(conn.id), isNotNull);
      expect(await profileConnections.listForConnection(conn.id), isEmpty);
      await storage.setActiveProfileId('p1');
      expect(storage.getHiddenLibraries(), isEmpty);
      await storage.setActiveProfileId('p2');
      expect(storage.getHiddenLibraries(), {'plex-machine:movies'});
    });
  });

  group('removeConnectionCompletely', () {
    Future<void> removeCompletely(Connection conn) => removeConnectionCompletely(
      connection: conn,
      profileConnections: profileConnections,
      connections: connections,
      storage: storage,
    );

    test('orphan local folder (no profile bindings) is removed', () async {
      final conn = _localFolder();
      await connections.upsert(conn);
      await removeCompletely(conn);
      expect(await connections.get(conn.id), isNull);
    });

    test('local folder bound to one profile removes binding and row', () async {
      final conn = _localFolder();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'profile-a', connectionId: conn.id, userIdentifier: conn.id),
      );
      await removeCompletely(conn);
      expect(await connections.get(conn.id), isNull);
      expect(await profileConnections.listForConnection(conn.id), isEmpty);
    });

    test('local folder bound to two profiles removes everything', () async {
      final conn = _localFolder();
      await connections.upsert(conn);
      for (final profile in ['profile-a', 'profile-b']) {
        await profileConnections.upsert(
          ProfileConnection(profileId: profile, connectionId: conn.id, userIdentifier: conn.id),
        );
      }
      await removeCompletely(conn);
      expect(await connections.get(conn.id), isNull);
      expect(await profileConnections.listForConnection(conn.id), isEmpty);
    });
  });

  // Disconnecting has to land on this device on its own. The screens that do it
  // follow up with a rebind, and a rebind is asynchronous, can be deferred, and
  // runs against servers that may be down — which is the state the user is in
  // when they reach for "disconnect" in the first place.
  group('disconnecting lands locally, without help from a rebind', () {
    late MultiServerManager manager;

    setUp(() {
      manager = MultiServerManager();
    });

    tearDown(() => manager.dispose());

    test('an unreachable Plex server is gone from the runtime, and its banner with it', () async {
      final conn = _plex();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: conn.id, userIdentifier: 'plex-user'),
      );
      await storage.setActiveProfileId('p1');

      // The server is down and its token was rejected: the state that puts the
      // "session expired" bar on screen and keeps it there.
      manager.debugRegisterClientForTesting(_OfflineClient('plex-machine'), online: false);
      manager.debugMarkAuthErrorForTesting(ServerId('plex-machine'));
      expect(manager.authErrorServerIds, contains('plex-machine'));

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      expect(manager.serverIds, isEmpty, reason: 'no rebind ran; the disconnect has to stand on its own');
      expect(manager.authErrorServerIds, isEmpty);
      expect(await profileConnections.listForConnection(conn.id), isEmpty);
    });

    test('the healthy server of a two-server profile keeps working', () async {
      final plex = _plex();
      final jellyfin = _jellyfin();
      await connections.upsert(plex);
      await connections.upsert(jellyfin);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: plex.id, userIdentifier: 'plex-user'),
      );
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p1',
          connectionId: jellyfin.id,
          userToken: jellyfin.accessToken,
          userIdentifier: jellyfin.userId,
        ),
      );
      await storage.setActiveProfileId('p1');

      manager.debugRegisterClientForTesting(_OfflineClient('plex-machine'), online: false);
      manager.debugRegisterClientForTesting(_OfflineClient('jf-machine'));

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: plex,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      expect(manager.serverIds, ['jf-machine']);
      expect(manager.onlineServerIds, ['jf-machine']);
      expect(await connections.get(jellyfin.id), isNotNull);
      expect((await profileConnections.listForProfile('p1')).map((row) => row.connectionId), [jellyfin.id]);
    });

    test('removing a shared account from another profile leaves the active profile connected', () async {
      final conn = _plex();
      await connections.upsert(conn);
      for (final profile in ['p1', 'p2']) {
        await profileConnections.upsert(
          ProfileConnection(profileId: profile, connectionId: conn.id, userIdentifier: 'plex-user'),
        );
      }
      await storage.setActiveProfileId('p1');
      manager.debugRegisterClientForTesting(_OfflineClient('plex-machine'));

      await removeProfileConnectionAndCleanup(
        profileId: 'p2',
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      expect(manager.serverIds, ['plex-machine'], reason: 'p1 still reaches this server');
    });

    test('another profile\'s user on the same Jellyfin server keeps its client', () async {
      final mine = _jellyfin(userId: 'user-a');
      final theirs = _jellyfin(userId: 'user-b');
      await connections.upsert(mine);
      await connections.upsert(theirs);
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p1',
          connectionId: mine.id,
          userToken: mine.accessToken,
          userIdentifier: 'user-a',
        ),
      );
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p2',
          connectionId: theirs.id,
          userToken: theirs.accessToken,
          userIdentifier: 'user-b',
        ),
      );
      await storage.setActiveProfileId('p1');

      // Both users are registered against the same machine; p1's is the active
      // one and p2's is kept alive so a profile switch can re-bind it.
      final theirClient = JellyfinClient.forTesting(
        connection: theirs,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      final myClient = JellyfinClient.forTesting(
        connection: mine,
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      manager.debugRegisterJellyfinClientForTesting(theirClient);
      manager.debugRegisterJellyfinClientForTesting(myClient);

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: mine,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      expect(manager.serverIds, isEmpty, reason: 'the active profile no longer reaches this machine');
      expect(
        manager.getJellyfinClientByCompoundId(theirs.id),
        isNotNull,
        reason: 'the other profile\'s client is kept for a future switch and must survive this',
      );
      expect(await connections.get(theirs.id), isNotNull);
    });

    test('a disconnected Jellyfin connection stays gone across a restart', () async {
      final conn = _jellyfin();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(
          profileId: 'p1',
          connectionId: conn.id,
          userToken: conn.accessToken,
          userIdentifier: conn.userId,
        ),
      );
      await storage.setActiveProfileId('p1');
      manager.debugRegisterClientForTesting(_OfflineClient('jf-machine'), online: false);

      await removeProfileConnectionAndCleanup(
        profileId: 'p1',
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      // A cold start reads the same database through fresh registries — the
      // only thing that survives a restart.
      final restartedConnections = ConnectionRegistry(db);
      final restartedProfileConnections = ProfileConnectionRegistry(db);

      expect(await restartedConnections.list(), isEmpty);
      expect(await restartedProfileConnections.listAll(), isEmpty);
      expect(await restartedConnections.get(conn.id), isNull);
    });

    test('a disconnected Pleya Share host stays gone across a restart', () async {
      final conn = _pleyaShare();
      await connections.upsert(conn);
      await profileConnections.upsert(
        ProfileConnection(profileId: 'p1', connectionId: conn.id, userIdentifier: conn.id),
      );
      await storage.setActiveProfileId('p1');

      await removeConnectionCompletely(
        connection: conn,
        profileConnections: profileConnections,
        connections: connections,
        storage: storage,
        serverManager: manager,
      );

      final restartedConnections = ConnectionRegistry(db);
      expect(await restartedConnections.get(conn.id), isNull);
      expect(await ProfileConnectionRegistry(db).listAll(), isEmpty);
    });
  });
}

/// A registered server that answers nothing. The cleanup path never probes it;
/// what matters is only whether it is still registered afterwards.
class _OfflineClient implements MediaServerClient {
  _OfflineClient(String id) : serverId = ServerId(id);

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Server $serverId';

  @override
  Future<HealthStatus> checkHealth() async => HealthStatus.offline;

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
