import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/video_player/auto_play_countdown.dart';

void main() {
  test('starts idle so the card shows no number before the setting is known', () {
    final countdown = AutoPlayCountdown();
    expect(countdown.remaining, -1);
    expect(countdown.isActive, isFalse);
  });

  test('ticks down to zero and fires exactly one callback', () {
    fakeAsync((async) {
      final countdown = AutoPlayCountdown();
      final ticks = <int>[];
      var elapsed = 0;

      countdown.start(onTick: () => ticks.add(countdown.remaining), onElapsed: () => elapsed++);
      expect(countdown.remaining, 5);
      expect(countdown.isActive, isTrue);

      async.elapse(const Duration(seconds: 10));

      expect(elapsed, 1);
      expect(ticks, [5, 4, 3, 2, 1, -1]);
      expect(countdown.isActive, isFalse);
      expect(countdown.remaining, -1);
    });
  });

  test('cancel stops the countdown and returns to idle', () {
    fakeAsync((async) {
      final countdown = AutoPlayCountdown();
      var elapsed = 0;

      countdown.start(onTick: () {}, onElapsed: () => elapsed++);
      async.elapse(const Duration(seconds: 2));
      expect(countdown.remaining, 3);

      countdown.cancel();
      async.elapse(const Duration(seconds: 30));

      expect(elapsed, 0);
      expect(countdown.isActive, isFalse);
      expect(countdown.remaining, -1);
    });
  });

  test('restarting replaces the running countdown instead of stacking timers', () {
    fakeAsync((async) {
      final countdown = AutoPlayCountdown();
      var elapsed = 0;

      countdown.start(onTick: () {}, onElapsed: () => elapsed++);
      async.elapse(const Duration(seconds: 3));
      countdown.start(onTick: () {}, onElapsed: () => elapsed++);
      expect(countdown.remaining, 5);

      async.elapse(const Duration(seconds: 30));
      expect(elapsed, 1);
    });
  });

  test('honors a custom start value', () {
    fakeAsync((async) {
      final countdown = AutoPlayCountdown(seconds: 2);
      var elapsed = 0;

      countdown.start(onTick: () {}, onElapsed: () => elapsed++);
      async.elapse(const Duration(seconds: 1));
      expect(elapsed, 0);
      async.elapse(const Duration(seconds: 1));
      expect(elapsed, 1);
    });
  });
}
