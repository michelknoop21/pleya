/// The back/more circles on the detail hero sit straight on the poster. In
/// the light theme their glyph is dark ink, so the button has to bring its
/// own light backdrop: contrast may not depend on the artwork (DEC-140). The
/// scene here is solid black, the worst case for dark ink. Dark and OLED keep
/// the old look: no backdrop of their own, white glyph, default glass.
library;

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/screens/media_detail/mobile_detail_hero.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/glass/glass_surface.dart';
import 'package:pleya/theme/glass/glass_text.dart';
import 'package:pleya/theme/mono_theme.dart';

import '../../test_helpers/contrast.dart';
import '../../test_helpers/glass_phone.dart';
import '../../test_helpers/prefs.dart';

double _luminance(Color c) {
  double ch(double v) => v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4).toDouble();
  return 0.2126 * ch(c.r) + 0.7152 * ch(c.g) + 0.0722 * ch(c.b);
}

double _contrast(Color a, Color b) {
  final la = _luminance(a), lb = _luminance(b);
  return (math.max(la, lb) + 0.05) / (math.min(la, lb) + 0.05);
}

const _sceneKey = Key('scene');
const _backKey = Key('back');

Future<void> _pump(WidgetTester tester, ThemeData theme, {Color? glyph}) async {
  await tester.pumpWidget(
    MaterialApp(
      theme: theme.copyWith(platform: TargetPlatform.iOS),
      home: RepaintBoundary(
        key: _sceneKey,
        child: Material(
          color: Colors.black,
          child: MobileDetailHeroBar(
            leading: GlassCircleButton(
              key: _backKey,
              icon: Icons.arrow_back_rounded,
              tooltip: 'Back',
              foregroundColor: glyph,
              onPressed: () {},
            ),
          ),
        ),
      ),
    ),
  );
  await tester.pumpAndSettle();
}

Finder get _icon => find.descendant(of: find.byKey(_backKey), matching: find.byType(Icon));

GlassSurface _surface(WidgetTester tester) =>
    tester.widget<GlassSurface>(find.descendant(of: find.byKey(_backKey), matching: find.byType(GlassSurface)));

/// The circle fill the button paints itself when glass is off.
Color? _plainBackdrop(WidgetTester tester) {
  final boxes = tester.widgetList<DecoratedBox>(
    find.descendant(of: find.byKey(_backKey), matching: find.byType(DecoratedBox)),
  );
  for (final b in boxes) {
    final d = b.decoration;
    if (d is ShapeDecoration && d.shape is CircleBorder && d.color != null) return d.color;
  }
  return null;
}

/// Pixel contrast of the button's glyph colour against what is painted under
/// it, the glyph itself made transparent. Percentile 0.05: dark ink loses
/// against the darkest pixels.
Future<double> _measured(WidgetTester tester, ThemeData theme) async {
  await _pump(tester, theme, glyph: Colors.transparent);
  return textContrastOverBackground(
    tester,
    area: _icon,
    textColor: theme.colorScheme.onSurface,
    percentile: 0.05,
    boundary: find.byKey(_sceneKey),
  );
}

void main() {
  setUp(() {
    resetSharedPreferencesForTest();
    SettingsService.resetForTesting();
  });

  final light = monoTheme(dark: false);
  final ink = light.colorScheme.onSurface;

  group('light theme: the button carries its own contrast', () {
    testWidgets('plain: theme-coloured circle behind the glyph, >= 4.5:1 over a black poster', (tester) async {
      await glassPhone(tester, glass: false);
      await _pump(tester, light);
      final backdrop = _plainBackdrop(tester);
      expect(backdrop, isNotNull, reason: 'no backdrop of its own');
      expect(backdrop!.a, greaterThanOrEqualTo(0.85));
      final glyph = tester.widget<Icon>(_icon).color!;
      expect(glyph, ink);
      expect(_contrast(glyph, Color.alphaBlend(backdrop, Colors.black)), greaterThanOrEqualTo(4.5));
      expect(await _measured(tester, light), greaterThanOrEqualTo(4.5));
    });

    testWidgets('glass: light tint on the plate and on its layer, >= 4.5:1 over a black poster', (tester) async {
      await glassPhone(tester, glass: true);
      await _pump(tester, light);
      final tokens = _surface(tester).tokens;
      expect(tokens, isNotNull, reason: 'the plate keeps the dark phone tint');
      // The real tier tints from the nearest layer, so the button needs a
      // layer of its own carrying the same light tint.
      final layer = tester.widget<GlassLayer>(
        find.ancestor(of: find.byType(GlassSurface), matching: find.byType(GlassLayer)).first,
      );
      final glyph = tester.widget<Icon>(_icon).color!;
      for (final tint in [tokens!.tint, tokens.realTint, layer.tokens?.tint, layer.tokens?.realTint]) {
        if (tint == null) continue;
        expect(tint.a, greaterThanOrEqualTo(0.85));
        expect(_contrast(glyph, Color.alphaBlend(tint, Colors.black)), greaterThanOrEqualTo(4.5));
      }
      expect(layer.tokens, isNotNull);
      expect(await _measured(tester, light), greaterThanOrEqualTo(4.5));
    });
  });

  for (final oled in [false, true]) {
    final dark = monoTheme(dark: true, oled: oled);
    for (final glass in [false, true]) {
      testWidgets('dark (oled: $oled, glass: $glass): unchanged look', (tester) async {
        await glassPhone(tester, glass: glass);
        await _pump(tester, dark);
        final surface = _surface(tester);
        expect(surface.tokens, isNull);
        expect(surface.legacy, isNull);
        expect(_plainBackdrop(tester), isNull);
        final icon = tester.widget<Icon>(_icon);
        expect(icon.color, Colors.white);
        expect(icon.shadows, kGlassIconShadows);
      });
    }
  }
}
