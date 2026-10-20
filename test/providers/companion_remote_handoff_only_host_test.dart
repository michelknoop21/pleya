import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/connection/connection.dart';
import 'package:pleya/providers/companion_remote_provider.dart';

import '../test_helpers/prefs.dart';

// A-23d: an iPhone listens for Pleya Fly as a handoff-only host. Joining an
// Apple TV as a client (a fly the other way, or the remote) must not overwrite
// that host's peer service, and leaving must bring the host back; otherwise
// the A-23 sheet refuses every fly and the phone stops listening until Pleya
// restarts.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(resetSharedPreferencesForTest);

  Future<CompanionRemoteProvider> phone() async {
    final p = CompanionRemoteProvider();
    addTearDown(() async {
      await p.stopHostServer();
      p.dispose();
    });
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

  test('a handoff-only host says so; a full host does not', () async {
    final p = await phone();
    expect(p.requestHandoffOnlyHost(), isTrue);
    await p.startHostServer(handoffOnly: true);
    expect(p.isHandoffOnlyHost, isTrue);
    expect(p.requestHandoffOnlyHost(), isFalse, reason: 'it already runs');

    await p.stopHostServer();
    await p.startHostServer();
    expect(p.isHostServerRunning, isTrue);
    expect(p.isHandoffOnlyHost, isFalse);
    await p.stopHandoffOnlyHost();
    expect(p.isHostServerRunning, isTrue, reason: 'stopping the fly listener leaves a full host alone');
  });

  test('joining a host gives way, leaving brings the handoff-only host back', () async {
    final p = await phone();
    p.requestHandoffOnlyHost();
    await p.startHostServer(handoffOnly: true);

    // Nothing listens on port 1: the join fails, as an unreachable Apple TV would.
    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));
    expect(p.isHostServerRunning, isFalse, reason: 'the client took over the peer service');
    expect(p.requestHandoffOnlyHost(), isFalse, reason: 'no host while a client session exists');

    await p.leaveSession();
    expect(p.isHandoffOnlyHost, isTrue);
  });

  test('a phone that stopped listening does not come back after leaving', () async {
    final p = await phone();
    p.requestHandoffOnlyHost();
    await p.startHostServer(handoffOnly: true);
    await p.stopHandoffOnlyHost();
    expect(p.isHostServerRunning, isFalse);

    await expectLater(p.connectToManualHost('127.0.0.1:1'), throwsA(anything));
    await p.leaveSession();
    expect(p.isHostServerRunning, isFalse);
  });
}
