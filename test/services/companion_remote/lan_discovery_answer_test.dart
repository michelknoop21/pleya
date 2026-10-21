import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/companion_remote/remote_auth_context.dart';
import 'package:pleya/services/companion_remote/lan_discovery_service.dart';

Map<String, dynamic> _beacon({String app = 'pleya', String platform = 'tvOS', String clientId = 'tv-1'}) => {
  'app': app,
  'platform': platform,
  'clientId': clientId,
};

void main() {
  group('LanDiscoveryService.shouldAnswerBeacon (A-23d: een iPhone antwoordt de Apple TV)', () {
    test('beantwoordt de beacon van een Apple TV', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(), ownClientIds: {'phone-1'}), isTrue);
    });

    test('beantwoordt zijn eigen beacon niet', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(clientId: 'phone-1'), ownClientIds: {'phone-1'}), isFalse);
    });

    test('beantwoordt geen ander apparaat dan een Apple TV', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(platform: 'iOS'), ownClientIds: {'phone-1'}), isFalse);
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(platform: 'macOS'), ownClientIds: {'phone-1'}), isFalse);
    });

    test('negeert pakketten van een andere app', () {
      expect(LanDiscoveryService.shouldAnswerBeacon(_beacon(app: 'other'), ownClientIds: {'phone-1'}), isFalse);
    });
  });

  group('LanDiscoveryService antwoordsocket', () {
    const context = RemoteAuthContext(
      id: 'ctx',
      backend: 'plex',
      connectionId: 'conn',
      homeSecret: [1, 2, 3],
      discoveryKey: [4, 5, 6, 7],
      clientIdentifier: 'phone-1',
      userUuid: 'u',
      allowedUserUuids: [],
    );

    Future<void> start(LanDiscoveryService service) => service.startBroadcastingForContexts(
      contexts: const [context],
      deviceName: 'iPhone',
      platform: 'iOS',
      wsPort: 48632,
      ips: const ['127.0.0.1'],
      answerBeacons: true,
    );

    testWidgets('een bind die na stop en een nieuwe start klaarkomt lekt geen socket op de discoverypoort', (
      tester,
    ) async {
      await tester.runAsync(() async {
        final service = LanDiscoveryService();
        addTearDown(service.dispose);

        // Stop and start again without waiting: the first bind is still pending
        // when the second start has re-armed the timer.
        await start(service);
        unawaited(service.stopBroadcasting());
        await start(service);
        await service.stopBroadcasting();
        await Future<void>.delayed(const Duration(milliseconds: 500));

        // Nothing may still hold the port: an exclusive bind only succeeds then.
        final probe = await RawDatagramSocket.bind(InternetAddress.anyIPv4, LanDiscoveryService.discoveryPort);
        probe.close();
      });
    });
  });
}
