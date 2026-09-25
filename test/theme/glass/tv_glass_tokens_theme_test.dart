import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/glass/glass_settings.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/utils/layout_constants.dart';

/// VIS-0925-D: Apple TV glass follows the theme. One dark recipe for every
/// theme gave a flat grey top bar in Light and a bare white rim in OLED on
/// the hardware photos of build 303.
void main() {
  Future<BuildContext> pumpTheme(WidgetTester tester, {required bool dark, bool oled = false}) async {
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
    return ctx;
  }

  testWidgets('Light: a white plate without dim and without a white rim', (tester) async {
    final t = GlassTokens.tvFor(await pumpTheme(tester, dark: false));
    expect(t.tint.computeLuminance(), greaterThan(0.9));
    expect(t.tint.a, closeTo(0.6, 0.01));
    expect(t.dim, 1);
    expect(t.edge, 0);
  });

  testWidgets('Dark: the existing dark recipe', (tester) async {
    final t = GlassTokens.tvFor(await pumpTheme(tester, dark: true));
    expect(t.tint, const GlassTokens.tv().tint);
    expect(t.dim, const GlassTokens.tv().dim);
    expect(t.edge, const GlassTokens.tv().edge);
  });

  testWidgets('OLED: the dark plate with a quiet 15% rim', (tester) async {
    final t = GlassTokens.tvFor(await pumpTheme(tester, dark: true, oled: true));
    expect(t.tint, const GlassTokens.tv().tint);
    expect(t.edge, closeTo(0.15, 0.001));
  });

  testWidgets('the rim width follows the TV density scale', (tester) async {
    final ctx = await pumpTheme(tester, dark: true);
    expect(GlassTokens.tvFor(ctx).edgeWidth, GlassTokens.defaultEdgeWidth * TvLayoutConstants.scaleOf(ctx));
  });

  testWidgets('the player panel keeps its dark plate in Light (white text over video)', (tester) async {
    final t = GlassTokens.tvFor(await pumpTheme(tester, dark: false), panel: true);
    expect(t.tint, const GlassTokens.tvPanel().tint);
  });
}
