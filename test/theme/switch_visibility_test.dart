import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/platform_detector.dart';
import 'package:pleya/widgets/settings_section.dart';

/// VIS-0925-C: an unselected Switch in Light vanished into its settings card
/// on the tv. Material 3's unselected track is surfaceContainerHighest, which
/// this palette maps onto the card surface, and its rim and thumb are the 10%
/// outline. The fix lives in [TvSettingsDensity], so it only reaches the TV
/// settings rows (review FIX 4): phone and desktop keep Material's switch.
void main() {
  double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  Future<ThemeData> themeUnderDensity(WidgetTester tester, {required bool dark, bool oled = false}) async {
    late ThemeData theme;
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: dark, oled: oled),
        home: TvSettingsDensity(
          child: Builder(
            builder: (context) {
              theme = Theme.of(context);
              return const SizedBox();
            },
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return theme;
  }

  group('on TV', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    for (final (name, dark, oled) in [('Light', false, false), ('Dark', true, false), ('OLED', true, true)]) {
      testWidgets('$name: an off switch separates from the card it sits on', (tester) async {
        final theme = await themeUnderDensity(tester, dark: dark, oled: oled);
        final tk = theme.extension<MonoTokens>()!;
        final off = <WidgetState>{};
        final track = Color.alphaBlend(theme.switchTheme.trackColor!.resolve(off)!, tk.surface);
        final thumb = Color.alphaBlend(theme.switchTheme.thumbColor!.resolve(off)!, track);

        expect(ratio(track, tk.surface), greaterThan(1.1), reason: 'track $track on card ${tk.surface}');
        expect(ratio(thumb, track), greaterThan(2), reason: 'thumb $thumb on track $track');
      });
    }

    testWidgets('selected and disabled keep Material defaults', (tester) async {
      final theme = await themeUnderDensity(tester, dark: false);
      for (final states in [
        {WidgetState.selected},
        {WidgetState.disabled},
        {WidgetState.disabled, WidgetState.selected},
      ]) {
        expect(theme.switchTheme.trackColor!.resolve(states), isNull, reason: '$states');
        expect(theme.switchTheme.thumbColor!.resolve(states), isNull, reason: '$states');
        expect(theme.switchTheme.trackOutlineColor!.resolve(states), isNull, reason: '$states');
      }
    });
  });

  testWidgets('off TV the switch theme is untouched', (tester) async {
    TvDetectionService.debugSetAppleTVOverride(false);
    addTearDown(() => TvDetectionService.debugSetAppleTVOverride(null));
    final theme = await themeUnderDensity(tester, dark: false);
    expect(theme.switchTheme, monoTheme(dark: false).switchTheme);
    expect(theme.switchTheme.trackColor, isNull);
  });
}
