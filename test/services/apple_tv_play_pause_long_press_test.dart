/// DEC-142: a Play/Pause held for 600 ms summons Big P. The hold is measured
/// from `play_pause_down`/`play_pause_up`, which station 3
/// (`PleyaFlutterViewController.tvosHandlePress`) sends for every Play/Pause
/// UIPress; the engine's Play/Pause recognizer keeps that press out of
/// `pressesBegan`, so `play_pause` never arrives for it. The hold is no
/// playback action: the player's stream stays silent.
library;

import 'dart:io';

import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/apple_tv_remote_touch_service.dart';
import 'package:pleya/utils/native_input_session.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late AppleTvRemoteTouchService service;
  late List<AppleTvRemotePlayPauseAction> downs;
  late int longPresses;

  void run(void Function(FakeAsync async) body) => fakeAsync((async) {
    service = AppleTvRemoteTouchService(scheduleFrame: () {});
    downs = [];
    longPresses = 0;
    service.playPauseActions.listen(downs.add);
    service.playPauseLongPresses.listen((_) => longPresses++);
    body(async);
  });

  void down(FakeAsync async) {
    service.handleMessage({'type': 'play_pause_down', 'source': 'presses', 'detail': 'tvosHandlePress'});
    async.flushMicrotasks();
  }

  void playbackAction(FakeAsync async, {required String source}) {
    service.handleMessage({'type': 'play_pause', 'source': source, 'detail': 'playPause'});
    async.flushMicrotasks();
  }

  void up(FakeAsync async) {
    service.handleMessage({'type': 'play_pause_up', 'source': 'presses', 'detail': 'tvosHandlePress'});
    async.flushMicrotasks();
  }

  tearDown(NativeInputSession.debugReset);

  test('held for 600 ms fires once, at the mark and before the release', () {
    run((async) {
      down(async);
      async.elapse(const Duration(milliseconds: 599));
      expect(longPresses, 0);
      async.elapse(const Duration(milliseconds: 1));
      expect(longPresses, 1);
      async.elapse(const Duration(seconds: 2));
      up(async);
      expect(longPresses, 1);
      expect(downs, isEmpty, reason: 'the hold is no play/pause for the player');
    });
  });

  test('a short press does not summon', () {
    run((async) {
      down(async);
      async.elapse(const Duration(milliseconds: 200));
      up(async);
      async.elapse(const Duration(seconds: 2));
      expect(longPresses, 0);
    });
  });

  test('a playback action alone never arms the hold, whatever its source', () {
    run((async) {
      playbackAction(async, source: 'presses');
      playbackAction(async, source: 'remote_control');
      async.elapse(const Duration(seconds: 2));
      expect(longPresses, 0);
      expect(downs.map((d) => d.source), ['presses', 'remote_control'], reason: 'the player hears both, unchanged');
    });
  });

  test('a release just before the mark cancels it', () {
    run((async) {
      down(async);
      async.elapse(const Duration(milliseconds: 590));
      up(async);
      async.elapse(const Duration(seconds: 1));
      expect(longPresses, 0);
    });
  });

  test('the release still cancels while the system keyboard is up', () {
    run((async) {
      NativeInputSession.begin();
      down(async);
      async.elapse(const Duration(milliseconds: 100));
      up(async);
      async.elapse(const Duration(seconds: 1));
      expect(longPresses, 0);
    });
  });

  test('a hold that starts during native text entry never summons, even after the keyboard closes', () {
    run((async) {
      NativeInputSession.begin();
      down(async);
      NativeInputSession.end();
      async.elapse(const Duration(seconds: 1));
      expect(longPresses, 0);
    });
  });

  test('station 3 sends the hold, once per delivery, for Play/Pause only', () {
    final swift = File('tvos/Runner/PleyaFlutterViewController.swift').readAsStringSync();
    for (final line in [
      'if !isRepeatDelivery {\n      forwardPlayPauseHold(press)\n    }',
      'guard press.type == .playPause else { return }',
      'case .began:\n      tvRemoteChannel.sendMessage(["type": "play_pause_down", "source": "presses"',
      'case .ended, .cancelled:\n      sendPlayPauseUpEvent(detail: "tvosHandlePress")',
    ]) {
      expect(swift, contains(line));
    }
  });
}
