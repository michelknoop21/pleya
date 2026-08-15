import 'dart:async';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/mpv/models.dart';
import 'package:pleya/mpv/player/player.dart';
import 'package:pleya/mpv/player/player_state.dart';
import 'package:pleya/mpv/player/player_streams.dart';
import 'package:pleya/services/audio_output_coordinator.dart';
import 'package:pleya/services/audio_output_decision.dart';
import 'package:pleya/services/settings_service.dart';

import '../test_helpers/prefs.dart';

/// Records what the coordinator writes to mpv, and can be told to fail a write
/// or to report the player as buffering.
class _FakePlayer implements Player {
  _FakePlayer() {
    _streams = PlayerStreams(
      playing: const Stream<bool>.empty(),
      completed: const Stream<bool>.empty(),
      buffering: const Stream<bool>.empty(),
      position: const Stream<Duration>.empty(),
      duration: const Stream<Duration>.empty(),
      seekable: const Stream<bool>.empty(),
      buffer: const Stream<Duration>.empty(),
      volume: const Stream<double>.empty(),
      rate: const Stream<double>.empty(),
      tracks: const Stream<Tracks>.empty(),
      track: const Stream<TrackSelection>.empty(),
      log: _logs.stream,
      error: const Stream<PlayerError>.empty(),
      audioDevice: const Stream<AudioDevice>.empty(),
      audioDevices: const Stream<List<AudioDevice>>.empty(),
      bufferRanges: const Stream<List<BufferRange>>.empty(),
      playbackRestart: const Stream<void>.empty(),
      backendSwitched: const Stream<void>.empty(),
    );
  }

  late final PlayerStreams _streams;
  final StreamController<PlayerLog> _logs = StreamController<PlayerLog>.broadcast();

  bool buffering = false;
  bool playing = false;
  Duration position = Duration.zero;
  bool failNextSetProperty = false;
  bool failNextPassthrough = false;

  final List<MapEntry<String, String>> properties = [];
  final List<bool> passthroughCalls = [];

  /// What mpv answers for a property, and which ones were asked for.
  final Map<String, String?> propertyValues = {};
  final List<String> propertyReads = [];

  void emitLog(String text) => _logs.add(PlayerLog(prefix: 'cplayer', level: PlayerLogLevel.verbose, text: text));

  @override
  PlayerState get state => PlayerState(buffering: buffering, playing: playing, position: position);

  @override
  Future<String?> getProperty(String name) async {
    propertyReads.add(name);
    return propertyValues[name];
  }

  @override
  PlayerStreams get streams => _streams;

  @override
  String get playerType => 'mpv';

  @override
  Future<void> setProperty(String name, String value) async {
    if (failNextSetProperty) {
      failNextSetProperty = false;
      throw StateError('native write failed');
    }
    properties.add(MapEntry(name, value));
  }

  @override
  Future<void> setAudioPassthrough(bool enabled) async {
    passthroughCalls.add(enabled);
    if (failNextPassthrough) {
      failNextPassthrough = false;
      throw StateError('native passthrough write failed');
    }
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late SettingsService settings;

  setUp(() async {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    settings = await SettingsService.getInstance();
    AudioOutputCoordinator.current = null;
  });

  test('a failed native write is retried instead of being cached as applied', () async {
    final player = _FakePlayer();
    final coordinator = AudioOutputCoordinator(player: player, settings: settings);

    await coordinator.prepare(audioCodec: 'eac3');
    player.passthroughCalls.clear();

    // The write throws. Recording the decision before awaiting would make this
    // look applied, and every later apply would skip it as "no change" —
    // leaving the player bitstreaming after the user asked for PCM.
    player.failNextPassthrough = true;
    await settings.write(SettingsService.audioOutputMode, AudioOutputMode.passthrough);
    await coordinator.onModeChanged();
    expect(player.passthroughCalls, [true], reason: 'the failing attempt still reached the player');

    // Nothing else changed, so a naive cache would now do nothing at all.
    await coordinator.onModeChanged();
    expect(player.passthroughCalls, [true, true], reason: 'the failed write must be retried, not skipped');

    coordinator.dispose();
  });

  test('mode changes still land after the decision cache recovers', () async {
    final player = _FakePlayer();
    final coordinator = AudioOutputCoordinator(player: player, settings: settings);
    await settings.write(SettingsService.audioOutputMode, AudioOutputMode.passthrough);

    await coordinator.prepare(audioCodec: 'eac3');
    expect(player.passthroughCalls, [true]);

    await settings.write(SettingsService.audioOutputMode, AudioOutputMode.pcm);
    await coordinator.onModeChanged();
    expect(player.passthroughCalls, [true, false]);

    coordinator.dispose();
  });

  test('a disposed coordinator stops touching the player', () async {
    final player = _FakePlayer();
    final coordinator = AudioOutputCoordinator(player: player, settings: settings);
    await coordinator.prepare(audioCodec: 'eac3');
    final callsBefore = player.passthroughCalls.length;

    coordinator.dispose();
    await coordinator.onModeChanged();

    expect(player.passthroughCalls.length, callsBefore, reason: 'no writes after dispose');
  });

  test('clears the active-coordinator handle only if it still owns it', () async {
    final first = AudioOutputCoordinator(player: _FakePlayer(), settings: settings);
    final second = AudioOutputCoordinator(player: _FakePlayer(), settings: settings);

    await first.prepare();
    await second.prepare();
    expect(AudioOutputCoordinator.current, same(second));

    // The outgoing coordinator is disposed after the new one has taken over —
    // it must not orphan the handle the sheets read.
    first.dispose();
    expect(AudioOutputCoordinator.current, same(second));

    second.dispose();
    expect(AudioOutputCoordinator.current, isNull);
  });

  test('an apply requested mid-flight runs instead of being dropped', () {
    fakeAsync((async) {
      final player = _FakePlayer();
      final coordinator = AudioOutputCoordinator(player: player, settings: settings);

      coordinator.prepare(audioCodec: 'eac3');
      async.flushMicrotasks();

      // Two mode changes back to back: the second lands while the first apply
      // is still awaiting the player, and must not be silently dropped.
      settings.write(SettingsService.audioOutputMode, AudioOutputMode.passthrough);
      async.flushMicrotasks();
      coordinator.onModeChanged();
      settings.write(SettingsService.audioOutputMode, AudioOutputMode.pcm);
      coordinator.onModeChanged();
      async.flushMicrotasks();
      async.elapse(const Duration(seconds: 1));

      expect(player.passthroughCalls.last, isFalse, reason: 'the newer pcm choice must win');
      coordinator.dispose();
    });
  });

  group('stall watchdog', () {
    /// Puts the coordinator on the bitstream path with the player reporting
    /// playback that is running but going nowhere.
    _FakePlayer stalledOnPassthrough(FakeAsync async, AudioOutputCoordinator coordinator, _FakePlayer player) {
      settings.write(SettingsService.audioOutputMode, AudioOutputMode.passthrough);
      async.flushMicrotasks();
      coordinator.prepare(audioCodec: 'eac3');
      async.flushMicrotasks();
      expect(player.passthroughCalls, [true], reason: 'the bitstream path must be the one under test');
      player.playing = true;
      player.position = const Duration(minutes: 15);
      return player;
    }

    setUp(AudioOutputCoordinator.resetBitstreamBlocksForTest);

    test('gives up a little over the stall timeout, not at twice it', () {
      fakeAsync((async) {
        final player = _FakePlayer();
        final coordinator = AudioOutputCoordinator(player: player, settings: settings);
        stalledOnPassthrough(async, coordinator, player);

        // Sampling every second means the first tick only records a position;
        // three more identical ones make it a stall.
        async.elapse(const Duration(seconds: 3));
        expect(player.passthroughCalls, [true], reason: 'too early to call it a stall');

        async.elapse(const Duration(seconds: 2));
        expect(player.passthroughCalls.last, isFalse, reason: 'the bitstream must be abandoned by ~4s');

        coordinator.dispose();
      });
    });

    test('a position that keeps moving is never a stall', () {
      fakeAsync((async) {
        final player = _FakePlayer();
        final coordinator = AudioOutputCoordinator(player: player, settings: settings);
        stalledOnPassthrough(async, coordinator, player);

        for (var i = 0; i < 20; i++) {
          async.elapse(const Duration(seconds: 1));
          player.position += const Duration(seconds: 1);
        }

        expect(player.passthroughCalls, [true], reason: 'playback was advancing the whole time');
        coordinator.dispose();
      });
    });

    test('buffering resets the count instead of ageing into a stall', () {
      fakeAsync((async) {
        final player = _FakePlayer();
        final coordinator = AudioOutputCoordinator(player: player, settings: settings);
        stalledOnPassthrough(async, coordinator, player);

        // Two seconds of standing still, then a buffering hitch: the position
        // is expected to sit still during buffering, so the count has to start
        // over rather than tip over on the next tick.
        async.elapse(const Duration(seconds: 2));
        player.buffering = true;
        async.elapse(const Duration(seconds: 3));
        expect(player.passthroughCalls, [true], reason: 'buffering is not a stalled bitstream');

        player.buffering = false;
        async.elapse(const Duration(seconds: 2));
        expect(player.passthroughCalls, [true], reason: 'the count must have restarted after buffering');

        async.elapse(const Duration(seconds: 3));
        expect(player.passthroughCalls.last, isFalse, reason: 'still stuck once buffering is over');

        coordinator.dispose();
      });
    });
  });

  group('verifying what mpv settled on', () {
    test('recognises the AO line mpv logs when the output opens', () {
      // Straight from an Apple TV device log; the probe hangs on this line, so
      // a reworded upstream string must fail here loudly.
      for (final line in [
        'AO: [avfoundation] 192000Hz stereo 2ch spdif-eac3',
        'AO: [audiounit] 48000Hz 5.1 6ch floatp',
        '  AO: [pulse] 48000Hz stereo 2ch float',
      ]) {
        expect(AudioOutputCoordinator.isAudioOutputOpenedLog(line), isTrue, reason: line);
      }
    });

    test('ignores lines that are not an audio output coming up', () {
      for (final line in [
        'VO: [avfoundation] 1920x1080 yuv420p',
        'Selected decoder: spdif_eac3',
        'audiounit does not support spdif formats',
        'Setting option AO: [avfoundation]',
        '',
      ]) {
        expect(AudioOutputCoordinator.isAudioOutputOpenedLog(line), isFalse, reason: line);
      }
    });

    test('measures as soon as the AO log arrives, and only once per decision', () {
      fakeAsync((async) {
        final player = _FakePlayer();
        final coordinator = AudioOutputCoordinator(player: player, settings: settings);
        coordinator.prepare(audioCodec: 'eac3');
        async.flushMicrotasks();
        player.propertyValues['current-ao'] = 'avfoundation';
        player.propertyValues['audio-out-params/format'] = 'spdif-eac3';
        player.propertyReads.clear();

        player.emitLog('AO: [avfoundation] 192000Hz stereo 2ch spdif-eac3');
        async.flushMicrotasks();
        expect(player.propertyReads, contains('current-ao'), reason: 'measured on the log line, not on the timer');
        // Kept, not only logged: this is the ground truth a later layer needs
        // to tell a requested bitstream from a running one.
        expect(coordinator.verifiedOutput?.ao, 'avfoundation');
        expect(coordinator.verifiedOutput?.isBitstream, isTrue);

        // mpv reloads the AO for reasons that are not a decision change; those
        // must not produce a second reading of the same decision.
        player.propertyReads.clear();
        player.emitLog('AO: [avfoundation] 48000Hz 5.1 6ch floatp');
        async.flushMicrotasks();
        async.elapse(const Duration(seconds: 30));
        expect(player.propertyReads, isEmpty, reason: 'the decision was already measured');

        coordinator.dispose();
      });
    });

    test('keeps trying while mpv has no output yet', () {
      fakeAsync((async) {
        final player = _FakePlayer();
        final coordinator = AudioOutputCoordinator(player: player, settings: settings);
        coordinator.prepare(audioCodec: 'eac3');
        async.flushMicrotasks();

        // An AO that is still coming up answers with an empty string, not with
        // null. Logging that as "unknown" is what made the device reports
        // worthless.
        player.propertyValues['current-ao'] = '';
        player.propertyValues['audio-out-params/format'] = 'spdif-eac3';
        player.propertyReads.clear();
        async.elapse(const Duration(seconds: 2));
        expect(player.propertyReads, contains('current-ao'));

        player.propertyReads.clear();
        async.elapse(const Duration(seconds: 1));
        expect(player.propertyReads, contains('current-ao'), reason: 'an empty answer is not a measurement');

        player.propertyValues['current-ao'] = 'avfoundation';
        async.elapse(const Duration(seconds: 1));
        player.propertyReads.clear();
        async.elapse(const Duration(seconds: 30));
        expect(player.propertyReads, isEmpty, reason: 'polling stops once there is something to report');

        coordinator.dispose();
      });
    });
  });

  group('recognising mpv giving up on the bitstream', () {
    test('matches the messages mpv actually emits', () {
      // These come from the shipped libmpv binary; the fallback hangs on them,
      // so a reworded upstream string must fail here loudly.
      for (final line in [
        'eac3 passthrough disabled after an earlier renderer failure',
        'ac3 passthrough disabled after an earlier renderer failure',
      ]) {
        expect(AudioOutputCoordinator.isPassthroughFailureLog(line), isTrue, reason: line);
      }
    });

    test('ignores ordinary log noise', () {
      for (final line in [
        // This one is a trap: it is mpv falling through from audiounit to the
        // avfoundation AO, which is how the bitstream path is *supposed* to
        // start. Treating it as a failure would disable passthrough on every
        // single attempt.
        'audiounit does not support spdif formats',
        'Using hardware decoding (videotoolbox).',
        'Audio device underrun detected.',
        'VO: [avfoundation] 1920x1080 yuv420p',
        '',
      ]) {
        expect(AudioOutputCoordinator.isPassthroughFailureLog(line), isFalse, reason: line);
      }
    });
  });
}
