import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_profile_switch.dart';

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
  late PlaybackHandoffLedger ledger;
  late List<String> events;

  setUp(() {
    ledger = PlaybackHandoffLedger();
    events = [];
  });

  Future<void> run(String id, {required bool activates}) => runHandoffProfileSwitch(
    request: _request(id),
    target: _anna,
    ledger: ledger,
    send: (data) => events.add('send $data'),
    activate: () async {
      events.add('activate armed=${ledger.isArmed}');
      return activates;
    },
    sendDelay: Duration.zero,
  );

  test('the phone hears the switch first, and the request is armed before the profile activates', () async {
    await run('h1', activates: true);
    expect(events, [
      'send {$handoffSwitchingKey: h1, $handoffProfileKey: Anna, $handoffPinKey: true}',
      'activate armed=true',
    ]);
    // No answer yet: the new session plays it and answers.
    expect(ledger.takeFor('plex-anna')?.id, 'h1');
  });

  test('a cancelled PIN leaves nothing armed and tells the phone it is the profile', () async {
    await run('h1', activates: false);
    expect(ledger.isArmed, isFalse);
    expect(events.last, 'send {$handoffFailedKey: h1, $handoffReasonKey: $handoffReasonWrongProfile}');
    expect(handoffQueryReply(ledger, 'h1'), {handoffFailedKey: 'h1', handoffReasonKey: handoffReasonWrongProfile});
  });

  test('a second handoff during a switch is refused without a second dialog', () async {
    ledger.arm(_request('h1'), 'plex-anna');
    await run('h2', activates: true);
    expect(events, ['send {$handoffFailedKey: h2}']);
    expect(ledger.takeFor('plex-anna')?.id, 'h1', reason: 'the first switch keeps its request');
  });
}
