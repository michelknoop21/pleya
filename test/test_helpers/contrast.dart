import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG-style contrast between [textColor] and the background painted behind
/// [area] (glass, blur, tint, shadows), read directly from pixels.
///
/// This does not classify pixels as "text" vs "background" by luminance
/// (Fixronde 1's approach): a glyph's anti-aliased edge sits at luminance
/// 0.3..0.8, a no-man's-land that used to get counted as background and
/// permanently capped the measured ratio around 3.3-3.7 regardless of the
/// plate's actual tint (see the task report, Fixronde 2). Instead, the caller
/// pumps the *same* layout with the target text painted fully transparent
/// (`color: Colors.transparent` in its `TextStyle`, shadows left in place: a
/// probe confirmed Flutter still paints `TextStyle.shadows` when `color` is
/// transparent, so the glyph's own shadow is part of what gets measured as
/// background, same as it would be with real text on top of it). [area] is
/// the `Finder` for that invisible text, so its rect matches exactly what the
/// real, visible text would occupy. Text luminance comes directly from
/// [textColor]: a flat color has one relative luminance, no pixels to sample.
///
/// [percentile] (default 0.95) turns the sampled background pixels into one
/// representative luminance: the value below which that fraction of pixels
/// falls. 0.95 means the lightest 5% of the background sets the bar, a
/// deliberately conservative pick for light text (worst case against a
/// bright pocket of the scene) without letting one stray bright pixel (a
/// literal max()) dominate the result.
///
/// [boundary] picks the `RepaintBoundary` to capture from when [area] has a
/// nearer one of its own (a `NavigationBar` label does): pass a finder for a
/// boundary at the screen origin, so its pixels line up with global rects.
///
/// Runs the actual capture inside [WidgetTester.runAsync]: [captureImage] and
/// [ui.Image.toByteData] settle through a real asynchronous gap that the fake
/// test clock never fires; outside `runAsync` this hangs until the test
/// harness kills the process, exactly like `flutter_test`'s own
/// `matchesGoldenFile` does it internally.
Future<double> textContrastOverBackground(
  WidgetTester tester, {
  required Finder area,
  required Color textColor,
  double percentile = 0.95,
  Finder? boundary,
}) async {
  final element = tester.element(boundary ?? area);
  // captureImage renders the nearest RepaintBoundary's paintBounds at a 1:1
  // pixel ratio, in that boundary's local (== global, for a boundary that
  // sits at the screen origin) logical coordinates: not scaled by
  // devicePixelRatio. tester.getRect is already in that same coordinate
  // space, so it maps directly onto image pixels with no scaling.
  final rect = tester.getRect(area);

  final bgLuminances = await tester.runAsync<List<double>>(() async {
    final image = await captureImage(element);
    try {
      final byteData = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      if (byteData == null) throw StateError('captureImage returned no pixel data');
      final pixels = byteData.buffer.asUint8List();

      final left = rect.left.floor().clamp(0, image.width - 1);
      final top = rect.top.floor().clamp(0, image.height - 1);
      final right = rect.right.ceil().clamp(left + 1, image.width);
      final bottom = rect.bottom.ceil().clamp(top + 1, image.height);

      final values = <double>[];
      for (var y = top; y < bottom; y++) {
        for (var x = left; x < right; x++) {
          final i = (y * image.width + x) * 4;
          values.add(_relativeLuminance(pixels[i] / 255, pixels[i + 1] / 255, pixels[i + 2] / 255));
        }
      }
      return values;
    } finally {
      image.dispose();
    }
  });

  if (bgLuminances == null || bgLuminances.isEmpty) {
    throw StateError('no background pixels captured in $rect');
  }

  bgLuminances.sort();
  final index = ((bgLuminances.length - 1) * percentile).round().clamp(0, bgLuminances.length - 1);
  final bgLuminance = bgLuminances[index];

  final textLuminance = _relativeLuminance(textColor.red / 255, textColor.green / 255, textColor.blue / 255);

  final lighter = math.max(bgLuminance, textLuminance);
  final darker = math.min(bgLuminance, textLuminance);
  return (lighter + 0.05) / (darker + 0.05);
}

double _channel(double c) => c <= 0.03928 ? c / 12.92 : math.pow((c + 0.055) / 1.055, 2.4).toDouble();

double _relativeLuminance(double r, double g, double b) =>
    0.2126 * _channel(r) + 0.7152 * _channel(g) + 0.0722 * _channel(b);
