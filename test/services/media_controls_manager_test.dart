import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/media_controls_manager.dart';
import 'package:os_media_controls/os_media_controls.dart';
import 'package:pleya/mpv/mpv.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('com.edde746.os_media_controls/methods');
  final calls = <MethodCall>[];
  late MediaControlsManager manager;
  var failNext = false;

  setUp(() {
    debugDefaultTargetPlatformOverride = TargetPlatform.iOS;
    calls.clear();
    failNext = false;
    manager = MediaControlsManager();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (failNext) {
        failNext = false;
        throw PlatformException(code: 'unavailable');
      }
      return null;
    });
  });

  tearDown(() {
    manager.dispose();
    debugDefaultTargetPlatformOverride = null;
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  Future<void> publish({bool playing = true, int milliseconds = 0, double speed = 1, bool force = false}) async {
    await manager.updatePlaybackState(
      isPlaying: playing,
      position: Duration(milliseconds: milliseconds),
      speed: speed,
      force: force,
    );
    await Future<void>.delayed(Duration.zero);
  }

  test('Apple ordinary position ticks do not repeatedly activate audio', () async {
    await publish(force: true);
    await publish(milliseconds: 250);
    expect(calls, hasLength(1));
  });

  test('Apple extrapolation skips advancing playback but corrects a stall', () async {
    final elapsed = Stopwatch()..start();
    await publish(force: true);
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    final position = elapsed.elapsedMilliseconds;
    await publish(milliseconds: position);
    expect(calls, hasLength(1));
    await Future<void>.delayed(const Duration(milliseconds: 1100));
    await publish(milliseconds: position);
    expect(calls, hasLength(2));
  });

  test('Apple position discontinuities resynchronise Now Playing', () async {
    await publish(force: true);
    await publish(milliseconds: 20000);
    expect(calls, hasLength(2));
    expect((calls.last.arguments as Map)['position'], 20.0);
  });

  test('pause, rate and explicit seek changes are published', () async {
    await publish(force: true);
    await publish(playing: false, force: true);
    await publish(speed: 2, force: true);
    await publish(milliseconds: 500, speed: 2, force: true);
    expect(calls, hasLength(4));
    expect((calls[1].arguments as Map)['state'], 'paused');
    expect((calls.last.arguments as Map)['position'], 0.5);
  });

  test('clear and suspension invalidate the Apple position anchor', () async {
    await publish(force: true);
    await manager.clear();
    await publish();
    expect(calls.where((c) => c.method == 'setPlaybackState'), hasLength(2));
    manager.suspendUpdates();
    await publish(force: true);
    manager.resumeUpdates();
    await publish(force: true);
    expect(calls.where((c) => c.method == 'setPlaybackState'), hasLength(3));
  });

  test('failed platform update is retried instead of becoming an anchor', () async {
    failNext = true;
    await publish(force: true);
    await publish();
    expect(calls, hasLength(2));
  });

  test('other platforms retain periodic position updates', () async {
    debugDefaultTargetPlatformOverride = TargetPlatform.android;
    await publish(force: true);
    await publish(milliseconds: 250);
    expect(calls, hasLength(2));
  });
  test('seek availability enables both interval commands and resets after clear', () async {
    await manager.setControlsEnabled(canSeek: true);
    expect(
      (calls.firstWhere((c) => c.method == 'enableControls').arguments as List),
      containsAll(['seek', 'skipForward', 'skipBackward']),
    );
    calls.clear();
    await manager.setControlsEnabled(canSeek: true);
    expect(calls, isEmpty);
    await manager.setControlsEnabled();
    expect(
      (calls.firstWhere((c) => c.method == 'disableControls').arguments as List),
      containsAll(['seek', 'skipForward', 'skipBackward']),
    );
    await manager.clear();
    calls.clear();
    await manager.setControlsEnabled(canSeek: true);
    expect(calls.where((c) => c.method == 'enableControls'), hasLength(1));
  });

  test('subtitle publication includes selection, empty tracks and disabled state', () async {
    await manager.updateSubtitleOptions([
      {'id': '3', 'language': 'nl', 'title': 'Nederlands'},
    ], '3');
    expect((calls.last.arguments as Map)['selectedId'], '3');
    await manager.updateSubtitleOptions([], null);
    expect((calls.last.arguments as Map)['options'], isEmpty);
    expect((calls.last.arguments as Map)['selectedId'], isNull);
    manager.suspendUpdates();
    final count = calls.length;
    await manager.updateSubtitleOptions([], null);
    expect(calls, hasLength(count));
  });

  test('system commands retain explicit intent and fractional requested intervals', () {
    final play = MediaControlEvent.fromMap({'type': 'play', 'source': 'commandCenter'});
    expect(play, isA<PlayEvent>());
    expect(play.isSystemCommand, isTrue);
    expect(MediaControlEvent.fromMap({'type': 'pause', 'source': 'commandCenter'}), isA<PauseEvent>());
    expect(MediaControlEvent.fromMap({'type': 'togglePlayPause'}).isSystemCommand, isFalse);
    final forward = MediaControlEvent.fromMap({'type': 'skipForward', 'interval': 7.5});
    final player = _SystemPlayer();
    expect(mediaControlSeekTarget(forward, player, canSeek: true), const Duration(milliseconds: 12500));
    expect(
      mediaControlSeekTarget(const SkipBackwardEvent(Duration(seconds: 10)), player, canSeek: true),
      Duration.zero,
    );
    expect(
      mediaControlSeekTarget(const SkipForwardEvent(Duration(seconds: 90)), player, canSeek: true),
      const Duration(seconds: 20),
    );
    expect(
      mediaControlSeekTarget(const SeekEvent(Duration(seconds: 90)), player, canSeek: true),
      const Duration(seconds: 20),
    );
    expect(mediaControlSeekTarget(forward, player, canSeek: false), isNull);
    expect(mediaControlSeekTarget(const SkipForwardEvent(Duration(seconds: -1)), player, canSeek: true), isNull);
    expect(mediaControlSeekTarget(const SkipForwardEvent(null), player, canSeek: true), isNull);
    final subtitle = MediaControlEvent.fromMap({'type': 'subtitle', 'id': '3', 'enabled': true}) as SubtitleOptionEvent;
    expect(subtitle.id, '3');
    expect(subtitle.enabled, isTrue);
    expect((MediaControlEvent.fromMap({'type': 'subtitle', 'enabled': false}) as SubtitleOptionEvent).enabled, isFalse);
  });
}

class _SystemPlayer implements Player {
  @override
  PlayerState get state => const PlayerState(position: Duration(seconds: 5), duration: Duration(seconds: 20));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}
