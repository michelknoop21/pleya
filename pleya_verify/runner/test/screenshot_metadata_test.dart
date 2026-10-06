import 'dart:typed_data';

import 'package:pleya_verify_runner/src/engine/screenshot_metadata.dart';
import 'package:test/test.dart';

void main() {
  test('reads the physical pixel size from a PNG IHDR', () {
    final png = Uint8List.fromList([
      0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a,
      0x00, 0x00, 0x00, 0x0d, 0x49, 0x48, 0x44, 0x52,
      0x00, 0x00, 0x0f, 0x00, // 3840
      0x00, 0x00, 0x08, 0x70, // 2160
    ]);

    expect(pngPixelSize(png), (width: 3840, height: 2160));
  });

  test('returns null for bytes that are not a complete PNG header', () {
    expect(pngPixelSize(Uint8List.fromList([1, 2, 3])), isNull);
  });
}
