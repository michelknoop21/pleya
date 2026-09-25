/// Liquid Glass Task 9 (LG-06): the TV search pill on a capsule of fake glass.
///
/// Glass off: today's filled pill. Glass on: the field loses its own fill and
/// sits in one [GlassSurface] (tvOS tokens, stadium), never a
/// `liquid_glass_renderer` widget, at the same size. Contrast is read on the
/// page ground the pill rests on (LG-06: `#141414`) and over the lightest
/// fixture, for when results scroll under it.
library;

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:liquid_glass_renderer/liquid_glass_renderer.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/screens/tv/tv_search_pill.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/platform_detector.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/golden.dart';
import '../../test_helpers/prefs.dart';

late final ui.Image _scene;
const _kSceneKey = Key('scene');

Future<void> _pumpPill(WidgetTester tester, {required bool glass, Widget? background, bool hideText = false}) async {
  tester.view.physicalSize = const Size(1920, 1080);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, glass);
  final theme = monoTheme(dark: true);
  await tester.pumpWidget(
    TranslationProvider(
      child: MaterialApp(
        theme: hideText
            ? theme.copyWith(
                textTheme: theme.textTheme.apply(bodyColor: Colors.transparent, displayColor: Colors.transparent),
              )
            : theme,
        home: RepaintBoundary(
          key: _kSceneKey,
          child: Stack(
            fit: StackFit.expand,
            children: [
              background ?? const ColoredBox(color: Color(0xFF141414)),
              Align(
                alignment: Alignment.topLeft,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(56, 132, 56, 0),
                  child: SizedBox(
                    width: 1808,
                    child: Material(
                      type: MaterialType.transparency,
                      child: TvSearchPill(
                        controller: TextEditingController(text: 'e'),
                        countLabel: '7 results',
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

void main() {
  setUpAll(() async {
    await loadAppFontsForGoldens();
    LocaleSettings.setLocaleSync(AppLocale.en);
    final bytes = File('test/fixtures/glass/bbb_light_scene.jpg').readAsBytesSync();
    _scene = (await (await ui.instantiateImageCodec(bytes)).getNextFrame()).image;
  });

  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
    TvDetectionService.debugSetAppleTVOverride(true);
  });

  tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

  Finder decorator() => find.byType(InputDecorator);

  testWidgets('glas uit: de gevulde pil van vandaag, geen GlassSurface', (tester) async {
    await _pumpPill(tester, glass: false);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(tester.widget<InputDecorator>(decorator()).decoration.filled, isTrue);
    // GlassSurface is in the tree but renders its child bare on the off tier.
    expect(glassTierFor(tester.element(decorator())), GlassTier.off);
  });

  testWidgets('glas aan: één GlassSurface met tvOS-tokens, veld zonder vulling, zelfde maat', (tester) async {
    await _pumpPill(tester, glass: false);
    final off = tester.getRect(decorator());

    await _pumpPill(tester, glass: true);
    final surface = tester.widget<GlassSurface>(find.byType(GlassSurface));
    expect(surface.shape, const StadiumBorder());
    expect(surface.tokens?.blur, const GlassTokens.tv().blur);
    expect(surface.tokens?.edge, const GlassTokens.tv().edge);
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(LiquidGlass), findsNothing);
    expect(find.byType(LiquidGlassLayer), findsNothing);
    expect(tester.widget<InputDecorator>(decorator()).decoration.filled, isFalse);
    expect(tester.getRect(decorator()), off);
    expect(tester.getRect(find.byType(GlassSurface)), off);
  });

  for (final (name, background) in [('op #141414 (ruststand)', null), ('over Big Buck Bunny (scrollend)', 'scene')]) {
    testWidgets('contrast $name: zoekterm 4,5:1', (tester) async {
      Widget? bg() => background == null ? null : RawImage(image: _scene, fit: BoxFit.cover);
      await _pumpPill(tester, glass: true, background: bg());
      final query = find.descendant(of: decorator(), matching: find.text('e'));
      final color = DefaultTextStyle.of(tester.element(query)).style.color ?? Colors.white;

      // Same pill with the text painted transparent: the field inherits its
      // colour from the text theme, so the theme carries the transparency.
      await _pumpPill(tester, glass: true, background: bg(), hideText: true);
      final ratio = await textContrastOverBackground(
        tester,
        area: find.descendant(of: decorator(), matching: find.text('e')),
        textColor: color,
        boundary: find.byKey(_kSceneKey),
      );
      // ignore: avoid_print - the measured ratio belongs in the test log
      print('tv search pill glass contrast $name: $ratio');
      expect(ratio, greaterThanOrEqualTo(4.5));
    });
  }
}
