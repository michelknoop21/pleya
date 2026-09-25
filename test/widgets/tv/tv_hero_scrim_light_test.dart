import 'dart:math' as math;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_unified_layout.dart';

/// VIS-0925-E: the Light hero scrim got smaller, and the synopsis must still
/// read at 4.5:1 across the whole text column over dark artwork, the case
/// where a white wash over a dark picture leaves dark ink on a dark ground.
void main() {
  const canvasWidth = 1038.0; // DEC-028's canonical Apple TV canvas.
  const scale = 0.85; // `scaleOf` on that canvas.
  const darkArtwork = Color(0xFF101010);
  final tk = monoTheme(dark: false).extension<MonoTokens>()!;

  double ratio(Color a, Color b) {
    final la = a.computeLuminance(), lb = b.computeLuminance();
    return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
  }

  double alphaAt(double f, List<double> stops, List<double> alphas) {
    for (var i = 1; i < stops.length; i++) {
      if (f <= stops[i]) {
        final t = (f - stops[i - 1]) / (stops[i] - stops[i - 1]);
        return alphas[i - 1] + (alphas[i] - alphas[i - 1]) * t;
      }
    }
    return alphas.last;
  }

  test('the synopsis clears 4.5:1 over dark artwork across the text column', () {
    final start = TvDiscoveryLayout.pageInset * scale / canvasWidth;
    final end = (TvDiscoveryLayout.pageInset + TvHomeLayout.heroTextMaxWidth) * scale / canvasWidth;
    var worst = double.infinity;
    for (var f = start; f <= end; f += 0.01) {
      final a = alphaAt(f, TvHomeLayout.heroScrimReadingStopsLight, TvHomeLayout.heroScrimReadingAlphasLight);
      final ground = Color.alphaBlend(tk.artworkScrim.withValues(alpha: a), darkArtwork);
      // The synopsis ink, as `_HeroText` paints it in Light.
      final ink = Color.alphaBlend(tk.onArtworkInk(dark: TvHomeLayout.inkTertiary, light: 0.84), ground);
      worst = math.min(worst, ratio(ink, ground));
    }
    expect(worst, greaterThanOrEqualTo(4.5));
  });

  test('the Light wash is smaller than the dark ramp plus the old +0.08', () {
    // Past the text column the Light ramp releases the picture entirely.
    expect(alphaAt(0.7, TvHomeLayout.heroScrimReadingStopsLight, TvHomeLayout.heroScrimReadingAlphasLight), 0);
    // No wash under the top navigation.
    expect(TvHomeLayout.heroScrimVerticalAlphasLight.first, 0);
    // The ground under the rail stays.
    expect(TvHomeLayout.heroScrimVerticalAlphasLight.last, 1);
  });
}
