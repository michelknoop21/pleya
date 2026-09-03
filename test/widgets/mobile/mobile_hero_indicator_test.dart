import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_hero_indicator.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget indicator) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: indicator),
      ),
    );
  }

  testWidgets('draws nothing for a single slide', (tester) async {
    await pump(tester, const MobileHeroIndicator(count: 1, selectedIndex: 0));
    expect(find.byType(AnimatedContainer), findsNothing);
  });

  testWidgets('draws one dot per slide', (tester) async {
    await pump(tester, const MobileHeroIndicator(count: 4, selectedIndex: 1));
    expect(find.byType(AnimatedContainer), findsNWidgets(4));
  });

  testWidgets('persistentDots stays visible without an in-flight advance', (tester) async {
    await pump(tester, const MobileHeroIndicator(count: 3, selectedIndex: 0, style: HeroIndicatorStyle.persistentDots));
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 1);
  });

  testWidgets('transientSegment hides outside an in-flight advance', (tester) async {
    await pump(
      tester,
      const MobileHeroIndicator(count: 3, selectedIndex: 0, style: HeroIndicatorStyle.transientSegment),
    );
    final opacity = tester.widget<AnimatedOpacity>(find.byType(AnimatedOpacity));
    expect(opacity.opacity, 0);
  });
}
