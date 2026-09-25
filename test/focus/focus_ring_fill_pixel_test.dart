/// VIS-0925-A: in Light a focused menu tile must keep its own 13% fill.
///
/// Build 303 on the Apple TV showed focused tiles at ~#555 with dark text on
/// them: the J10 separator was a `BoxShadow`, and `BoxDecoration` paints a
/// shadow as a filled box under the whole decoration, so 55% ink shone through
/// the tile's translucent fill. This reads the pixel in the middle of a focused
/// tile and compares it with the fill composited on the page background.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

const _tileKey = ValueKey('tile');
const _boundaryKey = ValueKey('boundary');

Widget _scene({required bool dark, bool oled = false, required FocusNode node}) => MaterialApp(
  theme: monoTheme(dark: dark, oled: oled),
  home: InputModeTracker(
    child: Scaffold(
      body: Center(
        child: RepaintBoundary(
          key: _boundaryKey,
          // The boundary captures only what it paints itself, so it carries
          // the page background under the tile.
          child: Builder(
            builder: (context) => ColoredBox(
              color: tokens(context).bg,
              child: Padding(padding: const EdgeInsets.all(20), child: _tile(node)),
            ),
          ),
        ),
      ),
    ),
  ),
);

Widget _tile(FocusNode node) => SizedBox(
  width: 200,
  height: 100,
  child: Builder(
    builder: (context) {
      final tk = tokens(context);
      return FocusableWrapper(
        focusNode: node,
        onSelect: () {},
        disableScale: true,
        borderRadius: 10 + TvMyPleyaLayout.tileFocusRingGap,
        child: Padding(
          padding: const EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap),
          child: Container(
            key: _tileKey,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              color: tk.text.withValues(alpha: TvMyPleyaLayout.tileFocusedFillAlpha),
            ),
          ),
        ),
      );
    },
  ),
);

Future<Color> _pixelAt(WidgetTester tester, Offset global) async {
  final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundaryKey));
  final origin = boundary.localToGlobal(Offset.zero);
  final local = global - origin;
  final bytes = await tester.runAsync(() async {
    final image = await boundary.toImage();
    try {
      final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
      final i = (local.dy.floor() * image.width + local.dx.floor()) * 4;
      final list = data!.buffer.asUint8List();
      return [list[i], list[i + 1], list[i + 2], list[i + 3]];
    } finally {
      image.dispose();
    }
  });
  return Color.fromARGB(bytes![3], bytes[0], bytes[1], bytes[2]);
}

Future<(Color, Color, Color)> _focusedTile(WidgetTester tester, {required bool dark, bool oled = false}) async {
  final node = FocusNode();
  addTearDown(node.dispose);
  await tester.pumpWidget(_scene(dark: dark, oled: oled, node: node));
  // A navigation key puts InputModeTracker in keyboard mode: the ring only
  // shows during D-pad navigation.
  await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
  node.requestFocus();
  await tester.pumpAndSettle();
  expect(node.hasFocus, isTrue);

  final context = tester.element(find.byKey(_tileKey));
  final tk = tokens(context);
  final expected = Color.alphaBlend(tk.text.withValues(alpha: TvMyPleyaLayout.tileFocusedFillAlpha), tk.bg);
  final rect = tester.getRect(find.byKey(_tileKey));
  final center = await _pixelAt(tester, rect.center);
  // The wrapper's outermost pixel: an inside ring keeps its Light separator
  // there, in the band outside the ring (review FIX 2).
  final wrapper = tester.getRect(find.byType(FocusableWrapper));
  final outside = await _pixelAt(tester, Offset(wrapper.center.dx, wrapper.top + 0.5));
  return (center, expected, outside);
}

int _channelDelta(Color a, Color b) => [
  ((a.r - b.r) * 255).round().abs(),
  ((a.g - b.g) * 255).round().abs(),
  ((a.b - b.b) * 255).round().abs(),
].reduce((x, y) => x > y ? x : y);

void main() {
  testWidgets('Light: the middle of a focused tile is exactly its 13% fill on the page', (tester) async {
    final (center, expected, outside) = await _focusedTile(tester, dark: false);
    expect(_channelDelta(center, expected), lessThanOrEqualTo(2), reason: 'center $center, fill $expected');
    // The separator still exists: a dark line on the ring's outer edge.
    expect(outside.computeLuminance(), lessThan(0.5), reason: 'separator pixel $outside');
  });

  testWidgets('Dark: the middle of a focused tile is its fill, no separator', (tester) async {
    final (center, expected, outside) = await _focusedTile(tester, dark: true);
    expect(_channelDelta(center, expected), lessThanOrEqualTo(2), reason: 'center $center, fill $expected');
    // No separator in Dark: the outermost pixel is the white ring itself.
    expect(outside.computeLuminance(), greaterThan(0.9));
  });

  testWidgets('OLED: the middle of a focused tile is its fill', (tester) async {
    final (center, expected, _) = await _focusedTile(tester, dark: true, oled: true);
    expect(_channelDelta(center, expected), lessThanOrEqualTo(2), reason: 'center $center, fill $expected');
  });
}
