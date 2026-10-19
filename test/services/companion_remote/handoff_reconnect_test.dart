import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/providers/companion_remote_provider.dart';
import 'package:pleya/services/companion_remote/companion_remote_peer_service.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';

void main() {
  group('reconnect during a profile switch on the host (A-23b)', () {
    test('without a switch the phone gives up after five attempts', () {
      expect(CompanionRemoteProvider.reconnectDelay(4, waitingForSwitch: false), const Duration(seconds: 16));
      expect(CompanionRemoteProvider.reconnectDelay(5, waitingForSwitch: false), isNull);
    });

    test('while a handoff waits for the switch it keeps trying every few seconds', () {
      for (final attempts in [0, 1, 2, 5, 12, 40]) {
        final delay = CompanionRemoteProvider.reconnectDelay(attempts, waitingForSwitch: true);
        expect(delay, isNotNull, reason: 'attempt $attempts');
        expect(delay!, lessThanOrEqualTo(const Duration(seconds: 4)));
      }
    });

    test('the attempts cover the whole switch budget, beyond the start deadline of the Apple TV', () {
      var waited = Duration.zero;
      var attempts = 0;
      final budget = PlaybackHandoffTracker().switchBudget;
      while (waited < budget) {
        final delay = CompanionRemoteProvider.reconnectDelay(attempts++, waitingForSwitch: true);
        if (delay == null) break;
        waited += delay;
      }
      expect(waited, greaterThanOrEqualTo(budget));
    });
  });

  group('host port after a profile switch (A-23b)', () {
    test('the preferred port is retried while the previous host still closes it', () async {
      final previous = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      final port = previous.port;
      Future<void>.delayed(const Duration(milliseconds: 300), () => previous.close(force: true));
      final server = await CompanionRemotePeerService.bindHostServer(port);
      addTearDown(() => server.close(force: true));
      expect(server.port, port);
    });

    test('a port that stays taken falls back to a random one', () async {
      final taken = await HttpServer.bind(InternetAddress.anyIPv4, 0);
      addTearDown(() => taken.close(force: true));
      final server = await CompanionRemotePeerService.bindHostServer(
        taken.port,
        attempts: 2,
        pause: const Duration(milliseconds: 10),
      );
      addTearDown(() => server.close(force: true));
      expect(server.port, isNot(taken.port));
    });
  });
}
