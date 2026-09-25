import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/glass/glass_text.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

const _kLabelStyle = TextStyle(color: Colors.white, fontSize: 28, fontWeight: FontWeight.w600);

// A probe found that "invisible" text (color: Colors.transparent, or any
// color equal to the destination) still leaves a few hundred pixels of
// colored antialiasing fringe right at the glyphs' own edges: a real Skia
// LCD-hinting artifact, present regardless of color/alpha (confirmed with
// `foreground: Paint()`, alpha 1, and plain transparent, all identical), and
// absent with no text at all. Against real content (the BBB fixture, or a
// flat white plane) that fringe's luminance (~0.08, i.e. quite dark) never
// competes for the *lightest* 5% p95 targets, so measuring right at the tight
// text rect is safe there. It only bites the flat-*black* sanity case in D,
// where the fringe's small nonzero luminance IS the brightest thing around;
// D uses a wider, key'd area to dilute it under 5%. See the task report,
// Fixronde 2.
const _kSanityAreaKey = Key('sanityArea');
const _kSanityAreaPadding = EdgeInsets.symmetric(horizontal: 32, vertical: 24);

// Decoded once, up front, to a ready ui.Image. Image.memory's own decode is a
// real async gap that pumpAndSettle (running on the fake test clock) does not
// reliably wait out, which made the contrast measurement flaky from one pump
// to the next (same setup, different numbers between runs). setUpAll runs on
// the real event loop (loadAppFontsForGoldens already relies on that), so
// decoding here is deterministic; RawImage then paints the finished frame
// with no further async step during the test. See the task report.
late final ui.Image _lightSceneImage;

/// Common test surface: phone-sized, glass enabled. Runs on the test renderer
/// (Skia), i.e. always the fake tier: deliberately the contrast floor per
/// `docs/liquid-glass-mockups-2026-09.md` (Contrast).
Future<void> _prepare(WidgetTester tester) async {
  tester.view.physicalSize = const Size(750, 1334);
  tester.view.devicePixelRatio = 2;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, true);
  useFakeGlassTier();
}

/// Pumps [background] behind a glass plate (phone tokens, StadiumBorder)
/// carrying `Text('Home', style: style)`. Measuring [style]'s real color
/// requires painting it transparent instead (see `textContrastOverBackground`
/// in `test/test_helpers/contrast.dart`); callers pass that in directly.
/// Measured via the text's own tight rect (`find.text('Home')`): safe here
/// because the real scene (or flat white) always has pixels brighter than the
/// antialiasing fringe's low luminance, see the note on `_kSanityAreaKey`.
Future<void> pumpTextOnGlass(WidgetTester tester, TextStyle style, Widget background) async {
  await _prepare(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: glassPhoneTheme(),
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

/// No glass at all: sanity fixtures for [textContrastOverBackground] itself
/// (case D). Same text, same measurement path, no plate in between; the wider
/// [_kSanityAreaPadding] dilutes the antialiasing fringe for the flat-black
/// leg, where it would otherwise be the brightest thing in the p95 window.
Future<void> pumpTextOnFlatColor(WidgetTester tester, Color background) async {
  await _prepare(tester);
  await tester.pumpWidget(
    MaterialApp(
      theme: glassPhoneTheme(),
      home: RepaintBoundary(
        child: ColoredBox(
          color: background,
          child: Center(
            child: Padding(
              key: _kSanityAreaKey,
              padding: _kSanityAreaPadding,
              child: const Text('Home', style: TextStyle(color: Colors.transparent, fontSize: 28)),
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Future<double> _measureGlass(WidgetTester tester) =>
    textContrastOverBackground(tester, area: find.text('Home'), textColor: Colors.white);

Future<double> _measureSanity(WidgetTester tester) =>
    textContrastOverBackground(tester, area: find.byKey(_kSanityAreaKey), textColor: Colors.white);

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    final codec = await ui.instantiateImageCodec(bytes);
    final frame = await codec.getNextFrame();
    _lightSceneImage = frame.image;
  });
  setUp(() => resetSharedPreferencesForTest());

  // Case A: de eis zelf. glassText's color is forced transparent so the
  // measured background includes its shadow, exactly as it would sit under
  // real white text; textColor: Colors.white supplies the actual text
  // luminance for the ratio.
  testWidgets('A: glassText haalt 4,5:1 op de lichtste echte scene (p95)', (tester) async {
    await pumpTextOnGlass(
      tester,
      glassText(_kLabelStyle).copyWith(color: Colors.transparent),
      RawImage(image: _lightSceneImage, fit: BoxFit.cover),
    );

    final ratio = await _measureGlass(tester);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });

  // Case B: same scene and plate, no shadow at all. Proves the shadow is
  // doing real work, independent of whatever case A's exact number is.
  testWidgets('B: zonder schaduw is het contrast op die scene lager dan A', (tester) async {
    await pumpTextOnGlass(
      tester,
      glassText(_kLabelStyle).copyWith(color: Colors.transparent),
      RawImage(image: _lightSceneImage, fit: BoxFit.cover),
    );
    final withShadow = await _measureGlass(tester);

    await pumpTextOnGlass(
      tester,
      _kLabelStyle.copyWith(color: Colors.transparent),
      RawImage(image: _lightSceneImage, fit: BoxFit.cover),
    );
    final withoutShadow = await _measureGlass(tester);

    expect(withoutShadow, lessThan(withShadow));
  });

  // Case C, informative, no requirement: a flat white plane never occurs in
  // the app (every real scene has structure for blur/dim to act on). This is
  // the theoretical hardest case, blur does nothing to a flat color and the
  // saturation matrix has, by definition, no effect on an achromatic color.
  // Only the number is recorded, in the task report.
  testWidgets('C: effen wit is informatief, geen eis', (tester) async {
    await pumpTextOnGlass(
      tester,
      glassText(_kLabelStyle).copyWith(color: Colors.transparent),
      const ColoredBox(color: Colors.white),
    );

    final ratio = await _measureGlass(tester);
    expect(ratio, greaterThan(1.0));
  });

  // Case D: sanity check for the meter itself, no glass involved. White text
  // on flat black must read near the WCAG maximum (21:1); white text on flat
  // white must read near 1:1 (no contrast at all). If either of these is off,
  // `textContrastOverBackground` itself is broken, not the glass recipe.
  testWidgets('D: sanity, wit op zwart ~21, wit op wit ~1', (tester) async {
    await pumpTextOnFlatColor(tester, Colors.black);
    final onBlack = await _measureSanity(tester);
    expect(onBlack, greaterThan(20));

    await pumpTextOnFlatColor(tester, Colors.white);
    final onWhite = await _measureSanity(tester);
    expect(onWhite, lessThan(1.1));
  });
}
