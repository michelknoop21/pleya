import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/providers/companion_remote_provider.dart';

import '../test_helpers/prefs.dart';

// A-23d: an iPhone listens for Pleya Fly as a handoff-only host. Joining an
// Apple TV as a client (a fly the other way, or the remote) must not overwrite
// that host's peer service, and when the client session ends, however it ends,
// the host must come back; otherwise the A-23 sheet refuses every fly and the
// phone stops listening until Pleya restarts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

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
}
