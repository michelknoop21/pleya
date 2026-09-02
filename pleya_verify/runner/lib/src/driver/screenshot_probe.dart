/// Catches a capture that is not a picture of anything.
///
/// **Why this exists.** `screencapture` on macOS exits 0 and writes a
/// perfectly valid PNG even when it captured nothing — a locked or sleeping
/// display, or a process without Screen Recording permission, yields a solid
/// black image with a zero exit code. The [C5] authoritative screenshot then
/// lands in the evidence bundle, the geometry assertions pass (they read the
/// transport, not the image), and the run reports PASS with a bundle whose
/// visual evidence is worthless.
///
/// That is not hypothetical. Every macOS bundle in this repo from Fase 8
/// onwards — `macos.smoke.boot` included — holds an all-black 2560x1440 PNG,
/// and every one of those runs was green. Nobody noticed, because nothing
/// ever looked at the pixels.
///
/// The check is deliberately crude and one-directional: it only rejects an
/// image with almost no variation at all. Pleya's UI is very dark, so a
/// brightness threshold would be wrong; but even the darkest real screen has
/// text, artwork and antialiasing in it. Measured on this repo's own
/// bundles: real captures use all 256 byte values, blank ones use 4.
library;

import 'dart:io';
import 'dart:typed_data';

/// Thrown when a capture cannot be evidence of anything.
class BlankScreenshotException implements Exception {
  final String message;

  const BlankScreenshotException(this.message);

  @override
  String toString() => 'BlankScreenshotException: $message';
}

/// Distinct byte values below which an image is treated as uniform.
///
/// Real captures in this repo: 256. Blank ones: 4. Anything under this is
/// not a photograph of a user interface.
const int _uniformityThreshold = 16;

/// How many distinct byte values the decompressed pixel data uses, or null
/// when the bytes are not a PNG this can read (in which case the caller
/// should not fail the run — an unreadable probe is not evidence of a blank
/// screen).
int? pngDistinctByteCount(Uint8List bytes) {
  const signature = [0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 8) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }

  final data = ByteData.sublistView(bytes);
  final idat = BytesBuilder();
  var pos = 8;
  while (pos + 8 <= bytes.length) {
    final length = data.getUint32(pos);
    final type = String.fromCharCodes(bytes.sublist(pos + 4, pos + 8));
    final start = pos + 8;
    if (start + length > bytes.length) break;
    if (type == 'IDAT') idat.add(bytes.sublist(start, start + length));
    if (type == 'IEND') break;
    pos = start + length + 4; // + CRC
  }

  final compressed = idat.takeBytes();
  if (compressed.isEmpty) return null;

  try {
    final raw = ZLibDecoder().convert(compressed);
    final seen = <int>{};
    for (final byte in raw) {
      // 16 distinct values is already far past "uniform"; stop early rather
      // than walk 14MB of pixels for an answer that cannot change.
      if (seen.add(byte) && seen.length > _uniformityThreshold) return seen.length;
    }
    return seen.length;
  } catch (_) {
    return null;
  }
}

/// Throws when [bytes] is a PNG with essentially no variation in it.
///
/// [context] names the capture path so the message says which tool produced
/// the empty image, and [hint] carries the platform-specific thing to check.
void assertNotBlankScreenshot(Uint8List bytes, {required String context, required String hint}) {
  final distinct = pngDistinctByteCount(bytes);
  if (distinct == null || distinct > _uniformityThreshold) return;
  throw BlankScreenshotException(
    '$context produced an image with only $distinct distinct byte values — that is a blank capture, '
    'not a screenshot of the app. Refusing to write it as evidence, because a green run with an empty '
    'screenshot is worse than a failed one. $hint',
  );
}
