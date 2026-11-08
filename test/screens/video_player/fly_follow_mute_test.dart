// Pleya Fly Meenemen (A-23e, 45-i): a phone that follows an Apple TV starts
// muted, and "Geluid aan" restores the usual level.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/video_player/fly_follow_mute.dart';
import 'package:pleya/watch_together/providers/watch_together_provider.dart';
import 'package:pleya/widgets/pleya_fly/fly_follow_indicators.dart';

import '../../test_helpers/watch_together_fakes.dart';

class _VolumePlayer extends FakeSyncPlayer {
  final volumes = <double>[];

  @override
  Future<void> setVolume(double volume) async => volumes.add(volume);
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
