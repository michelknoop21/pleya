import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// A minimal, valid, uncompressed-content PNG: a solid [width]x[height]
/// RGB square in the given color. No image library involved — a real PNG
/// decoder (Flutter's `Image.memory`/`Image.network` included) reads this
/// correctly; it is small enough to hand-encode: signature, IHDR, one IDAT
/// (zlib-deflated raw scanlines), IEND.
///
/// Used for fixture artwork: same `(width, height, r, g, b)` in always
/// produces the same bytes out, so two runs against the same named fixture
/// hash identically — see `pleya_verify/fixture_server/test/deterministic_png_test.dart`.
List<int> solidColorPng({required int width, required int height, required int r, required int g, required int b}) {
  final builder = BytesBuilder();
  builder.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  builder.add(_chunk('IHDR', _ihdrData(width, height)));
  builder.add(_chunk('IDAT', _idatData(width, height, r, g, b)));
  builder.add(_chunk('IEND', const []));
  return builder.toBytes();
}

List<int> _ihdrData(int width, int height) => [
  ..._uint32(width),
  ..._uint32(height),
  8, // bit depth
  2, // color type 2 = truecolor (RGB, no alpha)
  0, // compression method (the only defined value)
  0, // filter method (the only defined value)
  0, // interlace: none
];

List<int> _idatData(int width, int height, int r, int g, int b) {
  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0); // per-scanline filter type: none
    for (var x = 0; x < width; x++) {
      raw.add([r, g, b]);
    }
  }
  return ZLibEncoder().convert(raw.toBytes());
}

List<int> _chunk(String type, List<int> data) {
  final typeAndData = [...ascii.encode(type), ...data];
  return [..._uint32(data.length), ...typeAndData, ..._uint32(_crc32(typeAndData))];
}

List<int> _uint32(int value) => [(value >> 24) & 0xFF, (value >> 16) & 0xFF, (value >> 8) & 0xFF, value & 0xFF];

/// Standard PNG CRC-32 (polynomial 0xEDB88320), computed directly rather
/// than via `package:crypto` — that package has no CRC-32, only hashes.
int _crc32(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1);
    }
  }
  return crc ^ 0xFFFFFFFF;
}
