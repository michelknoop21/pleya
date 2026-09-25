/// J10: hoofdstuk 8's binding rule keeps white as the one TV focus identity
/// everywhere — this covers the contrast fix that lets it stay that way on a
/// light/white surface, rather than resolving J10 by repainting focus black.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/theme/mono_theme.dart';

Widget _themed({required bool dark, required Widget child}) => MaterialApp(
  theme: monoTheme(dark: dark),
  home: Scaffold(body: child),
);

void main() {
  group('FocusTheme.needsContrastSeparator', () {
    testWidgets('is false on the dark palette — the white ring already reads fine', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _themed(
          dark: true,
          child: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(FocusTheme.needsContrastSeparator(ctx), isFalse);
    });

    testWidgets('is true on the light palette, where surface is pure white', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        _themed(
          dark: false,
          child: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );

      expect(FocusTheme.needsContrastSeparator(ctx), isTrue);
    });
  });

  Future<BuildContext> pumpCtx(WidgetTester tester, {required bool dark}) async {
    late BuildContext ctx;
    await tester.pumpWidget(
      _themed(
        dark: dark,
        child: Builder(
          builder: (c) {
            ctx = c;
            return const SizedBox();
          },
        ),
      ),
    );
    // MaterialApp animates a theme change; settle so ctx reads the new one.
    await tester.pumpAndSettle();
    return ctx;
  }

  group('FocusTheme.contrastSeparatorColor', () {
    testWidgets('is the theme\'s own ink color, not an invented brand color', (tester) async {
      final color = FocusTheme.contrastSeparatorColor(await pumpCtx(tester, dark: false));
      // mono_theme.dart's light `text` is 0xFF111111, near-black ink.
      expect(color.r, closeTo(0x11 / 255, 0.01));
      expect(color.g, closeTo(0x11 / 255, 0.01));
      expect(color.b, closeTo(0x11 / 255, 0.01));
      expect(color.a, closeTo(0.55, 0.01));
    });
  });

  // VIS-0925-A: the separator is a stroke, never a shadow. A BoxShadow fills
  // the whole box and darkened every focused tile in Light. The pixel proof
  // lives in focus_ring_fill_pixel_test.dart.
  group('focusDecoration carries the separator as a line, never as a shadow', () {
    testWidgets('no state on any palette carries a shadow', (tester) async {
      for (final dark in [false, true]) {
        final ctx = await pumpCtx(tester, dark: dark);
        for (final focused in [false, true]) {
          expect(FocusTheme.focusDecoration(ctx, isFocused: focused).shadows, isNull);
          expect(FocusTheme.shapeFocusRing(ctx, isFocused: focused, shape: const StadiumBorder()).shadows, isNull);
        }
      }
    });

    testWidgets('a focused ring differs between light and dark only by the separator', (tester) async {
      final light = FocusTheme.focusDecoration(await pumpCtx(tester, dark: false), isFocused: true);
      final dark = FocusTheme.focusDecoration(await pumpCtx(tester, dark: true), isFocused: true);
      expect(light.shape, isNot(dark.shape));
      // Layout is unchanged from the old inside-aligned Border: the ring still
      // reserves its own width, the outside separator reserves nothing.
      expect(light.padding, const EdgeInsets.all(FocusTheme.focusBorderWidth));
      expect(dark.padding, const EdgeInsets.all(FocusTheme.focusBorderWidth));
    });

    testWidgets('an unfocused ring on light is identical to one on dark', (tester) async {
      final light = FocusTheme.focusDecoration(await pumpCtx(tester, dark: false), isFocused: false);
      final dark = FocusTheme.focusDecoration(await pumpCtx(tester, dark: true), isFocused: false);
      expect(light.shape, dark.shape);
    });
  });
}
