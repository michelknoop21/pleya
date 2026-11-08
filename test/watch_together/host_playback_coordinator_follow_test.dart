// Pleya Fly Meenemen (A-23e): the Apple TV hosts a session that phones follow.
// A follower never holds the room, and the session opens around a player
// that already runs without pausing or starting it.
import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/watch_together/models/playback_state.dart';
import 'package:pleya/watch_together/models/watch_session.dart';
import 'package:pleya/watch_together/services/attached_player.dart';
import 'package:pleya/watch_together/services/host_playback_coordinator.dart';

import '../test_helpers/watch_together_fakes.dart';

const _epochMs = 1000000;

class _Harness {
  _Harness(FakeAsync async, {required bool guestsFollow, bool playing = false}) {
    int nowMs() => _epochMs + async.elapsed.inMilliseconds;
    player = FakeSyncPlayer(position: const Duration(minutes: 76), playing: playing);
    coordinator = HostPlaybackCoordinator(
      myPeerId: 'host',
      controlMode: ControlMode.anyone,
      guestsFollow: guestsFollow,
      sendState: (state, {toPeerId}) => sent.add((state, toPeerId)),
      nowMs: nowMs,
    );
    attached = AttachedPlayer(player: player, onLost: () {}, nowMs: nowMs);
  }

  late final FakeSyncPlayer player;
  late final HostPlaybackCoordinator coordinator;
  late final AttachedPlayer attached;
  final List<(PlaybackState, String?)> sent = [];

  PlaybackState get last => [
    for (final (state, to) in sent)
      if (to == null) state,
  ].last;

  void guestReports(FakeAsync async, {bool ready = true, bool buffering = false}) {
    coordinator.onPeerStatus(
      'phone',
      PeerStatus(mediaKey: 'srv:rk1', ready: ready, buffering: buffering, positionMs: 0),
    );
    async.flushMicrotasks();
  }

  void dispose() {
    coordinator.dispose();
    attached.dispose();
  }
}

/// A room in which the host plays and one guest reported ready.
_Harness _playingRoom(FakeAsync async, {required bool guestsFollow}) {
  final h = _Harness(async, guestsFollow: guestsFollow);
  h.coordinator.onPeerJoined('phone', compatible: true);
  h.coordinator.attach(h.attached, ratingKey: 'rk1', serverId: 'srv');
  async.flushMicrotasks();
  h.guestReports(async);
  h.player.emitPlaybackRestart();
  async.flushMicrotasks();
  async.elapse(const Duration(seconds: 3));
  expect(h.player.state.playing, isTrue);
  expect(h.last.phase, PlaybackPhase.playing);
  return h;
}

void main() {
  group('follower role', () {
    test('a follower that stalls never pauses the host', () {
      fakeAsync((async) {
        final h = _playingRoom(async, guestsFollow: true);
        final pausesBefore = h.player.commandLog.where((c) => c == 'pause').length;

        h.guestReports(async, buffering: true);
        async.elapse(const Duration(seconds: 2));

        expect(h.last.phase, PlaybackPhase.playing);
        expect(h.last.waitingOn, isEmpty);
        expect(h.player.state.playing, isTrue);
        expect(h.player.commandLog.where((c) => c == 'pause').length, pausesBefore);
        h.dispose();
      });
    });

    test('negative control: the same stall from an ordinary guest pauses the host', () {
      fakeAsync((async) {
        final h = _playingRoom(async, guestsFollow: false);

        h.guestReports(async, buffering: true);
        async.elapse(const Duration(seconds: 2));

        expect(h.last.phase, PlaybackPhase.waitingForPeers);
        expect(h.last.waitingOn, ['phone']);
        expect(h.player.state.playing, isFalse);
        h.dispose();
      });
    });

    test('a follower that never reports does not hold the first start', () {
      fakeAsync((async) {
        final h = _Harness(async, guestsFollow: true);
        h.coordinator.onPeerJoined('phone', compatible: true);
        h.coordinator.attach(h.attached, ratingKey: 'rk1', serverId: 'srv');
        async.flushMicrotasks();
        h.player.emitPlaybackRestart();
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        expect(h.last.phase, PlaybackPhase.playing);
        expect(h.player.state.playing, isTrue);
        h.dispose();
      });
    });
  });

  group('mid-play attach', () {
    test('a session opened around a playing player keeps it playing, without a pause', () {
      fakeAsync((async) {
        final h = _Harness(async, guestsFollow: true, playing: true);
        h.coordinator.attach(h.attached, ratingKey: 'rk1', serverId: 'srv', hasFirstFrame: true, adoptPlayback: true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        expect(h.player.commandLog, isNot(contains('pause')));
        expect(h.player.state.playing, isTrue);
        expect(h.last.phase, PlaybackPhase.playing);
        expect(h.last.anchorPositionMs, const Duration(minutes: 76).inMilliseconds);

        // A phone joining later only gets the state; the host plays on.
        h.coordinator.onPeerJoined('phone', compatible: true);
        h.guestReports(async, ready: false);
        async.elapse(const Duration(seconds: 2));
        expect(h.player.commandLog, isNot(contains('pause')));
        expect(h.last.phase, PlaybackPhase.playing);
        h.dispose();
      });
    });

    test('a session opened around a paused player keeps it paused', () {
      fakeAsync((async) {
        final h = _Harness(async, guestsFollow: true);
        h.coordinator.attach(h.attached, ratingKey: 'rk1', serverId: 'srv', hasFirstFrame: true, adoptPlayback: true);
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 3));

        expect(h.player.commandLog, isNot(contains('play')));
        expect(h.player.state.playing, isFalse);
        expect(h.last.phase, PlaybackPhase.paused);
        h.dispose();
      });
    });

    test('negative control: the ordinary attach pauses a playing player for the group start', () {
      fakeAsync((async) {
        final h = _Harness(async, guestsFollow: true, playing: true);
        h.coordinator.attach(h.attached, ratingKey: 'rk1', serverId: 'srv', hasFirstFrame: true);
        async.flushMicrotasks();

        expect(h.player.commandLog, contains('pause'));
        h.dispose();
      });
    });
  });
}
