// Geometry contracts, not a simulation of human target-selection performance.
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/scroll_crown/crown_drag_motion.dart';
import 'rejected_distance_motion.dart';

void main() {
  test('physically rejected acceleration fails the direct-position contract', () {
    final rejected = RejectedDistanceMotion(y: 100, time: Duration.zero);
    final direct = CrownDragMotion(y: 100, time: Duration.zero);
    const max = 719928.0;
    final expected = max * .8;
    final old = rejected.move(
      y: 400,
      time: const Duration(seconds: 3),
      pixels: max * .2,
      minExtent: 0,
      maxExtent: max,
      travel: 500,
    );
    final current = direct.move(
      y: 400,
      time: const Duration(seconds: 3),
      pixels: max * .2,
      minExtent: 0,
      maxExtent: max,
      travel: 500,
    );
    expect(old, isNot(closeTo(expected, .001)));
    expect(current, closeTo(expected, .001));
  });

  test('equal vertical segments always cover equal library fractions', () {
    for (final count in [100, 1000, 10000]) {
      final max = (count - 1) * 72.0;
      final motion = CrownDragMotion(y: 0, time: Duration.zero);
      var pixels = 0.0;
      for (var i = 1; i <= 10; i++) {
        final before = pixels;
        pixels = motion.move(
          y: 50.0 * i,
          time: Duration(milliseconds: i * i * 100),
          pixels: pixels,
          minExtent: 0,
          maxExtent: max,
          travel: 500,
        );
        expect(pixels - before, closeTo(max / 10, .000001));
      }
    }
  });
}
