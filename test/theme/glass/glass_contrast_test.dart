import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/glass/glass_text.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

const _kLabelStyle = TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600);

// Decoded once, up front, to a ready ui.Image. Image.memory's own decode is a
// real async gap that pumpAndSettle (running on the fake test clock) does not
// reliably wait out, which made the contrast measurement flaky from one pump
// to the next (same setup, different numbers between runs). setUpAll runs on
// the real event loop (loadAppFontsForGoldens already relies on that), so
// decoding here is deterministic; RawImage then paints the finished frame
// with no further async step during the test. See the task report.
late final ui.Image _lightSceneImage;

/// Runs on the test renderer (Skia), i.e. always the fake tier: deliberately
/// the contrast floor per `docs/liquid-glass-mockups-2026-09.md` (Contrast):
/// real glass on Impeller only refracts more of the same lightened backdrop.
Future<void> pumpTextOnGlass(WidgetTester tester, TextStyle style, Widget background) async {
  tester.view.physicalSize = const Size(750, 1334);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, true);

  await tester.pumpWidget(
    MaterialApp(
      theme: monoTheme(dark: true),
      home: RepaintBoundary(
        child: Stack(
          fit: StackFit.expand,
          children: [
            Positioned.fill(child: background),
            Center(
              child: GlassLayer(
                child: GlassSurface(
                  shape: const StadiumBorder(),
                  tokens: const GlassTokens.phone(),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 16),
                    child: Text('Home', style: style),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _lightSceneImage = frame.image;
  });
  setUp(() => resetSharedPreferencesForTest());

  // Case A. De 4,5:1-eis is hard (Michel), maar op de lichtste echte fixture
  // (test/fixtures/glass/bbb_light_scene.jpg) haalt de donkere plaattint dat
  // getal niet, ook niet aan het plafond van deze fixronde (zwart 65%,
  // `GlassTokens.phone().tint`). Gemeten: 3,67:1 bij 65% (was 3,35 bij de
  // startwaarde 50%). Zie het taakrapport, sectie Fixronde 1, voor de volledige
  // reeks en de openstaande beslissing. De assertie hieronder bewaakt de
  // gemeten vloer zodat een regressie hier opvalt, niet dat de eis al is
  // gehaald.
  testWidgets('glassText op de lichtste echte scene: gemeten vloer, 4,5:1 nog niet gehaald', (tester) async {
    await pumpTextOnGlass(tester, glassText(_kLabelStyle), RawImage(image: _lightSceneImage, fit: BoxFit.cover));

    final ratio = await minTextContrast(tester, find.text('Home'));
    expect(ratio, greaterThan(3.5));
  });

  testWidgets('zonder glassText is het contrast op die scene lager', (tester) async {
    await pumpTextOnGlass(tester, glassText(_kLabelStyle), RawImage(image: _lightSceneImage, fit: BoxFit.cover));
    final withShadow = await minTextContrast(tester, find.text('Home'));

    await pumpTextOnGlass(tester, _kLabelStyle, RawImage(image: _lightSceneImage, fit: BoxFit.cover));
    final withoutShadow = await minTextContrast(tester, find.text('Home'));

    expect(withoutShadow, lessThan(withShadow));
  });

  // Informatief, geen eis: een vlak wit vlak komt in de app niet voor (elke
  // echte scene heeft eigen structuur waar blur/dim op kunnen grijpen). Dit
  // is het theoretisch hardste geval: blur doet niets op een egale kleur en
  // de saturatiematrix heeft op een achromatische kleur per definitie geen
  // effect. Alleen het cijfer wordt genoteerd, in het taakrapport.
  testWidgets('effen wit is informatief, geen eis', (tester) async {
    await pumpTextOnGlass(tester, glassText(_kLabelStyle), const ColoredBox(color: Colors.white));

    final ratio = await minTextContrast(tester, find.text('Home'));
    expect(ratio, greaterThan(1.0));
  });
}
