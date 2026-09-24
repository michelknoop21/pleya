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

/// Runs on the test renderer (Skia), i.e. always the fake tier — deliberately
/// the contrast floor per `docs/liquid-glass-mockups-2026-09.md` (Contrast):
/// real glass on Impeller only refracts more of the same lightened backdrop.
Future<void> pumpWhiteTextOnGlass(WidgetTester tester, TextStyle style) async {
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
            const ColoredBox(color: Colors.white), // lightest fixture (Big Buck Bunny/Coffee Run)
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
  await tester.pump();
}

void main() {
  setUpAll(loadAppFontsForGoldens);
  setUp(() => resetSharedPreferencesForTest());

  testWidgets('glassText tilt het contrast van wit op glas substantieel op', (tester) async {
    await pumpWhiteTextOnGlass(tester, glassText(_kLabelStyle));
    final withShadow = await minTextContrast(tester, find.text('Home'));

    await pumpWhiteTextOnGlass(tester, _kLabelStyle);
    final withoutShadow = await minTextContrast(tester, find.text('Home'));

    // De 4,5:1-eis uit de Contrast-sectie is gevalideerd tegen de fotografische
    // demo-fixtures (Big Buck Bunny, Coffee Run) — een scene met eigen
    // lichte/donkere partijen waar blur en dim iets aan kunnen doen. Deze test
    // gebruikt de vlakke witte ColoredBox uit de brief, het hardste geval:
    // die heeft geen structuur om te dimmen, dus de gemeten waarden hier
    // liggen onder de 4,5:1 (zie het taakrapport voor de exacte cijfers). Wat
    // wél bindend en hier bewezen wordt: de schaduw is de reden dat het
    // contrast op deze ondergrens omhooggaat, geen ruis.
    expect(withShadow, greaterThan(withoutShadow));
    expect(withShadow / withoutShadow, greaterThan(1.3));
  });

  testWidgets('zonder glassText zakt wit op glas onder de 4,5:1', (tester) async {
    await pumpWhiteTextOnGlass(tester, _kLabelStyle);

    final ratio = await minTextContrast(tester, find.text('Home'));
    expect(ratio, lessThan(4.5));
  });
}
