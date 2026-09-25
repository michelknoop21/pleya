/// VIS-0925 recheck item 5: a ring-mode [FocusableWrapper] paints its ring in
/// the background `decoration`, and the child covers everything inside the
/// ring's reserved band. The full 2.5 px of white ring must stay visible
/// around an opaque child in every theme; the Light separator sits outside the
/// box, as the shadow it replaced did.
library;

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/focus/focusable_wrapper.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/theme/mono_theme.dart';

const _boundary = ValueKey('boundary');
const _child = ValueKey('child');

void main() {
  for (final dark in [false, true]) {
    testWidgets('the whole ring shows around an opaque child (dark: $dark)', (tester) async {
      final node = FocusNode();
      addTearDown(node.dispose);
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: dark),
          home: InputModeTracker(
            child: Scaffold(
              body: Center(
                child: RepaintBoundary(
                  key: _boundary,
                  child: Builder(
                    builder: (context) => ColoredBox(
                      color: Theme.of(context).scaffoldBackgroundColor,
                      child: Padding(
                        padding: const EdgeInsets.all(20),
                        child: FocusableWrapper(
                          focusNode: node,
                          onSelect: () {},
                          disableScale: true,
                          child: const SizedBox(
                            key: _child,
                            width: 160,
                            height: 60,
                            // Opaque and mid-grey: neither the ring nor the
                            // separator can hide in it.
                            child: ColoredBox(color: Color(0xFF808080)),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
      await tester.sendKeyEvent(LogicalKeyboardKey.arrowDown);
      node.requestFocus();
      await tester.pumpAndSettle();

      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(_boundary));
      final origin = boundary.localToGlobal(Offset.zero);
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return (image.width, (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List());
        } finally {
          image.dispose();
        }
      });
      int green(Offset global) {
        final l = global - origin;
        return bytes!.$2[(l.dy.floor() * bytes.$1 + l.dx.floor()) * 4 + 1];
      }

      final wrapper = tester.getRect(find.byType(FocusableWrapper));
      final x = wrapper.center.dx;
      // The ring's band is the wrapper's outer 2.5 px, all white.
      for (final dy in [0.5, 1.5]) {
        expect(green(Offset(x, wrapper.top + dy)), greaterThan(240), reason: 'ring pixel at +$dy');
      }
      expect(
        tester.getRect(find.byKey(_child)).top - wrapper.top,
        closeTo(FocusTheme.focusBorderWidth, 0.01),
        reason: 'the child is inset by the ring width, not more',
      );
      // Light: the separator is directly outside; Dark: the page.
      final outside = green(Offset(x, wrapper.top - 0.5));
      if (dark) {
        expect(outside, lessThan(40));
      } else {
        expect(outside, lessThan(140), reason: 'separator pixel');
      }
    });
  }
}
