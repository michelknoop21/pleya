import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/models/companion_remote/remote_command.dart';
import 'package:pleya/services/companion_remote/playback_handoff.dart';
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

  test('the handoff command is appended after syncState: the wire format is the enum index', () {
    expect(RemoteCommandType.handoff.index, RemoteCommandType.syncState.index + 1);
    expect(RemoteCommandType.handoff.index, RemoteCommandType.values.length - 1);
  });

  test('an Apple TV listens for a handoff by default; a phone does not', () {
    expect(SettingsService.companionRemoteServerDefaultFor(desktop: false, appleTv: true), isTrue);
    expect(SettingsService.companionRemoteServerDefaultFor(desktop: true, appleTv: false), isTrue);
    expect(SettingsService.companionRemoteServerDefaultFor(desktop: false, appleTv: false), isFalse);
  });
}
