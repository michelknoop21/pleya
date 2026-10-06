import 'package:pleya_verify_runner/src/driver/ios_simulator_driver.dart';
import 'package:test/test.dart';

void main() {
  test('a pre-rotated iPad viewport satisfies landscape without a host shortcut', () {
    expect(viewportHasOrientation({'width': 1133.0, 'height': 744.0}, 'landscapeLeft'), true);
    expect(viewportHasOrientation({'width': 1133.0, 'height': 744.0}, 'landscapeRight'), true);
    expect(viewportHasOrientation({'width': 744.0, 'height': 1133.0}, 'landscapeLeft'), false);
  });

  test('portrait needs a measured taller-than-wide viewport', () {
    expect(viewportHasOrientation({'width': 744.0, 'height': 1133.0}, 'portrait'), true);
    expect(viewportHasOrientation({'width': 1133.0, 'height': 744.0}, 'portrait'), false);
    expect(viewportHasOrientation({'available': false}, 'portrait'), false);
  });
}
