import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/scroll_crown/crown_drag_motion.dart';

void main() {
  test('one continuous crown stroke reaches each exact endpoint at every library size', () {
    for (final count in [100, 1000, 10000]) {
      final max = (count - 1) * 72.0;
      for (final origin in [0.0, 20.0, 250.0, 480.0, 500.0]) {
        for (final target in [0.0, 500.0]) {
          if (target == origin) continue;
          final motion = CrownDragMotion(y: origin, time: Duration.zero);
          final initial = max * .4;
          expect(
            motion.move(y: origin, time: Duration.zero, pixels: initial, minExtent: 0, maxExtent: max, travel: 500),
            initial,
          );
          final actual = motion.move(
            y: target,
            time: const Duration(seconds: 10),
            pixels: initial,
            minExtent: 0,
            maxExtent: max,
            travel: 500,
          );
          expect(actual, target == 0 ? 0 : max, reason: 'full rail means full library in one stroke');
        }
      }
    }
  });

  test('knob grabbed at its real position follows the library fraction without acceleration', () {
    for (final max in [7128.0, 71928.0, 719928.0]) {
      final motion = CrownDragMotion(y: 100, time: Duration.zero);
      var pixels = max * .2;
      for (final fraction in [.2, .25, .5, .75, 1.0, .8, .4, 0.0]) {
        pixels = motion.move(
          y: fraction * 500,
          time: Duration.zero,
          pixels: pixels,
          minExtent: 0,
          maxExtent: max,
          travel: 500,
        );
        expect(pixels, closeTo(max * fraction, .000001));
      }
    }
  });

  test('same position gives same result at every speed and event frequency', () {
    double run(int samples, int micros) {
      final motion = CrownDragMotion(y: 100, time: Duration.zero);
      var pixels = 719928 * .2;
      for (var i = 1; i <= samples; i++) {
        pixels = motion.move(
          y: 100 + 250 * i / samples,
          time: Duration(microseconds: micros * i),
          pixels: pixels,
          minExtent: 0,
          maxExtent: 719928,
          travel: 500,
        );
      }
      return pixels;
    }

    for (final samples in [1, 60, 120]) {
      for (final time in [0, 8333, 1000000]) {
        expect(run(samples, time), closeTo(719928 * .7, .000001));
      }
    }
  });

  test('loading freezes interior scale and a reached bottom follows the live end', () {
    final motion = CrownDragMotion(y: 100, time: Duration.zero);
    var pixels = motion.move(
      y: 250,
      time: Duration.zero,
      pixels: 2000,
      minExtent: 0,
      maxExtent: 10000,
      rangeExtent: 10000,
      travel: 500,
    );
    expect(pixels, 5000);
    pixels = motion.move(
      y: 300,
      time: Duration.zero,
      pixels: pixels,
      minExtent: 0,
      maxExtent: 30000,
      rangeExtent: 10000,
      travel: 500,
    );
    expect(pixels, 6000);
    expect(
      motion.move(
        y: 500,
        time: Duration.zero,
        pixels: pixels,
        minExtent: 0,
        maxExtent: 30000,
        rangeExtent: 10000,
        travel: 500,
      ),
      30000,
    );
  });

  test('holding, returning to grab position, padding and collapsed ranges are stable', () {
    final motion = CrownDragMotion(y: 250, time: Duration.zero);
    var pixels = motion.move(y: 400, time: Duration.zero, pixels: 3000, minExtent: -100, maxExtent: 7000, travel: 500);
    for (var i = 0; i < 3; i++) {
      expect(
        motion.move(
          y: 400,
          time: Duration(seconds: i),
          pixels: pixels,
          minExtent: -100,
          maxExtent: 7000,
          travel: 500,
        ),
        pixels,
      );
    }
    expect(
      motion.move(y: 250, time: Duration.zero, pixels: pixels, minExtent: -100, maxExtent: 7000, travel: 500),
      3000,
    );
    expect(
      motion.move(y: -20, time: Duration.zero, pixels: pixels, minExtent: -100, maxExtent: 7000, travel: 500),
      -100,
    );
    expect(
      motion.move(y: 520, time: Duration.zero, pixels: pixels, minExtent: -100, maxExtent: 7000, travel: 500),
      7000,
    );
    expect(motion.move(y: 400, time: Duration.zero, pixels: 0, minExtent: 0, maxExtent: 0, travel: 500), 0);
  });
}
