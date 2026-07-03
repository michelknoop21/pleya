import 'package:flutter_test/flutter_test.dart';
import 'package:plezy/utils/blurhash.dart';

void main() {
  test('decodes a valid blurhash to opaque RGBA pixels', () {
    // Reference hash from the BlurHash spec examples.
    const hash = 'LEHV6nWB2yk8pyo0adR*.7kCMdnj';
    final pixels = decodeBlurHashRgba(hash, width: 8, height: 8);
    expect(pixels, isNotNull);
    expect(pixels!.length, 8 * 8 * 4);
    // Every alpha byte is fully opaque.
    for (var i = 3; i < pixels.length; i += 4) {
      expect(pixels[i], 255);
    }
    // Not a flat single color: at least two distinct red values.
    final reds = {for (var i = 0; i < pixels.length; i += 4) pixels[i]};
    expect(reds.length, greaterThan(1));
  });

  test('returns null for malformed hashes', () {
    expect(decodeBlurHashRgba('short'), isNull);
    expect(decodeBlurHashRgba('LEHV6nWB2yk8pyo0adR*'), isNull); // wrong length
  });
}
