import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // A 4K HDR film plus Flutter's wide-gamut surfaces (BGRA10_XR, 8 bytes a
  // pixel at 3840x2160) ran Pleya into the Apple TV's 2 GB per-app limit.
  test('the Apple TV renders Flutter without wide gamut', () {
    final plist = File('tvos/Runner/Info.plist').readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(plist, contains('<key>FLTEnableWideGamut</key><false/>'));
  });
}
