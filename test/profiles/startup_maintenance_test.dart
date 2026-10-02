import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_bootstrap.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/profiles/borrowed_connection_backfill.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/profiles/startup_maintenance.dart';
import 'package:pleya/services/server_registry.dart';
import 'package:pleya/services/storage_service.dart';

import '../test_helpers/prefs.dart';

final _jellyfin = JellyfinConnection(
  id: 'jf-machine/dad',
  baseUrl: 'https://jellyfin.local',
  serverName: 'Jellyfin',
  serverMachineId: 'jf-machine',
  userId: 'dad',
  userName: 'dad',
  accessToken: 'access-dad',
  deviceId: 'device-1',
  isAdministrator: true,
  createdAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
  lastAuthenticatedAt: DateTime.fromMillisecondsSinceEpoch(1_000_000),
);

class _ThrowingBootstrap extends ConnectionBootstrap {
  _ThrowingBootstrap({
    required super.storage,
    required super.connectionRegistry,
    required super.serverRegistry,
    required super.profileRegistry,
  });

  @override
  Future<void> run() async => throw StateError('bootstrap failed');
}

void main() {
  late AppDatabase db;
  late ConnectionRegistry connections;
  late ProfileConnectionRegistry profileConnections;
  late ProfileRegistry profileRegistry;
  late StorageService storage;

  setUp(() async {
    resetSharedPreferencesForTest();
    db = AppDatabase.forTesting(NativeDatabase.memory());
    connections = ConnectionRegistry(db);
    profileConnections = ProfileConnectionRegistry(db);
    profileRegistry = ProfileRegistry(db);
    storage = await StorageService.getInstance();
  });

  tearDown(() async => db.close());

  /// A pre-v20 borrow: the kid copied dad's token five minutes later and
  /// has no `borrowed` flag.
  Future<void> seedPreV20Borrow() async {
    await connections.upsert(_jellyfin);
    for (final (profile, minute) in [('dad', 0), ('kid', 5)]) {
      await profileConnections.upsert(
        ProfileConnection(
          profileId: profile,
          connectionId: _jellyfin.id,
          userToken: _jellyfin.accessToken,
          userIdentifier: _jellyfin.userId,
          tokenAcquiredAt: DateTime.fromMillisecondsSinceEpoch(1_700_000_000_000 + minute * 60000),
        ),
      );
    }
  }

  Future<Map<String, bool>> borrowedByProfile() async => {
    for (final pc in await profileConnections.listForConnection(_jellyfin.id)) pc.profileId: pc.borrowed,
  };

  Future<void> run(ConnectionBootstrap bootstrap) => runStartupMaintenance(
    bootstrap: bootstrap,
    profileConnections: profileConnections,
    connections: connections,
    storage: storage,
  );

  ConnectionBootstrap realBootstrap() => ConnectionBootstrap(
    storage: storage,
    connectionRegistry: connections,
    serverRegistry: ServerRegistry(storage),
    profileRegistry: profileRegistry,
    plexHomeUserFetcher: (_) async => const [],
    plexUserInfoFetcher: (_) async => throw StateError('offline'),
  );

  test('startup maintenance runs the borrowed backfill before the binder starts', () async {
    await seedPreV20Borrow();

    await run(realBootstrap());

    expect(await borrowedByProfile(), {'dad': false, 'kid': true});
    expect(storage.readBool(borrowedBackfillDoneKey), isTrue);
  });

  test('a failing bootstrap does not skip the borrowed backfill', () async {
    await seedPreV20Borrow();

    await run(
      _ThrowingBootstrap(
        storage: storage,
        connectionRegistry: connections,
        serverRegistry: ServerRegistry(storage),
        profileRegistry: profileRegistry,
      ),
    );

    expect(await borrowedByProfile(), {'dad': false, 'kid': true});
  });
}
