import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/companion_remote_peer_service.dart';

import '../test_helpers/prefs.dart';

// A-23d: an iPhone listens for Pleya Fly as a handoff-only host. Joining an
// Apple TV as a client (a fly the other way, or the remote) must not overwrite
// that host's peer service, and when the client session ends, however it ends,
// the host must come back; otherwise the A-23 sheet refuses every fly and the
// phone stops listening until Pleya restarts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);
  tearDown(() => CompanionRemotePeerService.debugBindDelay = Duration.zero);

  Future<CompanionRemoteProvider> phone({bool disposeOnTearDown = true}) async {
    final p = CompanionRemoteProvider();
    if (disposeOnTearDown) {
      addTearDown(() async {
        await p.stopHostServer();
        p.dispose();
      });
    }
    final ok = await p.initializeJellyfinCrypto(
      connection: JellyfinConnection(
        id: 'srv-1',
        baseUrl: 'https://jellyfin.local',
        serverName: 'Home',
        serverMachineId: 'jf-machine-1',
        userId: 'user-1',
        userName: 'michel',
        accessToken: 'tok-1',
        deviceId: 'dev-1',
        createdAt: DateTime.fromMillisecondsSinceEpoch(1000000),
      ),
      activeProfile: null,
    );
    expect(ok, isTrue);
    return p;
  }

  Future<CompanionRemoteProvider> listening() async {
    final p = await phone();
    expect(await p.requestHandoffOnlyHost(), isTrue);
    await p.startHostServer(handoffOnly: true);
    expect(p.isHandoffOnlyHost, isTrue);
    return p;
  }

  /// Nothing listens on port 1: the join fails, as an unreachable Apple TV would.
  DiscoveredHost unreachableTv(CompanionRemoteProvider p) => DiscoveredHost(
    authContextId: p.debugAuthContextId!,
    clientId: 'tv-1',
    name: 'Woonkamer',
    platform: 'tvOS',
    port: 1,
    ips: const ['127.0.0.1'],
  );

  Future<bool> portIsFree(int port) async {
    try {
      final socket = await ServerSocket.bind(InternetAddress.anyIPv4, port);
      await socket.close();
      return true;
    } on SocketException {
      return false;
    }
  }

  Future<void> eventually(bool Function() condition) async {
    for (var i = 0; i < 100 && !condition(); i++) {
      await Future<void>.delayed(const Duration(milliseconds: 50));
    }
  }

  test('a handoff-only host says so; a full host does not', () async {
    final p = await listening();
    expect(await p.requestHandoffOnlyHost(), isFalse, reason: 'it already runs');

    await p.stopHostServer();
    await p.startHostServer();
    expect(p.isHostServerRunning, isTrue);
    expect(p.isHandoffOnlyHost, isFalse);
    await p.stopHandoffOnlyHost();
    expect(p.isHostServerRunning, isTrue, reason: 'stopping the fly listener leaves a full host alone');
  });

  test('a handoff-only host never shows as connected; a full host does', () async {
    final p = await listening();
    expect(p.isConnected, isFalse, reason: 'the Verbonden dot on the iPad would burn for good');

    await p.stopHostServer();
    await p.startHostServer();
    expect(p.isConnected, isTrue);
  });

  for (final (name, join) in [
    ('connectToManualHost', (CompanionRemoteProvider p, DiscoveredHost tv) => p.connectToManualHost('127.0.0.1:1')),
    ('connectToDiscoveredHost', (CompanionRemoteProvider p, DiscoveredHost tv) => p.connectToDiscoveredHost(tv)),
  ]) {
    test('$name stops the host before joining and leaving brings it back', () async {
      final p = await listening();
      final port = p.debugHostPort!;

      await expectLater(join(p, unreachableTv(p)), throwsA(anything));
      expect(p.isHostServerRunning, isFalse, reason: 'the client took over the peer service');
      expect(await portIsFree(port), isTrue, reason: 'the old host server must be closed, not leaked');

      await p.leaveSession();
      expect(p.isHandoffOnlyHost, isTrue);
    });
  }

  test('a failed join without a leave is cleared on the next resume', () async {
    final p = await listening();
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));

    expect(await p.requestHandoffOnlyHost(), isTrue, reason: 'a dead client session must not block the host');
    await p.startHostServer(handoffOnly: true);
    expect(p.isHandoffOnlyHost, isTrue);
  });

  test('Cancel on a reconnect brings the host back', () async {
    final p = await listening();
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));

    p.cancelReconnect();
    await eventually(() => p.isHandoffOnlyHost);
    expect(p.isHandoffOnlyHost, isTrue);
  });

  test('a phone that stopped listening does not come back after leaving', () async {
    final p = await listening();
    await p.stopHandoffOnlyHost();
    expect(p.isHostServerRunning, isFalse);

    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));
    await p.leaveSession();
    p.cancelReconnect();
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(p.isHostServerRunning, isFalse);
  });

  test('a disposed provider binds no host', () async {
    final p = await phone(disposeOnTearDown: false);
    p.dispose();
    await p.startHostServer(handoffOnly: true);
    expect(p.isHostServerRunning, isFalse);
  });

  test('no host starts while a client session holds the peer service', () async {
    final p = await listening();
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));

    await p.startHostServer(handoffOnly: true);
    expect(p.isHostServerRunning, isFalse, reason: 'the client channel would be taken over');
    expect(p.isRemote, isTrue);
  });

  test('a leave and a join that overlap leave no orphan server behind', () async {
    final baseline = CompanionRemotePeerService.debugLiveHostServers;
    final p = await listening();
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));

    // The user leaves and joins again within the two seconds a close may take.
    final leave = p.leaveSession();
    final join = expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));
    await leave;
    await join;
    await p.leaveSession();
    expect(p.isHandoffOnlyHost, isTrue);

    await p.stopHostServer();
    expect(CompanionRemotePeerService.debugLiveHostServers, baseline, reason: 'every bound server was closed');
  });

  test('giving up on a lost Apple TV brings the host back', () async {
    final tv = await phone();
    await tv.startHostServer();
    final port = tv.debugHostPort!;
    final p = await listening();
    p.debugReconnectDelay = (_) => null;

    await p.connectToManualHost('127.0.0.1:$port');
    expect(p.isRemote, isTrue);
    expect(p.isConnected, isTrue);

    await tv.stopHostServer();
    await eventually(() => p.isHandoffOnlyHost);
    expect(p.isHandoffOnlyHost, isTrue);
  });

  test('a host stopped while it still binds leaves no server behind', () async {
    final baseline = CompanionRemotePeerService.debugLiveHostServers;
    final p = await phone();
    await p.requestHandoffOnlyHost();
    CompanionRemotePeerService.debugBindDelay = const Duration(milliseconds: 300);
    final starting = p.startHostServer(handoffOnly: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await p.stopHostServer();
    await starting;

    expect(p.isHostServerRunning, isFalse);
    expect(CompanionRemotePeerService.debugLiveHostServers, baseline, reason: 'the late bind was closed, not orphaned');
  });

  test('a host restored while a join still closes the old channel gives way to that join', () async {
    final baseline = CompanionRemotePeerService.debugLiveHostServers;
    final p = await listening();
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));

    // The leave closes the failed channel (bounded at 2 s) and then restores
    // the host; the join, 100 ms later, waits on the same close and finishes
    // after that restore, so it finds a running host it must stop first.
    final leave = p.leaveSession();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    final join = expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));
    await leave;
    await join;

    expect(p.isRemote, isTrue, reason: 'the join is the session now');
    expect(p.isHostServerRunning, isFalse);
    await p.leaveSession();
    await p.stopHostServer();
    expect(CompanionRemotePeerService.debugLiveHostServers, baseline, reason: 'the restored host was closed');
  });

  test('a pause while the fly host still binds leaves nothing running', () async {
    final baseline = CompanionRemotePeerService.debugLiveHostServers;
    final p = await phone();
    await p.requestHandoffOnlyHost();
    CompanionRemotePeerService.debugBindDelay = const Duration(milliseconds: 300);
    final starting = p.startHostServer(handoffOnly: true);
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await p.stopHandoffOnlyHost();
    await starting;

    expect(p.isHostServerRunning, isFalse, reason: 'iOS would take the socket; the provider must not think it runs');
    expect(CompanionRemotePeerService.debugLiveHostServers, baseline);
    expect(p.canStartHandoffOnlyHost, isFalse);
  });

  test('a slow leave does not tear down the session of a join that came after it', () async {
    final tv = await phone();
    await tv.startHostServer();
    final port = tv.debugHostPort!;
    final p = await listening();
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));

    // The failed channel takes up to 2 s to close; the user joins the Apple TV meanwhile.
    final leave = p.leaveSession();
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await p.connectToManualHost('127.0.0.1:$port');
    await leave;

    expect(p.isRemote, isTrue);
    expect(p.isConnected, isTrue, reason: 'the old leave must not clear the new session');
    expect(p.isHostServerRunning, isFalse, reason: 'no host restored under the new client session');
  });

  test('two host starts at once bind one server', () async {
    final baseline = CompanionRemotePeerService.debugLiveHostServers;
    final p = await phone();
    await p.requestHandoffOnlyHost();
    CompanionRemotePeerService.debugBindDelay = const Duration(milliseconds: 200);
    await Future.wait([p.startHostServer(handoffOnly: true), p.startHostServer(handoffOnly: true)]);
    expect(CompanionRemotePeerService.debugLiveHostServers, baseline + 1);
    await p.stopHostServer();
    expect(CompanionRemotePeerService.debugLiveHostServers, baseline);
  });
}
