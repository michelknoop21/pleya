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
  _FakePlayer()
    : _streams = PlayerStreams(
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
        log: const Stream<PlayerLog>.empty(),
        error: const Stream<PlayerError>.empty(),
        audioDevice: const Stream<AudioDevice>.empty(),
        audioDevices: const Stream<List<AudioDevice>>.empty(),
        bufferRanges: const Stream<List<BufferRange>>.empty(),
        playbackRestart: const Stream<void>.empty(),
        backendSwitched: const Stream<void>.empty(),
      );

  final PlayerStreams _streams;

  bool buffering = false;
  bool failNextSetProperty = false;
  bool failNextPassthrough = false;

  final List<MapEntry<String, String>> properties = [];
  final List<bool> passthroughCalls = [];

  @override
  PlayerState get state => PlayerState(buffering: buffering);

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
