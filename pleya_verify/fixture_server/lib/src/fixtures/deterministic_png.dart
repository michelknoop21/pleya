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

/// Calibration artwork: a PNG whose own geometry can be read back off a
/// screenshot, so "how much of this backdrop did the hero throw away" is a
/// measurement instead of an impression.
///
/// [solidColorPng] cannot answer that question. A 32x32 flat square renders
/// identically however hard it is cropped, which is exactly why the hero
/// artwork audit could not use the existing fixtures.
///
/// The image carries three readable features:
///
/// * a **1/10th grid**, so a crop can be counted in tenths of the source
///   without any reference to the request URL;
/// * an **edge band** on each of the four sides, each its own colour, so a
///   missing band names the edge the crop came off;
/// * a **subject block** at [subjectX]/[subjectY] in normalised coordinates,
///   standing in for the face or the title object a real backdrop puts
///   off-centre.
///
/// Deterministic for the same arguments, like everything else in this file.
List<int> calibrationPng({
  required int width,
  required int height,
  required int r,
  required int g,
  required int b,
  double subjectX = 0.5,
  double subjectY = 0.5,
}) {
  const band = 0.04; // edge band thickness, as a fraction of the short side
  final short = width < height ? width : height;
  final bandPx = (short * band).round().clamp(1, short);
  final subjectPx = (short * 0.18).round().clamp(2, short);
  final cx = (subjectX * width).round();
  final cy = (subjectY * height).round();

  final raw = BytesBuilder();
  for (var y = 0; y < height; y++) {
    raw.addByte(0);
    for (var x = 0; x < width; x++) {
      raw.add(_calibrationPixel(x, y, width, height, r, g, b, bandPx, subjectPx, cx, cy));
    }
  }

  final builder = BytesBuilder();
  builder.add(const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  builder.add(_chunk('IHDR', _ihdrData(width, height)));
  builder.add(_chunk('IDAT', ZLibEncoder().convert(raw.toBytes())));
  builder.add(_chunk('IEND', const []));
  return builder.toBytes();
}

List<int> _calibrationPixel(
  int x,
  int y,
  int width,
  int height,
  int r,
  int g,
  int b,
  int bandPx,
  int subjectPx,
  int cx,
  int cy,
) {
  // Subject first: it must win over the grid, because "is the subject still
  // on screen" is the question the whole image exists to answer.
  final dx = x - cx;
  final dy = y - cy;
  if (dx * dx + dy * dy <= subjectPx * subjectPx) return const [255, 255, 255];

  // Edge bands, one colour per side, so a screenshot names the cropped edge.
  if (y < bandPx) return const [255, 0, 0]; // top: red
  if (y >= height - bandPx) return const [0, 128, 255]; // bottom: blue
  if (x < bandPx) return const [0, 200, 0]; // left: green
  if (x >= width - bandPx) return const [255, 220, 0]; // right: yellow

  // Tenth-grid lines over the body fill.
  final lineW = (width / 220).ceil();
  final lineH = (height / 220).ceil();
  for (var i = 1; i < 10; i++) {
    if ((x - (width * i / 10)).abs() < lineW) return const [150, 150, 150];
    if ((y - (height * i / 10)).abs() < lineH) return const [150, 150, 150];
  }
  return [r, g, b];
}
