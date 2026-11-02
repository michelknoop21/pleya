import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/automation/automation_registry.dart';
import 'package:pleya/media/loudness_evidence.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/player.dart';
import 'package:pleya/mpv/player/player_state.dart';
import 'package:pleya/mpv/player/player_streams.dart';
import 'package:pleya/mpv/video.dart';

class _Streams implements PlayerStreams {
  _Streams(this.playbackRestart);
  @override
  final Stream<void> playbackRestart;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Player implements Player {
  _Player(Stream<void> restart) : streams = _Streams(restart);
  @override
  final PlayerStreams streams;
  @override
  PlayerState get state => const PlayerState();
  @override
  int? get textureId => null;
  @override
  AudioLoudness get plannedLoudness => AudioLoudness.none;
  @override
  AudioLoudness get effectiveLoudness => AudioLoudness.none;
  @override
  LoudnessEvidence? get loudnessEvidence => null;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  testWidgets(
    'first-frame evidence requires native restart rather than a dismissed loading indicator',
    (tester) async {
      final restart = StreamController<void>.broadcast();
      addTearDown(restart.close);
      final loadingComplete = ValueNotifier(true);
      addTearDown(loadingComplete.dispose);
      await tester.pumpWidget(
        MaterialApp(
          home: Video(player: _Player(restart.stream), hasFirstFrame: loadingComplete),
        ),
      );
      Map state() =>
          ((AutomationRegistry.instance.snapshot()['declared'] as List).cast<Map>().singleWhere(
                (n) => n['id'] == 'player.surface',
              )['state'])
              as Map;
      expect(state()['first_frame'], isFalse);
      restart.add(null);
      await tester.pump();
      expect(state()['first_frame'], isTrue);
      loadingComplete.value = false;
      await tester.pump();
      expect(state()['first_frame'], isFalse);
      loadingComplete.value = true;
      await tester.pump();
      expect(state()['first_frame'], isFalse, reason: 'an error may hide the spinner without rendering a frame');
    },
    skip: !const bool.fromEnvironment('PLEYA_VERIFY'),
  );
}
