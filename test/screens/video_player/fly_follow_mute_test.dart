// Pleya Fly Meenemen (A-23e, 45-i): a phone that follows an Apple TV starts
// muted, and "Geluid aan" restores the usual level.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/mpv/mpv.dart';
import 'package:pleya/screens/video_player/fly_follow_mute.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/pleya_fly/fly_follow_indicators.dart';

import '../../test_helpers/watch_together_fakes.dart';

class _VolumePlayer extends FakeSyncPlayer {
  final volumes = <double>[];
  final volumeEvents = StreamController<double>.broadcast();

  @override
  Future<void> setVolume(double volume) async {
    volumes.add(volume);
    volumeEvents.add(volume);
  }

  @override
  PlayerStreams get streams {
    final s = super.streams;
    return PlayerStreams(
      playing: s.playing,
      completed: s.completed,
      buffering: s.buffering,
      position: s.position,
      duration: s.duration,
      seekable: s.seekable,
      buffer: s.buffer,
      volume: volumeEvents.stream,
      rate: s.rate,
      tracks: s.tracks,
      track: s.track,
      log: s.log,
      error: s.error,
      audioDevice: s.audioDevice,
      audioDevices: s.audioDevices,
      bufferRanges: s.bufferRanges,
      playbackRestart: s.playbackRestart,
      backendSwitched: s.backendSwitched,
    );
  }
}

class _FlyHost extends WatchTogetherProvider {
  _FlyHost({this.host = true});
  final bool host;

  @override
  bool get isFlySession => true;

  @override
  bool get isHost => host;
}

class _FollowerWatchTogether extends WatchTogetherProvider {
  @override
  bool get isFlyFollower => true;
}

void main() {
  test('a following phone writes no watch state; only the Apple TV does', () {
    final follower = _FollowerWatchTogether();
    expect(playbackReportsAllowed(follower), isFalse);
    follower.dispose();
  });

  test('every watch-state writer of a follower is skipped, through one helper', () {
    final follower = _FollowerWatchTogether();
    final started = <String>[];
    expect(startWatchStateWriter(follower, 'progress tracker', () => started.add('tracker')), isFalse);
    expect(startWatchStateWriter(follower, 'scrobblers', () => started.add('scrobblers')), isFalse);
    expect(started, isEmpty);
    follower.dispose();
  });

  test('negative control: outside Meenemen the writers start', () {
    final ordinary = WatchTogetherProvider();
    final started = <String>[];
    expect(startWatchStateWriter(ordinary, 'progress tracker', () => started.add('tracker')), isTrue);
    expect(startWatchStateWriter(null, 'scrobblers', () => started.add('scrobblers')), isTrue);
    expect(started, ['tracker', 'scrobblers']);
    ordinary.dispose();
  });

  test('back on a following phone leaves without the Samen kijken question', () {
    final follower = _FollowerWatchTogether();
    final ordinary = WatchTogetherProvider();
    expect(leavesWithoutConfirm(follower), isTrue);
    expect(leavesWithoutConfirm(ordinary), isFalse, reason: 'negative control: a code session still asks');
    follower.dispose();
    ordinary.dispose();
  });

  test('closing the player ends its part in a fly session, not when it replaces itself', () {
    final tv = _FlyHost();
    final phone = _FlyHost(host: false);
    final ordinary = WatchTogetherProvider();
    expect(leavesFlySessionOnExit(tv, replacingWithVideo: false), isTrue);
    expect(leavesFlySessionOnExit(phone, replacingWithVideo: false), isTrue);
    expect(leavesFlySessionOnExit(tv, replacingWithVideo: true), isFalse);
    expect(leavesFlySessionOnExit(ordinary, replacingWithVideo: false), isFalse, reason: 'negative control');
    tv.dispose();
    phone.dispose();
    ordinary.dispose();
  });

  test('turning the volume up another way hides Geluid aan', () async {
    final player = _VolumePlayer();
    final mute = FlyFollowMute();
    mute.engage(player, following: true);
    await pumpEventQueue();
    expect(mute.muted.value, isTrue, reason: 'its own mute to 0 does not count');

    player.volumeEvents.add(40);
    await pumpEventQueue();
    expect(mute.muted.value, isFalse);
    mute.dispose();
  });

  test('a release after dispose does nothing', () async {
    final player = _VolumePlayer();
    final mute = FlyFollowMute();
    mute.engage(player, following: true);
    mute.dispose();
    await mute.release(player, 80);
    expect(player.volumes, [0]);
  });

  test('negative control: outside Meenemen every player writes watch state', () {
    final ordinary = WatchTogetherProvider();
    expect(ordinary.isFlyFollower, isFalse);
    expect(playbackReportsAllowed(ordinary), isTrue);
    expect(playbackReportsAllowed(null), isTrue);
    ordinary.dispose();
  });

  setUp(() => LocaleSettings.setLocale(AppLocale.nl));

  test('a following phone starts muted, once', () {
    final player = _VolumePlayer();
    final mute = FlyFollowMute();

    expect(mute.engage(player, following: true), isTrue);
    expect(mute.engage(player, following: true), isFalse);
    expect(player.volumes, [0]);
    expect(mute.muted.value, isTrue);
    mute.dispose();
  });

  test('negative control: an ordinary guest or host keeps its sound', () {
    final player = _VolumePlayer();
    final mute = FlyFollowMute();

    expect(mute.engage(player, following: false), isFalse);
    expect(player.volumes, isEmpty);
    expect(mute.muted.value, isFalse);
    mute.dispose();
  });

  test('Geluid aan restores the usual level, and only after a mute', () async {
    final player = _VolumePlayer();
    final mute = FlyFollowMute();

    await mute.release(player, 80);
    expect(player.volumes, isEmpty);

    mute.engage(player, following: true);
    await mute.release(player, 80);
    expect(player.volumes, [0, 80]);
    expect(mute.muted.value, isFalse);
    mute.dispose();
  });

  testWidgets('the Geluid aan button shows while muted and unmutes on a tap', (tester) async {
    final mute = FlyFollowMute();
    final player = _VolumePlayer();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: FlySoundOnButton(muted: mute.muted, onUnmute: () => mute.release(player, 100)),
        ),
      ),
    );
    expect(find.text('Geluid aan'), findsNothing);

    mute.engage(player, following: true);
    await tester.pump();
    expect(find.text('Geluid aan'), findsOneWidget);

    await tester.tap(find.text('Geluid aan'));
    await tester.pump();
    expect(find.text('Geluid aan'), findsNothing);
    expect(player.volumes, [0, 100]);
    mute.dispose();
  });
}
