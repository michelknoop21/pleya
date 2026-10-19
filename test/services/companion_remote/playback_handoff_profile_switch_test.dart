import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_profile_switch.dart';
import 'package:pleya/services/companion_remote/playback_handoff_receiver.dart';

PlaybackHandoffRequest _request(String id) => PlaybackHandoffRequest(
  id: id,
  serverId: 'server_1',
  itemId: 'item_9',
  positionMs: 226000,
  title: 'Big Buck Bunny',
  from: 'iPhone van Anna',
);

final _anna = Profile.plexHome(
  id: 'plex-anna',
  displayName: 'Anna',
  parentConnectionId: 'plex-1',
  plexHomeUserUuid: 'u-anna',
  plexProtected: true,
  createdAt: DateTime(2026),
);

void main() {
  late DateTime now;
  late PlaybackHandoffLedger ledger;
  late List<String> events;

  setUp(() {
    now = DateTime(2026, 10, 20, 20);
    ledger = PlaybackHandoffLedger(clock: () => now);
    events = [];
  });

  /// [pin] stands in for the PIN dialog: it returns whether the PIN was
  /// accepted, after which the real activation asks `mayActivate`.
  Future<void> run(String id, {Future<bool> Function()? pin, Duration sendDelay = Duration.zero}) =>
      runHandoffProfileSwitch(
        request: _request(id),
        target: _anna,
        ledger: ledger,
        send: (data) => events.add('send $data'),
        activate: (mayActivate) async {
          events.add('dialog armed=${ledger.isArmed}');
          if (!await (pin ?? () async => true)()) return false;
          final allowed = mayActivate();
          events.add('activate $allowed');
          return allowed;
        },
        sendDelay: sendDelay,
      );

  group('runHandoffProfileSwitch', () {
    test('the phone hears the switch first, and the request is armed before the profile activates', () async {
      await run('h1');
      expect(events, [
        'send {$handoffSwitchingKey: h1, $handoffProfileKey: Anna, $handoffPinKey: true}',
        'dialog armed=true',
        'activate true',
      ]);
      // No answer yet: the new session plays it and answers.
      expect(ledger.takeFor('plex-anna')?.id, 'h1');
    });

    test('a cancelled PIN leaves nothing armed and tells the phone the PIN was not entered', () async {
      await run('h1', pin: () async => false);
      expect(ledger.isArmed, isFalse);
      expect(events.last, 'send {$handoffFailedKey: h1, $handoffReasonKey: $handoffReasonPinCancelled}');
      expect(handoffQueryReply(ledger, 'h1'), {handoffFailedKey: 'h1', handoffReasonKey: handoffReasonPinCancelled});
    });

    test('a long PIN dialog still switches, and the start window begins at the PIN', () async {
      await run(
        'h1',
        pin: () async {
          now = now.add(const Duration(seconds: 55));
          return true;
        },
      );
      expect(events.last, 'activate true');
      now = now.add(const Duration(seconds: 20));
      expect(ledger.takeFor('plex-anna')?.id, 'h1');
    });

    test('a PIN entered after the PIN wait does not switch', () async {
      await run(
        'h1',
        pin: () async {
          now = now.add(PlaybackHandoffLedger.pinWait + const Duration(seconds: 1));
          return true;
        },
      );
      expect(events, contains('activate false'));
      expect(events.last, 'send {$handoffFailedKey: h1, $handoffReasonKey: $handoffReasonPinCancelled}');
      expect(ledger.isArmed, isFalse);
    });

    test('a PIN entered after the phone cancelled does not switch', () async {
      await run(
        'a23b-cancelled',
        pin: () async {
          cancelPlaybackHandoff('a23b-cancelled');
          return true;
        },
      );
      expect(events, contains('activate false'));
      expect(ledger.isArmed, isFalse);
    });

    test('a second handoff during a switch is refused without a second dialog', () async {
      ledger.arm(_request('h1'), 'plex-anna');
      await run('h2');
      expect(events, ['send {$handoffFailedKey: h2}']);
      ledger.mayActivate('h1');
      expect(ledger.takeFor('plex-anna')?.id, 'h1', reason: 'the first switch keeps its request');
    });

    test('two handoffs at once: the second meets the guard before the first waits', () async {
      await Future.wait([
        run('h1', sendDelay: const Duration(milliseconds: 30)),
        run('h2', sendDelay: const Duration(milliseconds: 30)),
      ]);
      expect(events.where((e) => e.startsWith('dialog')), hasLength(1));
      expect(events, contains('send {$handoffFailedKey: h2}'));
    });
  });

  group('runPendingHandoffResume', () {
    late List<String> reported;
    late List<String> received;

    setUp(() {
      reported = [];
      received = [];
      ledger
        ..arm(_request('h1'), 'plex-anna')
        ..mayActivate('h1');
    });

    Future<void> resume({required Future<bool> Function() binding}) => runPendingHandoffResume(
      ledger: ledger,
      profileId: 'plex-anna',
      awaitBinding: binding,
      report: (id, outcome) => reported.add('$id $outcome'),
      receive: (request) async => received.add(request.id),
    );

    test('plays once the servers are bound', () async {
      await resume(binding: () async => true);
      expect(received, ['h1']);
      expect(reported, isEmpty);
    });

    test('a binding that outlasts the start window does not start: the phone has given up', () async {
      await resume(
        binding: () async {
          now = now.add(PlaybackHandoffLedger.startWindow + const Duration(seconds: 1));
          return true;
        },
      );
      expect(received, isEmpty);
      expect(reported, ['h1 ${PlaybackHandoffOutcome.failed}']);
    });
  });
}
