import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/media_controls_manager.dart';

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
}
