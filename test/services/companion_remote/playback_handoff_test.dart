import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/models/companion_remote/remote_command.dart';
import 'package:pleya/profiles/profile.dart';
import 'package:pleya/profiles/profile_connection.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
import 'package:pleya/services/companion_remote/playback_handoff_receiver.dart';
import 'package:pleya/services/settings_service.dart';

PlaybackHandoffRequest _request() => const PlaybackHandoffRequest(
  id: 'h1',
  serverId: 'server_1',
  itemId: 'item_9',
  positionMs: 226000,
  title: 'Big Buck Bunny',
  from: 'iPhone van Michel',
);

void main() {
  group('PlaybackHandoffRequest', () {
    test('survives the wire', () {
      final back = PlaybackHandoffRequest.fromData(_request().toData());
      expect(back?.serverId, 'server_1');
      expect(back?.itemId, 'item_9');
      expect(back?.positionMs, 226000);
      expect(back?.from, 'iPhone van Michel');
    });

    test('a malformed request is dropped, never half-played', () {
      for (final broken in <Map<String, dynamic>?>[
        null,
        {..._request().toData()}..remove('itemId'),
        {..._request().toData(), 'serverId': ''},
        {..._request().toData(), 'positionMs': -1},
        {..._request().toData(), 'positionMs': '226000'},
        {..._request().toData(), 'id': 5},
      ]) {
        expect(PlaybackHandoffRequest.fromData(broken), isNull, reason: '$broken');
      }
    });
  });

  group('PlaybackHandoffTracker', () {
    test('the host saying it plays resolves the sender as playing', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h1', const Duration(seconds: 5));
      tracker.handleSyncState({handoffPlayingKey: 'h1'});
      expect(await answer, PlaybackHandoffOutcome.playing);
    });

    test('a failure keeps the sender playing', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h1', const Duration(seconds: 5));
      tracker.handleSyncState({handoffFailedKey: 'h1'});
      expect(await answer, PlaybackHandoffOutcome.failed);
    });

    test('a refusal for another profile is told apart, so the sheet can say what to fix', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h1', const Duration(seconds: 5));
      tracker.handleSyncState({handoffFailedKey: 'h1', handoffReasonKey: handoffReasonWrongProfile});
      expect(await answer, PlaybackHandoffOutcome.wrongProfile);
    });

    test('silence is a timeout, not a success', () async {
      final tracker = PlaybackHandoffTracker();
      expect(await tracker.wait('h1', const Duration(milliseconds: 20)), PlaybackHandoffOutcome.timedOut);
    });

    test('an answer for another handoff does not stop this sender', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h2', const Duration(milliseconds: 50));
      tracker.handleSyncState({handoffPlayingKey: 'h1'});
      expect(await answer, PlaybackHandoffOutcome.timedOut);
    });

    test('a dropped connection fails the outstanding handoff', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h1', const Duration(seconds: 5));
      tracker.failAll();
      expect(await answer, PlaybackHandoffOutcome.failed);
    });

    test('a repeated acknowledgement is ignored', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h1', const Duration(seconds: 5));
      tracker.handleSyncState({handoffPlayingKey: 'h1'});
      tracker.handleSyncState({handoffFailedKey: 'h1'});
      expect(await answer, PlaybackHandoffOutcome.playing);
    });
  });

  group('PlaybackHandoffTracker during a profile switch (A-23b)', () {
    Map<String, dynamic> switching(String id, {bool pin = false}) => {
      handoffSwitchingKey: id,
      handoffProfileKey: 'Anna',
      handoffPinKey: pin,
    };

    test(
      'the drop of a switch is expected: the sender keeps waiting and hears the answer after reconnecting',
      () async {
        final tracker = PlaybackHandoffTracker();
        final answer = tracker.wait('h1', const Duration(seconds: 5));
        tracker.handleSyncState(switching('h1'));
        tracker.failAll();
        expect(tracker.switchingIds, ['h1']);
        tracker.handleSyncState({handoffPlayingKey: 'h1'});
        expect(await answer, PlaybackHandoffOutcome.playing);
      },
    );

    test('the profile name and the PIN question reach the sheet', () async {
      final tracker = PlaybackHandoffTracker();
      final heard = <(String, bool)>[];
      final answer = tracker.wait('h1', const Duration(seconds: 5), onSwitching: (p, pin) => heard.add((p, pin)));
      tracker.handleSyncState(switching('h1', pin: true));
      expect(heard, [('Anna', true)]);
      tracker.complete('h1', PlaybackHandoffOutcome.failed);
      await answer;
    });

    test('the switch budget replaces the short wait, and pending keeps the sender waiting', () async {
      final tracker = PlaybackHandoffTracker(switchBudget: const Duration(milliseconds: 400));
      final answer = tracker.wait('h1', const Duration(milliseconds: 30));
      tracker.handleSyncState(switching('h1'));
      tracker.handleSyncState({handoffPendingKey: 'h1'});
      await Future<void>.delayed(const Duration(milliseconds: 120));
      tracker.handleSyncState({handoffPlayingKey: 'h1'});
      expect(await answer, PlaybackHandoffOutcome.playing);
    });

    test('the switch budget ends in a timeout', () async {
      final tracker = PlaybackHandoffTracker(switchBudget: const Duration(milliseconds: 80));
      final answer = tracker.wait('h1', const Duration(seconds: 30));
      tracker.handleSyncState(switching('h1'));
      expect(await answer, PlaybackHandoffOutcome.timedOut);
    }, timeout: const Timeout(Duration(seconds: 3)));

    test('a phone that stops reconnecting fails a switching handoff too', () async {
      final tracker = PlaybackHandoffTracker();
      final answer = tracker.wait('h1', const Duration(seconds: 5));
      tracker.handleSyncState(switching('h1'));
      tracker.failAll(force: true);
      expect(await answer, PlaybackHandoffOutcome.failed);
    });
  });

  group('PlaybackHandoffLedger', () {
    var now = DateTime(2026, 10, 19, 20);
    PlaybackHandoffLedger ledger() => PlaybackHandoffLedger(clock: () => now);
    setUp(() => now = DateTime(2026, 10, 19, 20));

    test('only the session of the armed profile takes the request', () {
      final l = ledger()..arm(_request(), 'anna');
      expect(l.takeFor('anna')?.id, 'h1');
      expect(l.takeFor('anna'), isNull, reason: 'taken once');
    });

    test('another profile drops the request, and the phone hears it failed', () {
      final l = ledger()..arm(_request(), 'anna');
      expect(l.takeFor('michel'), isNull);
      expect(l.takeFor('anna'), isNull);
      expect(handoffQueryReply(l, 'h1'), {handoffFailedKey: 'h1'});
    });

    test('a request older than the budget is dropped', () {
      final l = ledger()..arm(_request(), 'anna');
      now = now.add(PlaybackHandoffLedger.ttl + const Duration(seconds: 1));
      expect(l.isArmed, isFalse);
      expect(handoffQueryReply(l, 'h1'), {handoffFailedKey: 'h1'});
      expect(l.takeFor('anna'), isNull);
    });

    test('the Apple TV budget is shorter than the phone waits during a switch', () {
      expect(PlaybackHandoffLedger.ttl, lessThan(PlaybackHandoffTracker().switchBudget));
    });

    test('a reconnected phone hears pending, then the recorded answer', () {
      final l = ledger()..arm(_request(), 'anna');
      expect(handoffQueryReply(l, 'h1'), {handoffPendingKey: 'h1'});
      l.takeFor('anna');
      expect(handoffQueryReply(l, 'h1'), {handoffPendingKey: 'h1'});
      l.record('h1', PlaybackHandoffOutcome.playing);
      expect(handoffQueryReply(l, 'h1'), {handoffPlayingKey: 'h1'});
      l.record('h2', PlaybackHandoffOutcome.wrongProfile);
      expect(handoffQueryReply(l, 'h2'), {handoffFailedKey: 'h2', handoffReasonKey: handoffReasonWrongProfile});
      expect(handoffQueryReply(l, 'unknown'), {handoffFailedKey: 'unknown'});
    });
  });

  group('profileForHandoffSender', () {
    final created = DateTime(2026);
    final anna = Profile.plexHome(
      id: 'plex-anna',
      displayName: 'Anna',
      parentConnectionId: 'plex-1',
      plexHomeUserUuid: 'u-anna',
      createdAt: created,
    );
    final kids = Profile.local(id: 'local-kids', displayName: 'Kinderen', createdAt: created);
    final guest = Profile.local(id: 'local-guest', displayName: 'Gast', createdAt: created);
    ProfileConnection row(String profileId, String uuid) =>
        ProfileConnection(profileId: profileId, connectionId: 'plex-1', userIdentifier: uuid);

    test('a Plex Home profile of the sender on the same account', () {
      final match = profileForHandoffSender(
        [kids, anna],
        connectionId: 'plex-1',
        userUuid: 'u-anna',
        joinRows: [row('local-kids', 'u-anna')],
      );
      expect(match?.id, 'plex-anna');
    });

    test('the same user on another account is not the sender', () {
      expect(profileForHandoffSender([anna], connectionId: 'plex-2', userUuid: 'u-anna', joinRows: const []), isNull);
    });

    test('a local profile that holds the account for the sender', () {
      final match = profileForHandoffSender(
        [kids, guest],
        connectionId: 'plex-1',
        userUuid: 'u-sam',
        joinRows: [row('local-kids', 'u-sam'), row('local-guest', 'u-other')],
      );
      expect(match?.id, 'local-kids');
    });

    test('two local profiles for the sender are ambiguous: no switch', () {
      expect(
        profileForHandoffSender(
          [kids, guest],
          connectionId: 'plex-1',
          userUuid: 'u-sam',
          joinRows: [row('local-kids', 'u-sam'), row('local-guest', 'u-sam')],
        ),
        isNull,
      );
    });
  });

  test('the handoff command is appended after syncState: the wire format is the enum index', () {
    expect(RemoteCommandType.handoff.index, RemoteCommandType.syncState.index + 1);
    expect(RemoteCommandType.handoff.index, RemoteCommandType.values.length - 1);
  });

  test('an Apple TV listens for a handoff by default; a phone does not', () {
    expect(SettingsService.companionRemoteServerDefaultFor(desktop: false, appleTv: true), isTrue);
    expect(SettingsService.companionRemoteServerDefaultFor(desktop: true, appleTv: false), isTrue);
    expect(SettingsService.companionRemoteServerDefaultFor(desktop: false, appleTv: false), isFalse);
  });

  test('a cancel that arrives before the player mounts is remembered for the start', () {
    expect(isPlaybackHandoffCancelled('h9'), isFalse);
    cancelPlaybackHandoff('h9');
    expect(isPlaybackHandoffCancelled('h9'), isTrue);
    expect(isPlaybackHandoffCancelled('h10'), isFalse);
  });

  test('the item is played at the handed-over position, not the server one (transcode offset)', () {
    final item = MediaItem(
      backend: MediaBackend.plex,
      kind: MediaKind.movie,
      id: 'item_9',
      serverId: 'server_1',
      title: 'Big Buck Bunny',
      viewOffsetMs: 600000,
    );
    expect(itemAtHandoffPosition(item, _request()).viewOffsetMs, 226000);
  });

  test('only the active user of the Apple TV may hand over: progress lands on that account', () {
    expect(handoffUserMatches(clientUserUuid: 'u1', hostUserUuid: 'u1'), isTrue);
    expect(handoffUserMatches(clientUserUuid: 'u2', hostUserUuid: 'u1'), isFalse);
    expect(handoffUserMatches(clientUserUuid: '', hostUserUuid: ''), isFalse);
  });
}
