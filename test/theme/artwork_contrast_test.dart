import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';

/// Contrast rules for anything that sits on artwork.
///
/// Artwork does not flip with the theme: a poster stays bright in light mode
/// while `text` goes near-black and `bg` goes white. So a scrim built from the
/// page background *brightens* the image instead of dimming it, and dimmed ink
/// that reads as "secondary" white-on-dark reads as washed out black-on-bright.
///
/// Dark mode is the design target and must not move — every assertion below
/// pins the dark value to exactly what it was before the light-mode fork.
void main() {
  MonoTokens tokensOf(ThemeData theme) => theme.extension<MonoTokens>()!;

  final dark = tokensOf(monoTheme(dark: true));
  final oled = tokensOf(monoTheme(dark: true, oled: true));
  final light = tokensOf(monoTheme(dark: false));

  /// WCAG 2.1 relative luminance / contrast ratio, for opaque colours.
  double luminance(Color c) {
    double channel(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
    return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
  }

  double contrast(Color a, Color b) {
    final la = luminance(a);
    final lb = luminance(b);
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  /// [top] composited over [bottom], both treated as opaque backgrounds.
  Color over(Color top, Color bottom) => Color.lerp(bottom, top.withValues(alpha: 1), top.a)!;

  group('isLight', () {
    test('is set for the light theme only', () {
      expect(light.isLight, isTrue);
      expect(dark.isLight, isFalse);
      expect(oled.isLight, isFalse);
    });

    test('does not interpolate — the artwork underneath never crossfades', () {
      expect((dark.lerp(light, 0.49) as MonoTokens).isLight, isFalse);
      expect((dark.lerp(light, 0.51) as MonoTokens).isLight, isTrue);
    });

    test('survives copyWith', () {
      expect(light.copyWith(accent: const Color(0xFF00FF00)).isLight, isTrue);
      expect(dark.copyWith(accent: const Color(0xFF00FF00)).isLight, isFalse);
    });
  });

  group('artworkScrimAlpha', () {
    test('returns the dark value untouched in dark and OLED', () {
      expect(dark.artworkScrimAlpha(dark: 0.92, light: 0.97), 0.92);
      expect(oled.artworkScrimAlpha(dark: 0.7, light: 0.92), 0.7);
    });

    test('returns the light value in light mode', () {
      expect(light.artworkScrimAlpha(dark: 0.92, light: 0.97), 0.97);
    });

    test('scrims wash with the page background, never a hardcoded black', () {
      expect(light.artworkScrim, light.bg);
      expect(dark.artworkScrim, dark.bg);
    });
  });

  group('onArtworkInk', () {
    test('returns the dark alpha untouched in dark and OLED', () {
      expect(dark.onArtworkInk(dark: 0.78, light: 0.95).a, closeTo(0.78, 0.001));
      expect(oled.onArtworkInk(dark: 0.6, light: 0.85).a, closeTo(0.6, 0.001));
    });

    test('keeps more ink in light mode', () {
      expect(light.onArtworkInk(dark: 0.78, light: 0.95).a, closeTo(0.95, 0.001));
    });

    test('uses the theme ink, not a fixed white', () {
      expect(light.onArtwork, light.text);
      expect(dark.onArtwork, dark.text);
    });
  });

  group('WCAG AA over artwork', () {
    // The failure mode in light mode is a *dark* patch of artwork under a
    // white scrim: a thin wash leaves the background dark, and the near-black
    // text on top vanishes into it. A bright patch is the easy case — black
    // ink reads fine there either way — so a dark patch is what to pin.
    const darkArtwork = Color(0xFF101010);

    test('the pre-fix billboard values failed on dark artwork', () {
      // What shipped before: 0.55 wash, 0.7 ink.
      final bg = over(light.artworkScrim.withValues(alpha: 0.55), darkArtwork);
      final ink = over(light.text.withValues(alpha: 0.7), bg);
      expect(contrast(ink, bg), lessThan(4.5));
    });

    test('light hero synopsis clears 4.5:1', () {
      final bg = over(light.artworkScrim.withValues(alpha: 0.97), darkArtwork);
      final ink = over(light.onArtworkInk(dark: 0.7, light: 0.94), bg);
      expect(contrast(ink, bg), greaterThanOrEqualTo(4.5));
    });

    test('light TV nav rail label clears 4.5:1', () {
      final bg = over(light.artworkScrim.withValues(alpha: 0.97), darkArtwork);
      final ink = over(light.text, bg);
      expect(contrast(ink, bg), greaterThanOrEqualTo(4.5));
    });

    test('light rail hub header clears 3:1 for large text', () {
      final bg = over(light.artworkScrim.withValues(alpha: 0.92), darkArtwork);
      final ink = over(light.onArtworkInk(dark: 0.6, light: 0.85), bg);
      expect(contrast(ink, bg), greaterThanOrEqualTo(3.0));
    });

    test('dark mode still clears 4.5:1 on bright artwork', () {
      // The mirror case, proving the dark ramp was already correct and is
      // unchanged: white ink under a black wash over a bright poster.
      const brightArtwork = Color(0xFFFFF4E0);
      final bg = over(dark.artworkScrim.withValues(alpha: 0.92), brightArtwork);
      final ink = over(dark.onArtworkInk(dark: 0.7, light: 0.94), bg);
      expect(contrast(ink, bg), greaterThanOrEqualTo(4.5));
    });
  });
}
