import 'dart:typed_data';

/// Returns the PNG canvas size from its IHDR chunk without decoding the image.
///
/// Platform screenshots are PNGs, so these two integers are enough to record
/// the physical-pixel half of the viewport-density contract alongside the
/// app's logical `/v1/viewport` measurement.
({int width, int height})? pngPixelSize(Uint8List bytes) {
  const signature = <int>[0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a];
  if (bytes.length < 24) return null;
  for (var i = 0; i < signature.length; i++) {
    if (bytes[i] != signature[i]) return null;
  }
  if (bytes[12] != 0x49 || bytes[13] != 0x48 || bytes[14] != 0x44 || bytes[15] != 0x52) {
    return null;
  }

  final data = ByteData.sublistView(bytes);
  final width = data.getUint32(16);
  final height = data.getUint32(20);
  if (width == 0 || height == 0) return null;
  return (width: width, height: height);
}
