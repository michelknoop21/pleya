import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between the text glyphs and the background of the
/// nearest [textFinder] widget, measured on the rendered pixels via
/// [captureImage] — the same primitive golden tests use, so this runs on the
/// test renderer's Skia output (the fake glass tier; see
/// `docs/liquid-glass-mockups-2026-09.md`, Contrast).
///
/// Pixels inside the text's bounding rect with relative luminance above 0.8
/// are treated as glyph pixels (anti-aliased white text is near-white at its
/// core); the rest of the rect is background. The ratio is computed from the
/// two groups' average relative luminance, per WCAG 2.x.
///
/// Runs the actual capture inside [WidgetTester.runAsync]: [captureImage] and
/// [ui.Image.toByteData] settle through a real asynchronous gap that the fake
/// test clock never fires — outside `runAsync` this hangs until the test
/// harness kills the process, exactly like `flutter_test`'s own
/// `matchesGoldenFile` does it internally.
Future<double> minTextContrast(WidgetTester tester, Finder textFinder) async {
  final element = tester.element(textFinder);
  // captureImage renders the nearest RepaintBoundary's paintBounds at a 1:1
  // pixel ratio, in that boundary's local (== global, for a boundary that
  // sits at the screen origin) logical coordinates — not scaled by
  // devicePixelRatio. tester.getRect is already in that same coordinate
  // space, so it maps directly onto image pixels with no scaling.
  final rect = tester.getRect(textFinder);

  final result = await tester.runAsync<({int textCount, int bgCount, double textLumSum, double bgLumSum})>(() async {
    final image = await captureImage(element);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw StateError('captureImage returned no pixel data');
      final pixels = byteData.buffer.asUint8List();

      final left = rect.left.floor().clamp(0, image.width - 1);
      final top = rect.top.floor().clamp(0, image.height - 1);
      final right = rect.right.ceil().clamp(left + 1, image.width);
      final bottom = rect.bottom.ceil().clamp(top + 1, image.height);

      var textLumSum = 0.0;
      var bgLumSum = 0.0;
      var textCount = 0;
      var bgCount = 0;

      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final i = (y * image.width + x) * 4;
          final lum = _relativeLuminance(pixels[i] / 255, pixels[i + 1] / 255, pixels[i + 2] / 255);
          if (lum > 0.8) {
            textLumSum += lum;
            textCount++;
          } else {
            bgLumSum += lum;
            bgCount++;
          }
        }
      }
      return (textCount: textCount, bgCount: bgCount, textLumSum: textLumSum, bgLumSum: bgLumSum);
    } finally {
      image.dispose();
    }
  });

  if (result == null) throw StateError('tester.runAsync returned no result (zone unsupported?)');
  if (result.textCount == 0 || result.bgCount == 0) {
    throw StateError(
      'could not separate text (${result.textCount} px) from background (${result.bgCount} px) in the captured rect',
    );
  }

  final textAvg = result.textLumSum / result.textCount;
  final bgAvg = result.bgLumSum / result.bgCount;
  final lighter = math.max(textAvg, bgAvg);
  final darker = math.min(textAvg, bgAvg);
  return (lighter + 0.05) / (darker + 0.05);
}

double _channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(double r, double g, double b) =>
    0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b);
