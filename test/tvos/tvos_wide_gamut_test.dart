import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 4K HDR film ran Pleya into the Apple TV's 2 GB per-app limit. When the
  // display reports a wide gamut, Flutter draws BGRA10_XR surfaces (8 bytes a
  // pixel at 3840x2160); off, they are half that. Not yet measured on the device.
  test('the Apple TV renders Flutter without wide gamut', () {
    final plist = File('tvos/Runner/Info.plist').readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(plist, contains('<key>FLTEnableWideGamut</key><false/>'));
  });
}
