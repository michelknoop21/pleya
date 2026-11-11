// A-23e: the phone's listener outlives an identity rebuild (the rebuild only
// restarts the host). It must then match the identities of now: a listener
// that bound with only a non-Plex identity otherwise ignores the Apple TV's
// Plex beacon forever, and the Meenemen card never shows.
import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/connection/connection_registry.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/models/plex/plex_home.dart';
import 'package:pleya/models/plex/plex_home_user.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/profiles/plex_home_service.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/profiles/profile_connection_registry.dart';
import 'package:pleya/profiles/profile_registry.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/lan_discovery_service.dart';
import 'package:pleya/services/companion_remote/remote_auth_context.dart';
import 'package:pleya/services/companion_remote/remote_auth_service.dart';
import 'package:pleya/services/storage_service.dart';

import '../../test_helpers/prefs.dart';

/// A listener socket the test feeds datagrams into.
class _Socket extends Stream<RawSocketEvent> implements RawDatagramSocket {
  final events = StreamController<RawSocketEvent>.broadcast();
  final _pending = <Datagram>[];

  void deliver(List<int> data) {
    _pending.add(Datagram(Uint8List.fromList(data), InternetAddress('10.0.0.2'), LanDiscoveryService.discoveryPort));
    events.add(RawSocketEvent.read);
  }

  @override
  Datagram? receive() => _pending.isEmpty ? null : _pending.removeAt(0);

  @override
  StreamSubscription<RawSocketEvent> listen(
    void Function(RawSocketEvent)? onData, {
    Function? onError,
    void Function()? onDone,
    bool? cancelOnError,
  }) => events.stream.listen(onData, onError: onError, onDone: onDone, cancelOnError: cancelOnError);

  @override
  void close() {}

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// The beacon an Apple TV sends for the home behind [discoveryKey], in the wire format.
List<int> _tvBeacon(List<int> discoveryKey, {bool playing = true}) {
  final auth = RemoteAuthService.instance;
  final homeHash = auth.computeDiscoveryTag(discoveryKey);
  const ips = ['10.0.0.2'];
  return utf8.encode(
    jsonEncode({
      'app': 'pleya',
      'v': 1,
      'homeHash': homeHash,
      'name': 'Woonkamer',
      'platform': 'tvOS',
      'clientId': 'tv-1',
      'port': 48632,
      'ips': ips,
      'hmac': auth.computeBeaconHmac(
        discoveryKey: discoveryKey,
        version: 1,
        homeHash: homeHash,
        name: 'Woonkamer',
        platform: 'tvOS',
        clientId: 'tv-1',
        port: 48632,
        ips: ips,
      ),
      if (playing) 'playing': true,
      'follow': true,
    }),
  );
}

RemoteAuthContext _context(String id, List<int> discoveryKey) => RemoteAuthContext(
  id: id,
  backend: 'plex',
  connectionId: id,
  homeSecret: const [1, 2, 3],
  discoveryKey: discoveryKey,
  clientIdentifier: 'phone-1',
  userUuid: 'u',
  allowedUserUuids: const [],
);

Future<void> _turn() => Future<void>.delayed(Duration.zero);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(resetSharedPreferencesForTest);

  test('the listener matches the identities of now, not those it bound with', () async {
    final socket = _Socket();
    final service = LanDiscoveryService(listenerSocketFactory: () async => socket);
    addTearDown(() async {
      service.dispose();
      await socket.events.close();
    });
    const plexKey = [4, 5, 6, 7];
    var identities = [
      _context('pleya', const [9, 9, 9, 9]),
    ];
    final seen = <List<DiscoveredHost>>[];
    final subscription = service.startListeningForCurrentContexts(() => identities).listen(seen.add);
    addTearDown(subscription.cancel);
    await _turn();

    socket.deliver(_tvBeacon(plexKey));
    await _turn();
    expect(seen, isEmpty, reason: 'negative control: another home stays ignored');

    identities = [...identities, _context('plex', plexKey)];
    socket.deliver(_tvBeacon(plexKey));
    await _turn();

    expect(seen.single.single.name, 'Woonkamer');
    expect(seen.single.single.authContextId, 'plex');
    expect(seen.single.single.playing, isTrue);
  });

  test('a rebuild that adds a Plex identity while the fly host runs lets the bound listener take its beacon', () async {
    final db = AppDatabase.forTesting(NativeDatabase.memory());
    final connections = ConnectionRegistry(db);
    final profileConnections = ProfileConnectionRegistry(db);
    final profiles = ProfileRegistry(db);
    final storage = await StorageService.getInstance();
    final plexHome = PlexHomeService(
      connections: connections,
      profileConnections: profileConnections,
      storage: storage,
      plexHomeUserFetcher: (_) async => const [],
    );
    final active = ActiveProfileProvider(
      registry: profiles,
      plexHome: plexHome,
      connections: connections,
      storage: storage,
    );
    addTearDown(() async {
      await active.resetForTesting();
      active.dispose();
      await plexHome.dispose();
      await db.close();
    });

    final plexAccount = _plexAccount('plex-b', 'client-b');
    final profile = Profile.local(id: 'profile-b', displayName: 'b', createdAt: DateTime(2026, 1, 1));
    await connections.upsert(plexAccount);
    await profiles.upsert(profile);
    await profileConnections.upsert(
      ProfileConnection(profileId: profile.id, connectionId: plexAccount.id, userIdentifier: 'admin-b'),
      makeDefault: true,
    );
    await storage.setActiveProfileId(profile.id);
    await active.initialize();

    final sockets = <_Socket>[];
    final provider = CompanionRemoteProvider(
      discoveryService: LanDiscoveryService(
        listenerSocketFactory: () async {
          final socket = _Socket();
          sockets.add(socket);
          return socket;
        },
      ),
    );
    addTearDown(() async {
      await provider.stopHostServer();
      provider.dispose();
      for (final socket in sockets) {
        await socket.events.close();
      }
    });

    // The phone starts with an identity that is not the Apple TV's Plex Home,
    // runs its fly host, and Home listens for a playing Apple TV.
    await provider.initializeJellyfinCrypto(connection: _jellyfinConnection('j'), activeProfile: profile);
    await provider.requestHandoffOnlyHost();
    await provider.startHostServer(handoffOnly: true);
    expect(provider.isHostServerRunning, isTrue);
    final seen = <List<DiscoveredHost>>[];
    final subscription = provider.discoverHosts()!.listen(seen.add);
    addTearDown(subscription.cancel);
    await _turn();
    expect(provider.isListeningForHosts, isTrue);

    // The Plex identity appears: the rebuild restarts the host, not the listener.
    final ok = await provider.ensureCryptoReady(
      _home('admin-b'),
      connections: connections,
      activeProfile: active,
      profileConnections: profileConnections,
      account: plexAccount,
    );
    expect(ok, isTrue);
    final plex = provider.debugAuthContexts.singleWhere((c) => c.backend == 'plex');
    expect(provider.isListeningForHosts, isTrue);
    expect(sockets, hasLength(1), reason: 'the listener that bound before the rebuild is still the one');

    sockets.single.deliver(_tvBeacon(plex.discoveryKey));
    await _turn();

    final tv = seen.last.single;
    expect(tv.name, 'Woonkamer');
    expect(tv.playing, isTrue);
    expect(tv.authContextId, plex.id);
  });
}

PlexAccountConnection _plexAccount(String id, String clientIdentifier) {
  return PlexAccountConnection(
    id: id,
    accountToken: 'token-$id',
    clientIdentifier: clientIdentifier,
    accountLabel: id,
    createdAt: DateTime(2026, 1, 1),
  );
}

JellyfinConnection _jellyfinConnection(String id) {
  return JellyfinConnection(
    id: id,
    baseUrl: 'https://jellyfin.example.test',
    serverName: 'Jellyfin',
    serverMachineId: 'machine-$id',
    userId: 'user-$id',
    userName: 'User $id',
    accessToken: 'token-$id',
    deviceId: 'device-$id',
    createdAt: DateTime(2026, 1, 1),
  );
}

PlexHome _home(String adminUuid) {
  return PlexHome(
    id: 1,
    name: 'Home',
    guestUserID: null,
    guestUserUUID: '',
    guestEnabled: false,
    subscription: false,
    users: [
      PlexHomeUser(
        id: 1,
        uuid: adminUuid,
        title: adminUuid,
        thumb: '',
        hasPassword: false,
        restricted: false,
        updatedAt: null,
        admin: true,
        guest: false,
        protected: false,
      ),
    ],
  );
}
