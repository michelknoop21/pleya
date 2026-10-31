/// The sort mark of the reference (74ace49c): A to Z reads downward, so the arrow
/// points down, with the lines growing towards its head.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/widgets/mobile/library_sort_glyph.dart';

const double _size = 88;

void main() {
  /// Whether the mark paints the wing of an arrow head near [bottom] or the top.
  Future<bool> paintsNear(WidgetTester tester, {required bool descending, required bool bottom}) async {
    final key = GlobalKey();
    await tester.pumpWidget(
      Center(
        child: RepaintBoundary(
          key: key,
          child: LibrarySortGlyph(descending: descending, color: Colors.white, size: _size),
        ),
      ),
    );
    final byte = await tester.runAsync(() async {
      final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage();
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      // On the left wing, halfway: x = 0.8 - 0.08, y = 0.88 - 0.08 from the head.
      final x = (_size * 0.72).round();
      final y = (_size * (bottom ? 0.80 : 0.20)).round();
      return data!.getUint8((y * image.width + x) * 4 + 3);
    });
    return byte! > 0;
  }

  testWidgets('ascending points down', (tester) async {
    expect(await paintsNear(tester, descending: false, bottom: true), isTrue);
    expect(await paintsNear(tester, descending: false, bottom: false), isFalse);
  });

  testWidgets('descending is the same mark flipped', (tester) async {
    expect(await paintsNear(tester, descending: true, bottom: false), isTrue);
    expect(await paintsNear(tester, descending: true, bottom: true), isFalse);
  });
}
