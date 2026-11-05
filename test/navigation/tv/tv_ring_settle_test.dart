import 'package:fake_async/fake_async.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/tv/tv_ring_settle.dart';

void main() {
  test('a single move activates at once and once more, idempotently, when the window closes', () {
    fakeAsync((async) {
      var calls = 0;
      final settle = TvRingSettle(activate: () => calls++);
      settle.ringMoved();
      expect(calls, 1);
      async.elapse(kTvRingSettle);
      expect(calls, 2);
      expect(settle.isPending, isFalse);
    });
  });

  test('moves inside the window coalesce into one trailing activation', () {
    fakeAsync((async) {
      var calls = 0;
      final settle = TvRingSettle(activate: () => calls++);
      for (var i = 0; i < 5; i++) {
        settle.ringMoved();
        async.elapse(const Duration(milliseconds: 80));
      }
      expect(calls, 1, reason: 'only the leading edge so far');
      async.elapse(kTvRingSettle);
      expect(calls, 2);
    });
  });

  test('flush activates a pending sweep now and closes the window', () {
    fakeAsync((async) {
      var calls = 0;
      final settle = TvRingSettle(activate: () => calls++);
      settle.ringMoved();
      settle.ringMoved();
      settle.flush();
      expect(calls, 2);
      async.elapse(kTvRingSettle);
      expect(calls, 2, reason: 'the window was closed by the flush');
      settle.flush();
      expect(calls, 2, reason: 'nothing pending, nothing to flush');
    });
  });

  test('without coalescing every move activates and no window stays open', () {
    fakeAsync((async) {
      var calls = 0;
      final settle = TvRingSettle(activate: () => calls++);
      settle.ringMoved();
      settle.ringMoved(coalesce: false);
      settle.ringMoved(coalesce: false);
      expect(calls, 3);
      expect(settle.isPending, isFalse);
      async.elapse(kTvRingSettle);
      expect(calls, 3);
    });
  });
}
