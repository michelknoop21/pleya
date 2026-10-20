import 'dart:async';

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

bool _always() => true;

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
  /// accepted, after which the real activation asks `mayActivate`. [proof]
  /// stands in for the plex.tv check of the phone's token (A-23c). A [pin] that
  /// returns false is the user cancelling the dialog. [activation] is what the
  /// real `active.activate` would return once the PIN and `mayActivate` pass.
  Future<void> run(
    String id, {
    Future<bool> Function()? pin,
    Future<String?> Function()? proof,
    Profile? target,
    Duration sendDelay = Duration.zero,
    bool Function() activation = _always,
  }) => runHandoffProfileSwitch(
    request: _request(id),
    target: target ?? _anna,
    ledger: ledger,
    send: (data) => events.add('send $data'),
    verifyProof: proof,
    activate: (mayActivate, verifiedToken, onPinCancelled) async {
      if (verifiedToken != null) {
        events.add('token $verifiedToken');
      } else {
        events.add('dialog armed=${ledger.isArmed}');
        if (!await (pin ?? () async => true)()) {
          onPinCancelled();
          return false;
        }
      }
      final allowed = mayActivate();
      events.add('activate $allowed');
      return allowed && activation();
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

    test('a PIN entered after the PIN wait does not switch and is a plain failure', () async {
      await run(
        'h1',
        pin: () async {
          now = now.add(PlaybackHandoffLedger.pinWait + const Duration(seconds: 1));
          return true;
        },
      );
      expect(events, contains('activate false'));
      expect(events.last, 'send {$handoffFailedKey: h1}');
      expect(ledger.isArmed, isFalse);
    });

    test('an activation that returns false after the PIN is a plain failure, not a missed PIN', () async {
      await run('h1', activation: () => false);
      expect(events, contains('activate true'));
      expect(events.last, 'send {$handoffFailedKey: h1}');
      expect(handoffQueryReply(ledger, 'h1'), {handoffFailedKey: 'h1'});
      expect(ledger.isArmed, isFalse);
    });

    test('an exception during the switch is a plain failure, not a missed PIN', () async {
      await run('h1', activation: () => throw StateError('storage failed'));
      expect(events.last, 'send {$handoffFailedKey: h1}');
      expect(handoffQueryReply(ledger, 'h1'), {handoffFailedKey: 'h1'});
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

  group('runHandoffProfileSwitch with a Plex token of the sender (A-23c)', () {
    test('a proven token skips the PIN: the phone hears no PIN and the token reaches the activation', () async {
      await run('h1', proof: () async => 'tok-anna');
      expect(events, [
        'send {$handoffSwitchingKey: h1, $handoffProfileKey: Anna, $handoffPinKey: false}',
        'token tok-anna',
        'activate true',
      ]);
      expect(ledger.takeFor('plex-anna')?.id, 'h1');
    });

    test('no proof keeps the PIN', () async {
      await run('h1', proof: () async => null);
      expect(events.first, 'send {$handoffSwitchingKey: h1, $handoffProfileKey: Anna, $handoffPinKey: true}');
      expect(events[1], 'dialog armed=true');
    });

    test('a proof that throws keeps the PIN', () async {
      await run('h1', proof: () async => throw Exception('plex.tv unreachable'));
      expect(events.first, 'send {$handoffSwitchingKey: h1, $handoffProfileKey: Anna, $handoffPinKey: true}');
      expect(events[1], 'dialog armed=true');
    });

    test('the proof runs once the request is armed, so a second handoff meanwhile is refused', () async {
      final checking = Completer<String?>();
      var armedAtProof = false;
      final first = run(
        'h1',
        proof: () {
          armedAtProof = ledger.isArmed;
          return checking.future;
        },
      );
      await Future<void>.delayed(Duration.zero);
      await run('h2');
      checking.complete('tok-anna');
      await first;
      expect(armedAtProof, isTrue);
      expect(events, contains('send {$handoffFailedKey: h2}'));
      expect(events.where((e) => e.startsWith('token')), ['token tok-anna']);
    });

    test('an unprotected profile is never checked', () async {
      var checked = false;
      final open = Profile.plexHome(
        id: 'plex-anna',
        displayName: 'Anna',
        parentConnectionId: 'plex-1',
        plexHomeUserUuid: 'u-anna',
        createdAt: DateTime(2026),
      );
      await run(
        'h1',
        target: open,
        proof: () async {
          checked = true;
          return 'tok-anna';
        },
      );
      expect(checked, isFalse);
      expect(events.first, 'send {$handoffSwitchingKey: h1, $handoffProfileKey: Anna, $handoffPinKey: false}');
    });

    test('a proven switch the phone gave up on is a plain failure, not a missed PIN', () async {
      await run(
        'a23c-cancelled',
        proof: () async {
          cancelPlaybackHandoff('a23c-cancelled');
          return 'tok-anna';
        },
      );
      expect(events, contains('activate false'));
      expect(events.last, 'send {$handoffFailedKey: a23c-cancelled}');
      expect(ledger.isArmed, isFalse);
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
