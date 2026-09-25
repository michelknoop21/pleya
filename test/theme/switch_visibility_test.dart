import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';

/// VIS-0925-C: an unselected Switch in Light vanished into its settings card.
/// Material 3's unselected track is surfaceContainerHighest, which this palette
/// maps onto the card surface, and its rim and thumb are the 10% outline.
void main() {
  double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  for (final (name, dark, oled) in [('Light', false, false), ('Dark', true, false), ('OLED', true, true)]) {
    test('$name: an off switch separates from the card it sits on', () {
      final theme = monoTheme(dark: dark, oled: oled);
      final tk = theme.extension<MonoTokens>()!;
      final off = <WidgetState>{};
      final track = Color.alphaBlend(theme.switchTheme.trackColor!.resolve(off)!, tk.surface);
      final thumb = Color.alphaBlend(theme.switchTheme.thumbColor!.resolve(off)!, track);

      expect(ratio(track, tk.surface), greaterThan(1.1), reason: 'track $track on card ${tk.surface}');
      expect(ratio(thumb, track), greaterThan(2), reason: 'thumb $thumb on track $track');
    });
  }

  test('a selected switch keeps Material defaults', () {
    final theme = monoTheme(dark: false);
    final on = {WidgetState.selected};
    expect(theme.switchTheme.trackColor!.resolve(on), isNull);
    expect(theme.switchTheme.thumbColor!.resolve(on), isNull);
  });
}
