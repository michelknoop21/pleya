/// J10: hoofdstuk 8's binding rule keeps white as the one TV focus identity
/// everywhere — this covers the contrast fix that lets it stay that way on a
/// light/white surface, rather than resolving J10 by repainting focus black.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/focus/focus_theme.dart';
import 'package:pleya/theme/mono_theme.dart';

Widget _themed({required bool dark, required Widget child}) =>
    MaterialApp(theme: monoTheme(dark: dark), home: Scaffold(body: child));

void main() {
  group('FocusTheme.needsContrastSeparator', () {
    testWidgets('is false on the dark palette — the white ring already reads fine', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: true, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      expect(FocusTheme.needsContrastSeparator(ctx), isFalse);
    });

    testWidgets('is true on the light palette, where surface is pure white', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      expect(FocusTheme.needsContrastSeparator(ctx), isTrue);
    });
  });

  group('FocusTheme.contrastSeparatorShadows', () {
    testWidgets('is the theme\'s own ink color, not an invented brand color', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final shadows = FocusTheme.contrastSeparatorShadows(ctx);

      expect(shadows, isNotEmpty);
      for (final shadow in shadows) {
        // mono_theme.dart's light `text` is 0xFF111111 — near-black ink, the
        // same value used for every other piece of light-theme text.
        expect(shadow.color.r, closeTo(0x11 / 255, 0.01));
        expect(shadow.color.g, closeTo(0x11 / 255, 0.01));
        expect(shadow.color.b, closeTo(0x11 / 255, 0.01));
      }
    });

    testWidgets('is a crisp, tight line, not a soft glow', (tester) async {
      // A soft, wide blur in white-on-white would just read as more white
      // bleeding into white — the opposite of a separator. Zero or near-zero
      // blur is what actually draws a line.
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final shadows = FocusTheme.contrastSeparatorShadows(ctx);

      expect(shadows.every((s) => s.blurRadius <= 2), isTrue);
    });
  });

  group('focusDecoration carries the separator exactly when needed', () {
    testWidgets('a focused ring on light gets the separator shadow', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final decoration = FocusTheme.focusDecoration(ctx, isFocused: true);

      expect(decoration.boxShadow, isNotNull);
      expect(decoration.boxShadow, isNotEmpty);
      // The ring itself never stops being white — J10 is additive, not a
      // second focus color.
      expect(decoration.border, isA<Border>());
      final border = decoration.border as Border;
      expect(border.top.color, Colors.white);
    });

    testWidgets('an unfocused item on light never carries the separator', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final decoration = FocusTheme.focusDecoration(ctx, isFocused: false);

      expect(decoration.boxShadow, isNull);
    });

    testWidgets('a focused ring on dark never carries the separator', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: true, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final decoration = FocusTheme.focusDecoration(ctx, isFocused: true);

      expect(decoration.boxShadow, isNull);
    });
  });

  group('shapeFocusRing carries the separator exactly when needed', () {
    testWidgets('a focused pill on light gets the separator shadow', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final decoration = FocusTheme.shapeFocusRing(ctx, isFocused: true, shape: const StadiumBorder());

      expect(decoration.shadows, isNotNull);
      expect(decoration.shadows, isNotEmpty);
    });

    testWidgets('an unfocused pill on light never carries the separator', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(_themed(dark: false, child: Builder(builder: (c) { ctx = c; return const SizedBox(); })));

      final decoration = FocusTheme.shapeFocusRing(ctx, isFocused: false, shape: const StadiumBorder());

      expect(decoration.shadows, isNull);
    });
  });
}
