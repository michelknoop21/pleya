/// Pixel checks on `CatalogTopPanel`: the tint has to cover the panel's full
/// width and run out gradually over the tail. A layout slip (a tint laid out
/// zero pixels wide) is invisible to every geometry test of the panel itself,
/// so these read back what was painted.
library;

import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/home/mobile_catalog_widgets.dart';

void main() {
  const contentHeight = 100.0;

  /// Paints the panel in black over a pure red page and returns the red
  /// channel down one column of pixels.
  Future<List<int>> redDown(WidgetTester tester, {required double x}) async {
    final boundary = GlobalKey();
    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: boundary,
          child: Stack(
            children: [
              const Positioned.fill(child: ColoredBox(color: Color(0xFFFF0000))),
              Positioned(
                top: 0,
                left: 0,
                right: 0,
                child: CatalogTopPanel(
                  collapsed: false,
                  background: Colors.black,
                  measureKey: GlobalKey(),
                  child: const SizedBox(height: contentHeight),
                ),
              ),
            ],
          ),
        ),
      ),
    );
    final bytes = await tester.runAsync(() async {
      final image = await (boundary.currentContext!.findRenderObject()! as RenderRepaintBoundary).toImage();
      final data = await image.toByteData();
      return (image.width, data!);
    });
    final (width, ByteData data) = bytes!;
    final bottom = (contentHeight + CatalogTopPanel.fadeTail + 4).toInt();
    return [for (var y = 0; y < bottom; y++) data.getUint8((y * width + x.toInt()) * 4)];
  }

  testWidgets('the tint covers the full width of the panel', (tester) async {
    for (final x in [2.0, 400.0, 797.0]) {
      final red = await redDown(tester, x: x);
      expect(red[50], lessThan(90), reason: 'the page shows through the panel at x=$x only dimmed: ${red[50]}');
    }
  });

  testWidgets('the lower edge runs out gradually instead of ending in a line', (tester) async {
    final red = await redDown(tester, x: 400);
    final tail = red.sublist(contentHeight.toInt(), (contentHeight + CatalogTopPanel.fadeTail).toInt());
    expect(tail.first, lessThan(120), reason: 'the tail starts close to the panel tint: $tail');
    expect(tail.last, greaterThan(230), reason: 'and ends close to the page: $tail');
    for (var i = 1; i < tail.length; i++) {
      expect(tail[i], greaterThanOrEqualTo(tail[i - 1]), reason: 'never darker further down: $tail');
      expect(tail[i] - tail[i - 1], lessThan(70), reason: 'no single step carries the edge: $tail');
    }
    expect(red.last, 255, reason: 'below the tail the page is untouched');
  });
}
