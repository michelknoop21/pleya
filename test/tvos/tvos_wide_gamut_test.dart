import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  // Keep Flutter surface storage smaller while investigating 4K highwater kills.
  test('the Apple TV renders Flutter without wide gamut', () {
    final plist = File('tvos/Runner/Info.plist').readAsStringSync().replaceAll(RegExp(r'\s+'), '');
    expect(plist, contains('<key>FLTEnableWideGamut</key><false/>'));
  });
}
