import 'dart:io';

import 'package:pleya_verify_fixture_server/src/fixtures/deterministic_png.dart';
import 'package:test/test.dart';

void main() {
  test('starts with the PNG signature', () {
    final bytes = solidColorPng(width: 8, height: 8, r: 10, g: 20, b: 30);
    expect(bytes.take(8).toList(), const [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A]);
  });

  test('the IHDR chunk carries the requested width, height and an RGB color type', () {
    final bytes = solidColorPng(width: 12, height: 7, r: 1, g: 2, b: 3);
    // Chunk layout: 4-byte length, 4-byte type, data, 4-byte CRC. IHDR is the
    // first chunk, right after the 8-byte signature.
    final ihdrData = bytes.sublist(16, 16 + 13);
    final width = (ihdrData[0] << 24) | (ihdrData[1] << 16) | (ihdrData[2] << 8) | ihdrData[3];
    final height = (ihdrData[4] << 24) | (ihdrData[5] << 16) | (ihdrData[6] << 8) | ihdrData[7];
    expect(width, 12);
    expect(height, 7);
    expect(ihdrData[8], 8, reason: 'bit depth');
    expect(ihdrData[9], 2, reason: 'color type 2 = truecolor RGB, no alpha');
  });

  test('every chunk CRC is correct — a real decoder checks this', () {
    final bytes = solidColorPng(width: 4, height: 4, r: 100, g: 150, b: 200);
    var offset = 8;
    while (offset < bytes.length) {
      final length = (bytes[offset] << 24) | (bytes[offset + 1] << 16) | (bytes[offset + 2] << 8) | bytes[offset + 3];
      final chunkStart = offset + 4;
      final typeAndData = bytes.sublist(chunkStart, chunkStart + 4 + length);
      final storedCrc = bytes.sublist(chunkStart + 4 + length, chunkStart + 4 + length + 4);
      expect(storedCrc, _crc32Bytes(typeAndData), reason: 'CRC mismatch at chunk offset $offset');
      offset = chunkStart + 4 + length + 4;
    }
    expect(offset, bytes.length, reason: 'chunks must exactly tile the file with no trailing bytes');
  });

  test('the same color in produces byte-identical output every time', () {
    final a = solidColorPng(width: 16, height: 16, r: 5, g: 6, b: 7);
    final b = solidColorPng(width: 16, height: 16, r: 5, g: 6, b: 7);
    expect(a, b);
  });

  test('a different color produces different bytes', () {
    final a = solidColorPng(width: 16, height: 16, r: 5, g: 6, b: 7);
    final b = solidColorPng(width: 16, height: 16, r: 8, g: 9, b: 10);
    expect(a, isNot(b));
  });

  test('the IDAT payload decompresses back to the exact filter-0 scanlines expected', () {
    const width = 3;
    const height = 2;
    final bytes = solidColorPng(width: width, height: height, r: 9, g: 8, b: 7);
    final ihdrLength = (bytes[8] << 24) | (bytes[9] << 16) | (bytes[10] << 8) | bytes[11];
    final idatOffset = 8 + 4 + 4 + ihdrLength + 4; // signature + IHDR chunk
    final idatLength =
        (bytes[idatOffset] << 24) |
        (bytes[idatOffset + 1] << 16) |
        (bytes[idatOffset + 2] << 8) |
        bytes[idatOffset + 3];
    final idatData = bytes.sublist(idatOffset + 8, idatOffset + 8 + idatLength);
    final raw = ZLibDecoder().convert(idatData);

    final expected = <int>[];
    for (var y = 0; y < height; y++) {
      expected.add(0);
      for (var x = 0; x < width; x++) {
        expected.addAll([9, 8, 7]);
      }
    }
    expect(raw, expected);
  });
}

List<int> _crc32Bytes(List<int> bytes) {
  var crc = 0xFFFFFFFF;
  for (final byte in bytes) {
    crc ^= byte;
    for (var i = 0; i < 8; i++) {
      crc = (crc & 1) != 0 ? (crc >> 1) ^ 0xEDB88320 : (crc >> 1);
    }
  }
  crc ^= 0xFFFFFFFF;
  return [(crc >> 24) & 0xFF, (crc >> 16) & 0xFF, (crc >> 8) & 0xFF, crc & 0xFF];
}
