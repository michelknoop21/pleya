import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/services/jellyfin_client.dart';
import 'package:pleya/services/plex_auth_service.dart';
import 'package:pleya/media/ids.dart';
import 'package:pleya/media/media_server_client.dart';
import 'package:pleya/services/multi_server_manager.dart';

import '../test_helpers/prefs.dart';

/// A server whose health probe the test decides — including when it answers.
/// The interesting window is exactly the one a hanging probe opens: the user
/// gives up on a server that is not responding and disconnects it while the
/// request they are waiting for is still out.
class _ProbeClient implements MediaServerClient {
  _ProbeClient(String id, {this.status = HealthStatus.online}) : serverId = ServerId(id);

  @override
  final ServerId serverId;

  @override
  String? get serverName => 'Server $serverId';

  HealthStatus status;

  /// When set, [checkHealth] waits on it. Complete it to let the probe land.
  Completer<void>? gate;

  int probes = 0;
  bool closed = false;

  @override
  Future<HealthStatus> checkHealth() async {
    probes++;
    final pending = gate;
    if (pending != null) await pending.future;
    return status;
  }

  @override
  void close() => closed = true;

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

PlexAccountConnection _plexAccount(List<String> serverIds) => PlexAccountConnection(
  id: 'plex-account',
  accountToken: 'account-token',
  clientIdentifier: 'client-1',
  accountLabel: 'Plex',
  servers: [
    for (final id in serverIds)
      PlexServer(
        name: 'Server $id',
        clientIdentifier: id,
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
  createdAt: DateTime.fromMillisecondsSinceEpoch(0),
);

void main() {
  setUp(resetSharedPreferencesForTest);

  group('a disconnect while a probe is in flight', () {
    test('a late health result cannot put a removed server back', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final client = _ProbeClient('srv-1')..gate = Completer<void>();
      manager.debugRegisterClientForTesting(client);
      expect(manager.serverIds, contains('srv-1'));

      // The sweep starts and blocks on the probe.
      final sweep = manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);
      expect(client.probes, 1);

      // The user disconnects the server that is not answering.
      manager.removeServer(ServerId('srv-1'));
      expect(manager.serverIds, isEmpty);

      // The probe finally lands, long after the connection stopped existing.
      client.gate!.complete();
      await sweep;

      expect(manager.serverIds, isEmpty, reason: 'a late probe must not re-register a disconnected server');
      expect(manager.onlineServerIds, isEmpty);
      expect(manager.offlineServerIds, isEmpty);
    });

    test('a late auth-rejected result cannot raise the banner for a removed server', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final client = _ProbeClient('srv-1', status: HealthStatus.authError)..gate = Completer<void>();
      manager.debugRegisterClientForTesting(client);

      final sweep = manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      manager.removeServer(ServerId('srv-1'));
      client.gate!.complete();
      await sweep;

      expect(
        manager.authErrorServerIds,
        isEmpty,
        reason: 'a "session expired" banner for a connection the user just deleted has nothing to point at',
      );
    });

    test('a server disconnected while its banner was already up loses the banner with it', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final client = _ProbeClient('srv-1', status: HealthStatus.authError);
      manager.debugRegisterClientForTesting(client, online: false);
      manager.debugMarkAuthErrorForTesting(ServerId('srv-1'));
      expect(manager.authErrorServerIds, contains('srv-1'));

      manager.removeServer(ServerId('srv-1'));

      expect(manager.authErrorServerIds, isEmpty);
      expect(manager.serverIds, isEmpty);
    });

    test('re-adding the same id does not inherit the old probe\'s answer', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final stale = _ProbeClient('srv-1', status: HealthStatus.authError)..gate = Completer<void>();
      manager.debugRegisterClientForTesting(stale);
      final sweep = manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      manager.removeServer(ServerId('srv-1'));
      // The user reconnects the same server before the old probe returns.
      final fresh = _ProbeClient('srv-1');
      manager.debugRegisterClientForTesting(fresh);

      stale.gate!.complete();
      await sweep;

      expect(manager.authErrorServerIds, isEmpty, reason: 'the old session\'s verdict does not apply to the new one');
      expect(manager.onlineServerIds, contains('srv-1'));
    });
  });

  group('one server down, the others usable', () {
    test('disconnecting the failing server leaves the healthy one online and registered', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final healthy = _ProbeClient('srv-ok');
      final broken = _ProbeClient('srv-bad', status: HealthStatus.authError)..gate = Completer<void>();
      manager.debugRegisterClientForTesting(healthy);
      manager.debugRegisterClientForTesting(broken);

      final sweep = manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      manager.removeServer(ServerId('srv-bad'));
      broken.gate!.complete();
      await sweep;

      expect(manager.serverIds, ['srv-ok']);
      expect(manager.onlineServerIds, contains('srv-ok'));
      expect(manager.authErrorServerIds, isEmpty);
      expect(manager.getClient(ServerId('srv-ok')), same(healthy));
      expect(healthy.closed, isFalse, reason: 'the healthy connection is untouched by its neighbour going away');
    });

    test('one server failing its probe does not mark the other offline', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(_ProbeClient('srv-ok'));
      manager.debugRegisterClientForTesting(_ProbeClient('srv-bad', status: HealthStatus.offline));

      await manager.checkServerHealth();

      expect(manager.onlineServerIds, ['srv-ok']);
      expect(manager.offlineServerIds, ['srv-bad']);
    });
  });

  group('an expired session is not a transport problem', () {
    test('automatic sweeps leave auth-rejected servers alone', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(_ProbeClient('srv-auth', status: HealthStatus.authError), online: false);
      manager.debugRegisterClientForTesting(_ProbeClient('srv-down', status: HealthStatus.offline), online: false);
      await manager.checkServerHealth();

      expect(manager.authErrorServerIds, ['srv-auth']);
      expect(
        manager.reconnectCandidateServerIds(forceRediscovery: false),
        ['srv-down'],
        reason: 'retrying a rejected token on every resume is the reconnect storm, and it can never succeed',
      );
    });

    test('the user asking for a reconnect still includes them', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(_ProbeClient('srv-auth', status: HealthStatus.authError), online: false);
      await manager.checkServerHealth();

      expect(manager.reconnectCandidateServerIds(forceRediscovery: true), ['srv-auth']);
    });

    test('a probe that succeeds again clears the auth state without a restart', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final client = _ProbeClient('srv-1', status: HealthStatus.authError);
      manager.debugRegisterClientForTesting(client, online: false);
      await manager.checkServerHealth();
      expect(manager.authErrorServerIds, ['srv-1']);

      client.status = HealthStatus.online;
      await manager.checkServerHealth();

      expect(manager.authErrorServerIds, isEmpty);
      expect(manager.onlineServerIds, ['srv-1']);
    });
  });

  group('a stale Jellyfin probe leaves no trace', () {
    test('a late probe does not resurrect the per-user health of a removed machine', () async {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      final connection = JellyfinConnection(
        id: 'jf-machine/user-a',
        baseUrl: 'https://jf.example.com',
        serverName: 'Zolder',
        serverMachineId: 'jf-machine',
        userId: 'user-a',
        userName: 'user-a',
        accessToken: 'token',
        deviceId: 'device',
        createdAt: DateTime.fromMillisecondsSinceEpoch(0),
      );
      final gate = Completer<void>();
      final client = JellyfinClient.forTesting(
        connection: connection,
        httpClient: MockClient((_) async {
          await gate.future;
          return http.Response('{}', 401);
        }),
      );
      manager.debugRegisterJellyfinClientForTesting(client);

      final sweep = manager.checkServerHealth();
      await Future<void>.delayed(Duration.zero);

      manager.removeJellyfinConnection(connection);
      expect(manager.getJellyfinHealthForConnection(connection.id), isNull);

      gate.complete();
      await sweep;

      expect(
        manager.getJellyfinHealthForConnection(connection.id),
        isNull,
        reason: 'a probe that outlived the disconnect must not write a health row back for it',
      );
      expect(manager.serverIds, isEmpty);
    });
  });

  group('an expired session and a flapping network', () {
    test('a connectivity sweep does not race endpoints for an auth-rejected server', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      // Both servers land in _plexServers as auth-rejected, then one of them
      // gets its session back: offline, but for an ordinary transport reason.
      manager.markPlexConnectionAuthError(_plexAccount(const ['srv-auth', 'srv-down']));
      manager.updateServerStatus(ServerId('srv-down'), false);

      expect(manager.authErrorServerIds, ['srv-auth']);
      expect(
        manager.reoptimizeCandidateServerIds().toSet(),
        {'srv-down'},
        reason: 'the connectivity path has to skip the same servers the reconnect sweep skips',
      );
      expect(manager.reconnectCandidateServerIds(forceRediscovery: false).toSet(), {'srv-down'});
    });
  });

  group('tearing everything down', () {
    test('the share poll starts over at its initial delay after a full disconnect', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      manager.debugSetSharePollDelayForTesting(const Duration(minutes: 3));
      manager.disconnectAll();

      expect(
        manager.debugSharePollDelay,
        MultiServerManager.sharePollInitialDelay,
        reason: 'a backed-off delay carried into the next session makes recovery minutes slower than intended',
      );
    });
  });

  group('ownership tokens', () {
    test('a token stops matching once the server is removed', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(_ProbeClient('srv-1'));
      final token = manager.generationFor(ServerId('srv-1'));
      expect(manager.ownsGeneration(ServerId('srv-1'), token), isTrue);

      manager.removeServer(ServerId('srv-1'));

      expect(manager.ownsGeneration(ServerId('srv-1'), token), isFalse);
    });

    test('a re-added server gets a different token', () {
      final manager = MultiServerManager();
      addTearDown(manager.dispose);

      manager.debugRegisterClientForTesting(_ProbeClient('srv-1'));
      final first = manager.generationFor(ServerId('srv-1'));
      manager.removeServer(ServerId('srv-1'));
      manager.debugRegisterClientForTesting(_ProbeClient('srv-1'));
      final second = manager.generationFor(ServerId('srv-1'));

      expect(second, isNot(first));
      expect(manager.ownsGeneration(ServerId('srv-1'), first), isFalse);
      expect(manager.ownsGeneration(ServerId('srv-1'), second), isTrue);
    });
  });
}
