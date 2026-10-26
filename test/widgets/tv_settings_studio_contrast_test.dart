import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/settings/settings_studio_theme.dart';
import 'package:pleya/widgets/tv/tv_settings_studio_style.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

void main() {
  // A-24 replaces VIS-0925-B. VIS-0925-B drew the chosen category as a full
  // ink pill; the Studio direction makes it a secondary mark (accent bar over a
  // warm fill) so that the ring is the only thing that looks like focus. The
  // ratios below are WCAG contrast of each composite on its own palette.
  group('A-24 Studio rail, rows and switch contrast', () {
    double ratio(Color a, Color b) {
      final la = a.computeLuminance(), lb = b.computeLuminance();
      return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
    }

    for (final (name, dark, oled) in [('Light', false, false), ('Dark', true, false), ('OLED', true, true)]) {
      test(name, () {
        // A-24b: the palette Instellingen wears (warm page in Light).
        final tk = settingsStudioTokens(monoTheme(dark: dark, oled: oled).extension<MonoTokens>()!);
        // Fills are translucent; measure them composited on the page.
        Color fill({required bool selected, required bool focused}) =>
            Color.alphaBlend(tvStudioCategoryFill(tk, selected: selected, focused: focused), tk.bg);
        final selected = fill(selected: true, focused: false);
        final focused = fill(selected: false, focused: true);
        final idle = fill(selected: false, focused: false);
        Color on(Color ink, Color fill) => Color.alphaBlend(ink, fill);

        // The bar is a non-text mark: 3:1 against the fill it sits on.
        expect(ratio(tvStudioMarkerColor(tk), selected), greaterThan(3));
        // The chosen label reads on its fill, the idle labels on the page.
        expect(ratio(on(tvStudioCategoryLabel(tk, selected: true), selected), selected), greaterThan(7));
        expect(ratio(on(tvStudioCategoryLabel(tk, selected: false), idle), idle), greaterThan(4.5));
        // The chosen fill separates from the page, and from a focused pill.
        expect(ratio(selected, idle), greaterThan(1.1));
        expect(selected, isNot(focused));
        // The focus indicator stands out against the chosen fill: the white
        // ring in Dark and OLED, its dark separator band in Light.
        final ring = tk.isLight ? tk.text : Colors.white;
        expect(ratio(ring, selected), greaterThan(3));
        // Eyebrow, and the row's value and description ink at the alphas
        // `tv_settings_rows.dart` paints, on a focused and an idle row.
        expect(ratio(tvStudioEyebrow(tk), tk.bg), greaterThan(4.5));
        final row = Color.alphaBlend(tvStudioRowFill(tk, focused: true), tk.bg);
        final idleRow = Color.alphaBlend(tvStudioRowFill(tk, focused: false), tk.bg);
        for (final fill in [row, idleRow]) {
          expect(ratio(on(tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary), fill), fill), greaterThan(4.5));
          expect(ratio(on(tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary), fill), fill), greaterThan(4.5));
        }
        expect(ratio(tk.isLight ? tk.text : Colors.white, row), greaterThan(3));
        // The switch in a row (anchor 02): its on-track is a non-text mark
        // on the page and on a focused row.
        expect(ratio(settingsStudioSwitchColor(tk), tk.bg), greaterThan(3));
        expect(ratio(settingsStudioSwitchColor(tk), row), greaterThan(3));
        // Coral as text (destructive titles, "Live voorbeeld"): 4.5:1 on the
        // page, the card, a focused row and, in Light, the warm #F1E8E3 fill.
        final text = settingsStudioTextCoral(tk);
        for (final under in [tk.bg, tk.surface, row, if (tk.isLight) const Color(0xFFF1E8E3)]) {
          expect(ratio(text, under), greaterThan(4.5), reason: '$name coral text on $under');
        }
      });
    }
  });
}
