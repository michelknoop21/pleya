import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:pleya_verify_runner/src/driver/screenshot_probe.dart';
import 'package:test/test.dart';

/// Builds a PNG whose pixel data is [fill] repeated — a stand-in for the
/// all-black image `screencapture` writes when it captured nothing.
Uint8List _uniformPng({int width = 64, int height = 64, int fill = 0}) =>
    _png(width, height, List<int>.filled(height * (1 + width * 4), fill));

/// Builds a PNG with varied pixel data, standing in for a real capture.
Uint8List _variedPng({int width = 64, int height = 64}) {
  final raw = <int>[];
  for (var y = 0; y < height; y++) {
    raw.add(0); // filter byte
    for (var x = 0; x < width; x++) {
      raw.addAll([(x * 4) % 256, (y * 7) % 256, (x * y) % 256, 255]);
    }
  }
  return _png(width, height, raw);
}

Uint8List _png(int width, int height, List<int> rawScanlines) {
  final out = BytesBuilder()..add([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]);

  void chunk(String type, List<int> data) {
    final length = ByteData(4)..setUint32(0, data.length);
    out
      ..add(length.buffer.asUint8List())
      ..add(ascii.encode(type))
      ..add(data)
      ..add([0, 0, 0, 0]); // CRC — pngDistinctByteCount does not verify it
  }

  final ihdr = ByteData(13)
    ..setUint32(0, width)
    ..setUint32(4, height)
    ..setUint8(8, 8) // bit depth
    ..setUint8(9, 6); // colour type: RGBA
  chunk('IHDR', ihdr.buffer.asUint8List());
  chunk('IDAT', ZLibEncoder().convert(rawScanlines));
  chunk('IEND', const []);
  return out.takeBytes();
}

void main() {
  group('pngDistinctByteCount', () {
    test('a flat image uses almost no distinct values', () {
      expect(pngDistinctByteCount(_uniformPng()), lessThanOrEqualTo(2));
    });

    test('a varied image uses many', () {
      expect(pngDistinctByteCount(_variedPng()), greaterThan(16));
    });

    test('non-PNG bytes return null rather than claiming blankness', () {
      // An unreadable probe is not evidence of an empty screen, and must not
      // fail a run on its own.
      expect(pngDistinctByteCount(Uint8List.fromList(utf8.encode('not a png'))), isNull);
      expect(pngDistinctByteCount(Uint8List(0)), isNull);
    });
  });

  group('assertNotBlankScreenshot', () {
    test('rejects the all-black capture screencapture writes when it captured nothing', () {
      expect(
        () => assertNotBlankScreenshot(_uniformPng(), context: 'screencapture', hint: 'unlock the display'),
        throwsA(
          isA<BlankScreenshotException>().having(
            (e) => e.message,
            'message',
            allOf(contains('blank capture'), contains('screencapture'), contains('unlock the display')),
          ),
        ),
      );
    });

    test('accepts a real capture', () {
      expect(
        () => assertNotBlankScreenshot(_variedPng(), context: 'simctl io screenshot', hint: 'boot the simulator'),
        returnsNormally,
      );
    });

    test('accepts bytes it cannot parse, rather than failing a run on a probe it does not understand', () {
      expect(
        () =>
            assertNotBlankScreenshot(Uint8List.fromList(utf8.encode('not a png')), context: 'screencapture', hint: ''),
        returnsNormally,
      );
    });
  });

  test('the threshold separates this repo\'s own real and blank bundles', () {
    // Measured, not guessed: the macOS bundles in .build/pleya-verify hold
    // all-black 2560x1440 captures using 4 distinct byte values, while the
    // tvOS ones use all 256. Skipped when no bundles are on disk (a fresh
    // clone, or CI).
    final bundles = Directory('${Directory.current.path}/../../.build/pleya-verify');
    if (!bundles.existsSync()) return;

    final shots = bundles
        .listSync()
        .whereType<Directory>()
        .map((d) => Directory('${d.path}/screenshots'))
        .where((d) => d.existsSync())
        .expand((d) => d.listSync().whereType<File>())
        .where((f) => f.path.endsWith('.png'))
        .toList();
    if (shots.isEmpty) return;

    for (final shot in shots) {
      final distinct = pngDistinctByteCount(shot.readAsBytesSync());
      if (distinct == null) continue;
      expect(
        distinct,
        anyOf(lessThan(8), greaterThan(16)),
        reason: '${shot.path} sits in the ambiguous middle — the threshold needs revisiting',
      );
    }
  });
}
