import 'dart:io';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';

/// WCAG contrast ratio between two opaque colors.
double contrastRatio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return ((la > lb ? la : lb) + 0.05) / ((la > lb ? lb : la) + 0.05);
}

String hexOf(Color c) => '#${(c.toARGB32() & 0xFFFFFF).toRadixString(16).padLeft(6, '0').toUpperCase()}';

/// What a scan across the edge of a focused control found, from the surface
/// outside it inward.
class FocusBand {
  const FocusBand({required this.surface, required this.color, required this.thickness, required this.inner});

  /// The pixel at the far outside end of the scan: what the control stands on.
  final Color surface;

  /// The pixel of the indicator that stands out most against [surface].
  final Color color;

  /// How far the indicator holds at least 3:1 against [surface], in logical
  /// pixels. Zero when nothing on the scan line does.
  final double thickness;

  /// The pixel half a ring width inside the indicator: the white ring on a
  /// light surface, the control itself on a dark one.
  final Color inner;

  double get contrast => contrastRatio(color, surface);

  @override
  String toString() =>
      'band ${hexOf(color)} on ${hexOf(surface)} ${contrast.toStringAsFixed(2)}:1, '
      '${thickness.toStringAsFixed(2)} px, inside it ${hexOf(inner)}';
}

/// One painted frame of the [RepaintBoundary] found by a finder, at the
/// device pixel ratio of the test view.
class FocusFrame {
  FocusFrame._(this._scale, this._width, this._height, this._rgba, this.png, this._origin);

  final double _scale;
  final int _width;
  final int _height;
  final Uint8List _rgba;
  final Uint8List png;
  final Offset _origin;

  static Future<FocusFrame> capture(WidgetTester tester, Finder boundary) async {
    final scale = tester.view.devicePixelRatio;
    final render = tester.renderObject<RenderRepaintBoundary>(boundary);
    final origin = render.localToGlobal(Offset.zero);
    final frame = await tester.runAsync(() async {
      final image = await render.toImage(pixelRatio: scale);
      try {
        final rgba = (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        final png = (await image.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
        return FocusFrame._(scale, image.width, image.height, rgba, png, origin);
      } finally {
        image.dispose();
      }
    });
    return frame!;
  }

  Color _physical(int x, int y) {
    final i = (y.clamp(0, _height - 1) * _width + x.clamp(0, _width - 1)) * 4;
    return Color(0xFF000000 | _rgba[i] << 16 | _rgba[i + 1] << 8 | _rgba[i + 2]);
  }

  /// The pixel under a global logical position.
  Color at(Offset global) {
    final local = (global - _origin) * _scale;
    return _physical(local.dx.floor(), local.dy.floor());
  }

  /// Scans the [side] of [box] at its midpoint, from [outside] logical pixels
  /// outside the box to [inside] logical pixels inside it, and reports the
  /// outermost run of pixels that holds 3:1 against the surface.
  FocusBand band(Rect box, AxisDirection side, {double outside = 12, double inside = 10}) {
    final (Offset edge, Offset inward) = switch (side) {
      AxisDirection.up => (box.topCenter, const Offset(0, 1)),
      AxisDirection.down => (box.bottomCenter, const Offset(0, -1)),
      AxisDirection.left => (box.centerLeft, const Offset(1, 0)),
      AxisDirection.right => (box.centerRight, const Offset(-1, 0)),
    };
    final start = ((edge - inward * outside) - _origin) * _scale;
    // The pixel that holds the scan line on the axis the scan does not move on.
    final sx = start.dx.floor(), sy = start.dy.floor();
    final steps = ((outside + inside) * _scale).round();
    Color pixel(int step) => _physical(sx + (inward.dx * step).round(), sy + (inward.dy * step).round());

    final surface = pixel(0);
    var first = -1, last = -1;
    var color = surface;
    for (var i = 1; i < steps; i++) {
      final p = pixel(i);
      if (contrastRatio(p, surface) >= 3) {
        if (first < 0) first = i;
        last = i;
        if (contrastRatio(p, surface) > contrastRatio(color, surface)) color = p;
      } else if (first >= 0) {
        break;
      }
    }
    if (first < 0) return FocusBand(surface: surface, color: surface, thickness: 0, inner: surface);
    final inner = pixel(last + (1.25 * _scale).round().clamp(2, 1 << 20));
    return FocusBand(surface: surface, color: color, thickness: (last - first + 1) / _scale, inner: inner);
  }

  /// Keeps this frame as `<name>.png` in the directory `PLEYA_SHOT_DIR` names.
  /// Without that variable nothing is written.
  Future<void> keep(WidgetTester tester, String name) async {
    if (Platform.environment['PLEYA_SHOT_DIR'] case final dir?) {
      await tester.runAsync(() => File('$dir/$name.png').writeAsBytes(png));
    }
  }
}
