import 'dart:math' as math;

import 'dart:ui' as ui;

import 'package:flutter/rendering.dart';
import 'package:pleya/media/media_backend.dart';
import 'package:pleya/media/media_item.dart';
import 'package:pleya/media/media_kind.dart';
import 'package:pleya/media/unified/canonical_media_identity.dart';
import 'package:pleya/media/unified/unified_media_group.dart';
import 'package:pleya/media/unified/unified_media_source.dart';
import 'package:pleya/media/unified/unified_watch_state.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/theme/mono_tokens.dart';
import 'package:pleya/widgets/tv/tv_hero_billboard_card.dart';
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

  test('past the text column the Light ramp is never stronger than the dark one', () {
    for (var f = 0.56; f <= 1.0; f += 0.01) {
      final light = alphaAt(f, TvHomeLayout.heroScrimReadingStopsLight, TvHomeLayout.heroScrimReadingAlphasLight);
      final dark = alphaAt(f, TvHomeLayout.heroScrimReadingStops, TvHomeLayout.heroScrimReadingAlphas);
      expect(light, lessThanOrEqualTo(dark + 1e-9), reason: 'at $f');
    }
    // No wash under the top navigation, and the ground under the rail stays.
    expect(TvHomeLayout.heroScrimVerticalAlphasLight.first, 0);
    expect(TvHomeLayout.heroScrimVerticalAlphasLight.last, 1);
  });

  // Michel after the review: a Light hero is as clear as a Dark one, dimmed or
  // not. The dim veil is one strength in every theme.
  for (final (name, dark) in [('Light', false), ('Dark', true)]) {
    testWidgets('$name: the dim veil washes at heroDimAlpha', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: dark),
          home: const TvHeroDimVeil(dim: 1),
        ),
      );
      final veil = tester.widget<ColoredBox>(
        find.descendant(of: find.byType(TvHeroDimVeil), matching: find.byType(ColoredBox)).first,
      );
      expect(veil.color.a, closeTo(TvHomeLayout.heroDimAlpha, 0.005));
    });
  }

  // The artwork outside the text column shows with the same strength in Light
  // as in Dark and OLED: sampled from the painted hero over a mid-grey picture,
  // the scrim alpha across the right 40% at mid height is at most Dark's.
  testWidgets('outside the text column the Light scrim covers no more than the Dark one', (tester) async {
    tester.view.physicalSize = const Size(1038, 584);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    const art = 0x80;

    Future<List<double>> alphasFor({required bool dark, bool oled = false}) async {
      await tester.pumpWidget(
        MaterialApp(
          theme: monoTheme(dark: dark, oled: oled),
          home: RepaintBoundary(
            key: const ValueKey('hero'),
            child: TvHeroBillboardCard(
              group: _group(),
              size: const Size(1038, 584),
              artwork: const ColoredBox(color: Color(0xFF808080)),
              actions: const SizedBox(height: 40),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
      final bg = monoTheme(dark: dark, oled: oled).extension<MonoTokens>()!.bg;
      final boundary = tester.renderObject<RenderRepaintBoundary>(find.byKey(const ValueKey('hero')));
      final bytes = await tester.runAsync(() async {
        final image = await boundary.toImage();
        try {
          return (await image.toByteData(format: ui.ImageByteFormat.rawRgba))!.buffer.asUint8List();
        } finally {
          image.dispose();
        }
      });
      const y = 584 ~/ 2;
      final bgG = (bg.g * 255).round();
      return [
        for (var x = (1038 * 0.6).round(); x < 1038; x += 20) (bytes![(y * 1038 + x) * 4 + 1] - art) / (bgG - art),
      ];
    }

    final light = await alphasFor(dark: false);
    final dark = await alphasFor(dark: true);
    final oled = await alphasFor(dark: true, oled: true);
    for (var i = 0; i < light.length; i++) {
      expect(light[i], lessThanOrEqualTo(dark[i] + 0.02), reason: 'sample $i: light ${light[i]}, dark ${dark[i]}');
      expect(oled[i], closeTo(dark[i], 0.02));
    }
  });
}

UnifiedMediaGroup _group() {
  final item = MediaItem(
    id: 'dune',
    backend: MediaBackend.plex,
    kind: MediaKind.movie,
    title: 'Dune',
    year: 2021,
    summary: 'A noble family becomes embroiled in a war.',
    serverId: 'nas',
    serverName: 'nas',
  );
  final source = UnifiedMediaSource.fromItem(item);
  return UnifiedMediaGroup(
    groupId: 'dune-group',
    identity: canonicalIdentityOf(item) ?? CanonicalMediaIdentity.opaque(),
    sources: [source],
    representativeSourceKey: source.sourceKey,
    watchState: selectRepresentativeWatchState({source.sourceKey: item}),
  );
}
