/// Light text-contrast audit for the TV surfaces touched by VIS-0925, run for
/// Dark and OLED as well so a Light fix cannot regress them.
///
/// Every foreground is measured against each background it actually sits on,
/// composited from the real tokens: page, card, elevated tier, the 5.5% and
/// 13% tile fills, the selected pill, the TV glass plate over a light and a
/// dark hero, and the hero scrim where the CTAs and the badge sit. WCAG AA:
/// 4.5:1 for body text, 3:1 for large text (24 pt or more on the television)
/// and icons. Disabled states are exempt under WCAG and not listed.
///
/// Point sizes: `scaleOf` tokens land at token x 0.85 x 1.85 on an Apple TV
/// (DEC-139, log ekeb2); `TvHig` values are points already.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/utils/tv_hig.dart';
import 'package:pleya/widgets/tv/tv_top_nav_item.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

double _ratio(Color a, Color b) {
  final la = a.computeLuminance(), lb = b.computeLuminance();
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

Color _over(Color fg, Color bg) => Color.alphaBlend(fg, bg);

/// Points on the television for a `scaleOf` token.
double _pt(double token) => token * 0.85 * 1.85;

/// Lowest value of a gradient over [from, to]: the weakest wash under text
/// that spans that range.
double _minAlpha(List<double> stops, List<double> alphas, double from, double to) {
  double at(double f) {
    for (var i = 1; i < stops.length; i++) {
      if (f <= stops[i]) {
        final t = (f - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return alphas[i - 1] + (alphas[i] - alphas[i - 1]) * t;
      }
    }
    return alphas.last;
  }

  var m = double.infinity;
  for (var f = from; f <= to; f += 0.005) {
    m = math.min(m, at(f));
  }
  return m;
}

class _Row {
  _Row(this.element, this.fg, this.bg, this.points, {this.icon = false});
  final String element;
  final Color fg;
  final Color bg;
  final double points;
  final bool icon;
  double get required => icon || points >= 24 ? 3.0 : 4.5;
  // Translucent ink is composited on its background first; luminance ignores alpha.
  double get ratio => _ratio(_over(fg, bg), bg);
}

List<_Row> _audit(MonoTokens tk, GlassTokens glass) {
  final text = tk.text;
  Color ink(double a) => text.withValues(alpha: a);
  final fill55 = _over(ink(TvMyPleyaLayout.tileFillAlpha), tk.bg);
  final fill13Bg = _over(ink(TvMyPleyaLayout.tileFocusedFillAlpha), tk.bg);
  final fill13Surface = _over(ink(TvMyPleyaLayout.tileFocusedFillAlpha), tk.surface);

  // The fake-tier plate (GlassSurface): the backdrop through the dim step,
  // then the tint on top. Saturation is irrelevant on grey heroes.
  Color plateOver(Color hero) {
    final dimmed = Color.from(alpha: 1, red: hero.r * glass.dim, green: hero.g * glass.dim, blue: hero.b * glass.dim);
    return _over(glass.tint, dimmed);
  }

  const lightHero = Color(0xFFF0F0F0);
  const darkHero = Color(0xFF101010);
  // Hero CTAs and the badge sit between 4% and 30% of the width, under the
  // reading scrim; the weakest wash there is the case that counts.
  final stops = tk.isLight ? TvHomeLayout.heroScrimReadingStopsLight : TvHomeLayout.heroScrimReadingStops;
  final alphas = tk.isLight ? TvHomeLayout.heroScrimReadingAlphasLight : TvHomeLayout.heroScrimReadingAlphas;
  final ctaWash = _minAlpha(stops, alphas, 0.04, 0.30);
  final grounds = {
    'dark art': _over(tk.artworkScrim.withValues(alpha: ctaWash), darkHero),
    'bright art': _over(tk.artworkScrim.withValues(alpha: ctaWash), lightHero),
  };
  final pt = TvHig.body; // a Body label, in points

  return [
    _Row('page title, text on bg', text, tk.bg, _pt(TvMyPleyaLayout.pageTitleFontSize)),
    _Row('settings row title on surface', text, tk.surface, pt),
    _Row('settings row title on focused fill', text, fill13Surface, pt),
    _Row('settings row subtitle (textMuted) on surface', tk.textMuted, tk.surface, TvHig.caption1),
    _Row('settings row subtitle (textMuted) on focused fill', tk.textMuted, fill13Surface, TvHig.caption1),
    _Row('section label (textMuted) on bg', tk.textMuted, tk.bg, TvHig.caption2),
    _Row('density label (textMuted) on surface', tk.textMuted, tk.surface, TvHig.caption2),
    _Row('textMuted on elevated', tk.textMuted, tk.surfaceElevated, TvHig.caption2),
    _Row('selected category label (bg on text)', tk.bg, text, pt),
    _Row('idle category label on tile fill', text, fill55, pt),
    _Row('focused category label on 13% fill', text, fill13Bg, pt),
    _Row('hub tile title on fill', text, fill55, pt),
    _Row('hub tile subtitle (tertiary) on fill', ink(TvMyPleyaLayout.inkTertiary), fill55, TvHig.caption1),
    _Row('hub tile subtitle (tertiary) on 13% fill', ink(TvMyPleyaLayout.inkTertiary), fill13Bg, TvHig.caption1),
    _Row('hub icon (secondary) on fill', ink(TvMyPleyaLayout.inkSecondary), fill55, TvHig.body, icon: true),
    _Row(
      'hub group label (tertiary) on bg',
      ink(TvMyPleyaLayout.inkTertiary),
      tk.bg,
      _pt(TvMyPleyaLayout.groupLabelFontSize),
    ),
    _Row(
      'hub header meta (tertiary) on bg',
      ink(TvMyPleyaLayout.inkTertiary),
      tk.bg,
      _pt(TvMyPleyaLayout.headerMetaFontSize),
    ),
    _Row('page body (tertiary) on bg', ink(TvMyPleyaLayout.inkTertiary), tk.bg, _pt(TvMyPleyaLayout.footerFontSize)),
    _Row('topnav inactive (no glass) on bg', ink(TvTopNavLayout.inactiveInk), tk.bg, _pt(TvTopNavLayout.itemFontSize)),
    _Row('topnav active label (bg on text)', tk.bg, text, _pt(TvTopNavLayout.itemFontSize)),
    _Row(
      'topnav inactive on glass over light hero',
      _over(ink(kTvNavGlassInactiveInk), plateOver(lightHero)),
      plateOver(lightHero),
      _pt(TvTopNavLayout.itemFontSize),
    ),
    _Row(
      'topnav inactive on glass over dark hero',
      _over(ink(kTvNavGlassInactiveInk), plateOver(darkHero)),
      plateOver(darkHero),
      _pt(TvTopNavLayout.itemFontSize),
    ),
    _Row('primary CTA label (bg on text)', tk.bg, text, pt),
    for (final MapEntry(key: art, value: ground) in grounds.entries) ...[
      _Row('secondary CTA label on its fill, $art', text, _over(ink(TvHomeLayout.heroSecondaryFillAlpha), ground), pt),
      _Row(
        'badge label on badge fill, $art',
        _over(
          tk.onArtworkInk(dark: TvHomeLayout.inkSecondary, light: 0.92),
          _over(tk.artworkScrim.withValues(alpha: 0.54), ground),
        ),
        _over(tk.artworkScrim.withValues(alpha: 0.54), ground),
        _pt(13.5),
      ),
    ],
    _Row('catalog card title on bg', text, tk.bg, _pt(TvCatalogLayout.cardTitleFontSize)),
    _Row(
      'catalog card meta (secondary) on bg',
      ink(TvCatalogLayout.inkSecondary),
      tk.bg,
      _pt(TvCatalogLayout.cardMetaFontSize),
    ),
    _Row(
      'catalog card third line (tertiary) on bg',
      ink(TvCatalogLayout.inkTertiary),
      tk.bg,
      _pt(TvCatalogLayout.cardMetaFontSize),
    ),
    _Row(
      'section heading count (tertiary) on bg',
      ink(TvDiscoveryLayout.inkTertiary),
      tk.bg,
      _pt(TvDiscoveryLayout.metaContextFontSize),
    ),
    _Row(
      'search pill count (tertiary) on glass over bg',
      _over(ink(TvCatalogLayout.inkTertiary), plateOver(tk.bg)),
      plateOver(tk.bg),
      _pt(TvCatalogLayout.cardMetaFontSize),
    ),
    _Row(
      'source picker status (tertiary) on surface',
      ink(TvSourcePickerLayout.inkTertiary),
      tk.surface,
      _pt(TvSourcePickerLayout.statusFontSize),
    ),
  ];
}

void main() {
  for (final (name, dark, oled) in [('Light', false, false), ('Dark', true, false), ('OLED', true, true)]) {
    testWidgets('$name: every audited text and icon meets WCAG AA on its background', (tester) async {
      late BuildContext ctx;
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: dark, oled: oled),
          home: Builder(
            builder: (c) {
              ctx = c;
              return const SizedBox();
            },
          ),
        ),
      );
      await tester.pumpAndSettle();
      final rows = _audit(tokens(ctx), GlassTokens.tvFor(ctx));
      final table = StringBuffer('| $name | pt | ratio | required |\n');
      for (final r in rows) {
        table.writeln(
          '| ${r.element} | ${r.points.toStringAsFixed(1)} | ${r.ratio.toStringAsFixed(2)} | ${r.required} |',
        );
      }
      // ignore: avoid_print
      print(table);
      final failing = [
        for (final r in rows)
          if (r.ratio < r.required) '${r.element}: ${r.ratio.toStringAsFixed(2)} < ${r.required}',
      ];
      expect(failing, isEmpty);
    });
  }
}
