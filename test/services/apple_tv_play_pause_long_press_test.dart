/// DEC-142: a Play/Pause held for 600 ms summons Big P. The down event keeps
/// reaching the player unchanged; the long press fires while still held.
library;

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

  void down(FakeAsync async, {String source = 'presses'}) {
    service.handleMessage({'type': 'play_pause', 'source': source, 'detail': 'playPause'});
    async.flushMicrotasks();
  }

  void up(FakeAsync async) {
    service.handleMessage({'type': 'play_pause_up', 'source': 'presses', 'detail': 'pressesEnded'});
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
      expect(downs, hasLength(1), reason: 'the player still hears the down event, once');
    });
  });

  test('a short press is only the down event', () {
    run((async) {
      down(async);
      async.elapse(const Duration(milliseconds: 200));
      up(async);
      async.elapse(const Duration(seconds: 2));
      expect(longPresses, 0);
      expect(downs.single.source, 'presses');
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

  test('a remote-control event has no release and never counts as held', () {
    run((async) {
      down(async, source: 'remote_control');
      async.elapse(const Duration(seconds: 2));
      expect(longPresses, 0);
      expect(downs, hasLength(1));
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
}
