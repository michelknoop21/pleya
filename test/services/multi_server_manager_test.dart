import 'dart:async';
import 'package:pleya/media/ids.dart';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/database/app_database.dart';
import 'package:pleya/models/plex/plex_config.dart';
import 'package:pleya/services/plex_api_cache.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/services/plex_client.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/multi_server_manager.dart';
import 'package:pleya/services/pleya_server_client.dart';

import '../test_helpers/prefs.dart';

JellyfinConnection _jellyfinConnection(String userId) => JellyfinConnection(
  id: 'jf-machine/$userId',
  baseUrl: 'https://jf.example.com',
  serverName: 'Shared JF',
  serverMachineId: 'jf-machine',
  userId: userId,
  userName: userId,
  accessToken: 'token-$userId',
  deviceId: 'device',
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

JellyfinClient _jellyfinClient(String userId) => JellyfinClient.forTesting(
  connection: _jellyfinConnection(userId),
  httpClient: MockClient((_) async => http.Response('{}', 200)),
);

// NOTE on coverage scope:
// [MultiServerManager.addServer] / `connectToAllServers` / `_createClientForServer`
// all instantiate a real `PlexClient` via `findBestWorkingConnection`, which
// performs live HTTP calls to a Plex Media Server. The manager does NOT expose
// a fake `PlexClient` factory, so per the task brief we don't fake the network
// here.
//
// The tests below cover the orchestration logic that DOESN'T require a network:
//   - construction & initial state
//   - `removeServer` (pure local-map mutation)
//   - `updateServerStatus` + status-stream emissions
//   - `disconnectAll` / `dispose` lifecycle (no connectivity sub started, so
//     this verifies the no-op path for the subscription cancel)
//
// What is NOT covered here (would need a fake PlexClient factory):
//   - `addServer` success path
//   - `connectToAllServers` outcome map
//   - `checkServerHealth` health-probe sweep
//   - `_reoptimizeServer` endpoint promotion
//   - `_onServerEndpointsExhausted` debounce → reconnect
//   - `startNetworkMonitoring` connectivity-listener path

void main() {
  setUp(resetSharedPreferencesForTest);

  // ============================================================
  // Initial state
  // ============================================================

  group('initial state', () {
    test('a freshly constructed manager has no servers, clients, or status', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      expect(m.serverIds, isEmpty);
      expect(m.onlineServerIds, isEmpty);
      expect(m.offlineServerIds, isEmpty);
      expect(m.plexServers, isEmpty);
      expect(m.onlineClients, isEmpty);
    });

    test('getClient/getPlexServer return null for unknown ids', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      expect(m.getClient(ServerId('nope')), isNull);
      expect(m.getPlexServer(ServerId('nope')), isNull);
      expect(m.isServerOnline(ServerId('nope')), isFalse);
    });

    test('plexServers map is unmodifiable', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      // Map.unmodifiable rejects every mutating operation — clear() is the
      // simplest no-arg one to exercise the wrapper.
      expect(() => m.plexServers.clear(), throwsUnsupportedError);
    });
  });

  // ============================================================
  // updateServerStatus + status stream
  // ============================================================

  group('updateServerStatus + statusStream', () {
    test('emits a snapshot when status flips for a tracked server', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      // Pre-seed status (mirrors what addServer would do post-connect).
      m.updateServerStatus(ServerId('srv-1'), true);
      m.updateServerStatus(ServerId('srv-2'), false);
      m.updateServerStatus(ServerId('srv-1'), false); // change

      // Let the broadcast stream events drain.
      await Future<void>.delayed(Duration.zero);

      expect(emitted, hasLength(3));
      expect(emitted[0], {'srv-1': true});
      expect(emitted[1], {'srv-1': true, 'srv-2': false});
      expect(emitted[2], {'srv-1': false, 'srv-2': false});
    });

    test('repeated identical status is debounced (no extra emission)', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.updateServerStatus(ServerId('srv-1'), true);
      m.updateServerStatus(ServerId('srv-1'), true); // same value: no-op
      m.updateServerStatus(ServerId('srv-1'), true);

      await Future<void>.delayed(Duration.zero);
      expect(emitted, hasLength(1));
      expect(emitted.first, {'srv-1': true});
    });

    test('online/offline server-id getters reflect updateServerStatus', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('a'), true);
      m.updateServerStatus(ServerId('b'), false);
      m.updateServerStatus(ServerId('c'), true);

      expect(m.onlineServerIds.toSet(), {'a', 'c'});
      expect(m.offlineServerIds.toSet(), {'b'});
      expect(m.isServerOnline(ServerId('a')), isTrue);
      expect(m.isServerOnline(ServerId('b')), isFalse);
    });
  });

  group('refreshTokensForProfile', () {
    test('successful in-place Plex token refresh clears auth-error state', () async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);

      final m = MultiServerManager();
      addTearDown(m.dispose);

      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'old-token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('server-1'),
        serverName: 'Plex',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      m.debugRegisterClientForTesting(client, online: true);
      m.debugMarkAuthErrorForTesting(ServerId('server-1'));

      final bound = await m.refreshTokensForProfile(
        PlexAccountConnection(
          id: 'account-1',
          accountToken: 'account-token',
          clientIdentifier: 'client-id',
          accountLabel: 'Account',
          servers: [
            PlexServer(
              name: 'Plex',
              clientIdentifier: 'server-1',
              accessToken: 'new-token',
              connections: const [],
              owned: true,
            ),
          ],
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );

      expect(bound, {'server-1'});
      expect(m.authErrorServerIds, isNot(contains('server-1')));
      expect(client.config.token, 'new-token');
    });
  });

  group('Jellyfin connection updates', () {
    test('persists refreshed admin status discovered during health checks', () async {
      final persisted = <JellyfinConnection>[];
      final persistStarted = Completer<void>();
      final allowPersist = Completer<void>();
      final client = JellyfinClient.forTesting(
        connection: _jellyfinConnection('user-a'),
        httpClient: MockClient((request) async {
          expect(request.url.path, '/Users/Me');
          return http.Response(
            '{"Policy":{"IsAdministrator":true}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      addTearDown(client.close);
      final m = MultiServerManager()
        ..onJellyfinConnectionUpdated = (connection) async {
          persistStarted.complete();
          await allowPersist.future;
          persisted.add(connection);
        };
      addTearDown(m.dispose);
      m.debugRegisterJellyfinClientForTesting(client);

      final healthFuture = m.checkServerHealth();
      await persistStarted.future;
      expect(persisted, isEmpty);
      allowPersist.complete();
      await healthFuture;

      expect(persisted, hasLength(1));
      expect(persisted.single.isAdministrator, isTrue);
    });

    test('health remains online when persisting refreshed admin status fails', () async {
      final client = JellyfinClient.forTesting(
        connection: _jellyfinConnection('user-a'),
        httpClient: MockClient(
          (_) async =>
              http.Response('{"Policy":{"IsAdministrator":true}}', 200, headers: {'content-type': 'application/json'}),
        ),
      );
      addTearDown(client.close);
      final m = MultiServerManager()
        ..onJellyfinConnectionUpdated = (_) async {
          throw Exception('disk full');
        };
      addTearDown(m.dispose);
      m.debugRegisterJellyfinClientForTesting(client);

      await m.checkServerHealth();

      expect(m.isServerOnline(ServerId('jf-machine')), isTrue);
      expect(m.isOwnerOrAdmin(ServerId('jf-machine')), isTrue);
    });

    test('ignores stale admin-status persistence from a replaced Jellyfin client', () async {
      final persisted = <JellyfinConnection>[];
      final requestStarted = Completer<void>();
      final allowResponse = Completer<void>();
      final oldClient = JellyfinClient.forTesting(
        connection: _jellyfinConnection('user-a'),
        httpClient: MockClient((_) async {
          requestStarted.complete();
          await allowResponse.future;
          return http.Response(
            '{"Policy":{"IsAdministrator":true}}',
            200,
            headers: {'content-type': 'application/json'},
          );
        }),
      );
      final newClient = JellyfinClient.forTesting(
        connection: _jellyfinConnection('user-a').copyWith(accessToken: 'new-token'),
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(oldClient.close);
      final m = MultiServerManager()..onJellyfinConnectionUpdated = persisted.add;
      addTearDown(m.dispose);

      m.debugRegisterJellyfinClientForTesting(oldClient);
      final healthFuture = m.checkServerHealth();
      await requestStarted.future;
      m.debugRegisterJellyfinClientForTesting(newClient);
      allowResponse.complete();
      await healthFuture;

      expect(persisted, isEmpty);
      expect(m.getJellyfinClientByCompoundId('jf-machine/user-a'), same(newClient));
    });

    test('ignores stale health status when active Jellyfin user changes mid-check', () async {
      final requestStarted = Completer<void>();
      final allowResponse = Completer<void>();
      final userA = JellyfinClient.forTesting(
        connection: _jellyfinConnection('user-a'),
        httpClient: MockClient((_) async {
          requestStarted.complete();
          await allowResponse.future;
          return http.Response('', 403);
        }),
      );
      final userB = _jellyfinClient('user-b');
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.debugRegisterJellyfinClientForTesting(userA);
      final healthFuture = m.checkServerHealth();
      await requestStarted.future;
      m.debugRegisterJellyfinClientForTesting(userB, online: true);
      allowResponse.complete();
      await healthFuture;

      expect(m.getClient(ServerId('jf-machine')), same(userB));
      expect(m.isServerOnline(ServerId('jf-machine')), isTrue);
      expect(m.authErrorServerIds, isNot(contains('jf-machine')));
    });
  });

  // ============================================================
  // removeServer
  // ============================================================

  group('removeServer', () {
    test('removes a tracked server\'s status entry and emits a snapshot', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('srv-1'), true);
      m.updateServerStatus(ServerId('srv-2'), true);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.removeServer(ServerId('srv-1'));
      await Future<void>.delayed(Duration.zero);

      expect(m.serverIds, isNot(contains('srv-1')));
      expect(emitted, isNotEmpty);
      expect(emitted.last, {'srv-2': true});
    });

    test('removing an unknown id still emits a snapshot (does not throw)', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.removeServer(ServerId('never-added'));
      await Future<void>.delayed(Duration.zero);

      // Doesn't throw; state stays empty; one snapshot fires.
      expect(m.serverIds, isEmpty);
      expect(emitted, hasLength(1));
      expect(emitted.first, isEmpty);
    });

    test('removing a Jellyfin machine clears every scoped user client', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.debugRegisterJellyfinClientForTesting(_jellyfinClient('user-a'));
      m.debugRegisterJellyfinClientForTesting(_jellyfinClient('user-b'));

      expect(m.getJellyfinClientByCompoundId('jf-machine/user-a'), isNotNull);
      expect(m.getJellyfinClientByCompoundId('jf-machine/user-b'), isNotNull);

      m.removeServer(ServerId('jf-machine'));

      expect(m.getClient(ServerId('jf-machine')), isNull);
      expect(m.getJellyfinClientByCompoundId('jf-machine/user-a'), isNull);
      expect(m.getJellyfinClientByCompoundId('jf-machine/user-b'), isNull);
    });
  });

  // ============================================================
  // disconnectAll
  // ============================================================

  group('disconnectAll', () {
    test('clears all status and emits an empty snapshot', () async {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.updateServerStatus(ServerId('a'), true);
      m.updateServerStatus(ServerId('b'), false);

      final emitted = <Map<String, bool>>[];
      final sub = m.statusStream.listen(emitted.add);
      addTearDown(sub.cancel);

      m.disconnectAll();
      await Future<void>.delayed(Duration.zero);

      expect(m.serverIds, isEmpty);
      expect(m.onlineServerIds, isEmpty);
      expect(m.offlineServerIds, isEmpty);
      expect(emitted.last, isEmpty);
    });

    test('clears inactive Jellyfin scoped clients', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);

      m.debugRegisterJellyfinClientForTesting(_jellyfinClient('user-a'));
      m.debugRegisterJellyfinClientForTesting(_jellyfinClient('user-b'));

      m.disconnectAll();

      expect(m.getClient(ServerId('jf-machine')), isNull);
      expect(m.getJellyfinClientByCompoundId('jf-machine/user-a'), isNull);
      expect(m.getJellyfinClientByCompoundId('jf-machine/user-b'), isNull);
    });
  });

  // ============================================================
  // dispose
  // ============================================================

  group('dispose', () {
    test('disposing without connectivity monitoring does not throw', () {
      final m = MultiServerManager();
      // No startNetworkMonitoring call → _connectivitySubscription is null.
      // dispose() must handle the null-subscription path cleanly.
      expect(m.dispose, returnsNormally);
    });

    test('dispose closes the status stream (existing subscribers get onDone)', () async {
      final m = MultiServerManager();
      var done = false;
      final sub = m.statusStream.listen((_) {}, onDone: () => done = true);
      m.dispose();
      // Allow the close event to propagate.
      await Future<void>.delayed(Duration.zero);
      expect(done, isTrue);
      await sub.cancel();
    });
  });
  group('canManageServerMetadata', () {
    Future<MultiServerManager> plexManager({required bool owned}) async {
      final db = AppDatabase.forTesting(NativeDatabase.memory());
      PlexApiCache.initialize(db);
      addTearDown(db.close);
      final m = MultiServerManager();
      addTearDown(m.dispose);
      final client = PlexClient.forTesting(
        config: PlexConfig(
          baseUrl: 'https://plex.example',
          token: 'token',
          clientIdentifier: 'client-id',
          product: 'Plezy',
          version: '1.0.0',
        ),
        serverId: ServerId('server-1'),
        serverName: 'Plex',
        httpClient: MockClient((_) async => http.Response('{}', 200)),
      );
      m.debugRegisterClientForTesting(client, online: true);
      await m.refreshTokensForProfile(
        PlexAccountConnection(
          id: 'account-1',
          accountToken: 'account-token',
          clientIdentifier: 'account-client',
          accountLabel: 'Account',
          servers: [
            PlexServer(
              name: 'Plex',
              clientIdentifier: 'server-1',
              accessToken: 'token',
              connections: const [],
              owned: owned,
            ),
          ],
          createdAt: DateTime.fromMillisecondsSinceEpoch(0),
        ),
      );
      return m;
    }

    MultiServerManager jellyfinManager({required bool admin}) {
      final m = MultiServerManager();
      addTearDown(m.dispose);
      m.debugRegisterJellyfinClientForTesting(
        JellyfinClient.forTesting(
          connection: _jellyfinConnection('user-a').copyWith(isAdministrator: admin),
          httpClient: MockClient((_) async => http.Response('{}', 200)),
        ),
      );
      return m;
    }

    test('Plex owner may manage', () async {
      final m = await plexManager(owned: true);
      expect(m.canManageServerMetadata(ServerId('server-1')), isTrue);
    });

    test('Plex server shared with the account (not owned) may not', () async {
      final m = await plexManager(owned: false);
      expect(m.canManageServerMetadata(ServerId('server-1')), isFalse);
    });

    test('non-admin or restricted Plex Home member on an owned server may not', () async {
      final m = await plexManager(owned: true);
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      expect(m.canManageServerMetadata(ServerId('server-1')), isFalse);
      // Read-side probe keeps its own boundary.
      expect(m.isOwnerOrAdmin(ServerId('server-1')), isTrue);
    });

    test('restrictions are replaced, not accumulated, unless asked', () async {
      final m = await plexManager(owned: true);
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      m.setServerAuthorityRestrictions(serverIds: {'other'}, keepExisting: true);
      expect(m.canManageServerMetadata(ServerId('server-1')), isFalse);
      m.setServerAuthorityRestrictions();
      expect(m.canManageServerMetadata(ServerId('server-1')), isTrue);
    });

    test('Jellyfin administrator may manage, a regular user may not', () {
      expect(jellyfinManager(admin: true).canManageServerMetadata(ServerId('jf-machine')), isTrue);
      expect(jellyfinManager(admin: false).canManageServerMetadata(ServerId('jf-machine')), isFalse);
    });

    test('borrowed Jellyfin connection may not, even when the lender is admin', () {
      final m = jellyfinManager(admin: true);
      m.setServerAuthorityRestrictions(serverIds: {'jf-machine'});
      expect(m.canManageServerMetadata(ServerId('jf-machine')), isFalse);
    });

    Future<void> bindAccount(MultiServerManager m, {required String accountClientId, required bool owned}) =>
        m.refreshTokensForProfile(
          PlexAccountConnection(
            id: 'account-$accountClientId',
            accountToken: 'account-token-$accountClientId',
            clientIdentifier: accountClientId,
            accountLabel: accountClientId,
            servers: [
              PlexServer(
                name: 'Plex',
                clientIdentifier: 'server-1',
                accessToken: 'token-$accountClientId',
                connections: const [],
                owned: owned,
              ),
            ],
            createdAt: DateTime.fromMillisecondsSinceEpoch(0),
          ),
        );

    test('two Plex accounts on one server: bind order never opens rights to a borrower (closed side)', () async {
      // Own account sees the server as shared; the borrowed lender account
      // sees it as owned but is restricted. Whichever binds last, no owner
      // rights come out of the pair.
      for (final order in [
        ['own', 'lender'],
        ['lender', 'own'],
      ]) {
        final m = await plexManager(owned: false);
        m.setServerAuthorityRestrictions(plexAccountClientIds: {'lender'});
        for (final account in order) {
          await bindAccount(m, accountClientId: account, owned: account == 'lender');
        }
        expect(m.canManageServerMetadata(ServerId('server-1')), isFalse, reason: 'order $order');
      }
    });

    test('two Plex accounts on one server: the owner can miss rights when a borrowed row binds last', () async {
      final m = await plexManager(owned: false);
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'lender'});
      await bindAccount(m, accountClientId: 'own', owned: true);
      expect(m.canManageServerMetadata(ServerId('server-1')), isTrue);
      await bindAccount(m, accountClientId: 'lender', owned: true);
      // Known limit (last bind wins): closed, never a leak.
      expect(m.canManageServerMetadata(ServerId('server-1')), isFalse);
    });

    test('a non-admin Home member who owns a server is still restricted there (known boundary)', () async {
      // The restriction is per parent account, so it also covers a server the
      // member owns when it arrives through that account. Same as before this
      // change (the old isAdminActionAllowedForMediaItem blocked it too).
      final m = await plexManager(owned: true);
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      expect(m.canManageServerMetadata(ServerId('server-1')), isFalse);
    });

    test('Tautulli keeps its own admin probe: isOwnerOrAdmin ignores authority restrictions', () async {
      // Tautulli (settings tile, pollers, "Watched by") asks a different
      // question: is there a Plex server here whose admin data this account
      // may read. It stays on isOwnerOrAdmin on purpose; see the doc there.
      final m = await plexManager(owned: true);
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'}, serverIds: {'server-1'});
      expect(m.canManageServerMetadata(ServerId('server-1')), isFalse);
      expect(m.isOwnerOrAdmin(ServerId('server-1')), isTrue);
    });

    test('a change of restrictions emits a status event so owner-gated UI rebuilds', () async {
      final m = await plexManager(owned: true);
      final events = <Map<String, bool>>[];
      final sub = m.statusStream.listen(events.add);
      addTearDown(sub.cancel);
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      m.setServerAuthorityRestrictions(plexAccountClientIds: {'account-client'});
      await Future<void>.delayed(Duration.zero);
      expect(events, hasLength(1), reason: 'an unchanged set does not re-notify');
    });

    test('Pleya Server has no owner role yet and may not (PS-9)', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);
      final client = PleyaServerClient.create(
        PleyaServerConnection(
          id: 'pleyaServer.srv-1',
          baseUrl: 'http://nas.lan:8832',
          serverId: 'srv-1',
          serverName: 'Zolder',
          userName: 'michel',
          refreshToken: 'rt-1',
          createdAt: DateTime.utc(2026, 8, 19),
        ),
        httpClientFactory: () => MockClient((_) async => http.Response('{}', 200)),
      );
      addTearDown(client.close);
      m.debugRegisterClientForTesting(client);
      // Pinned to PS-9: even the bootstrap owner gets false until the server
      // exposes roles. When PS-9 lands, only `role == owner` may flip this.
      expect(
        m.canManageServerMetadata(ServerId('srv-1')),
        isFalse,
        reason: 'PS-9 not delivered: Pleya Server has no owner role yet',
      );
    });

    test('unknown server may not', () {
      final m = MultiServerManager();
      addTearDown(m.dispose);
      expect(m.canManageServerMetadata(ServerId('nope')), isFalse);
    });
  });
}
