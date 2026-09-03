import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_hero_actions.dart';

void main() {
  Future<void> pump(WidgetTester tester, Widget actions) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: actions),
      ),
    );
  }

  testWidgets('shows Play with no progress', (tester) async {
    await pump(tester, MobileHeroActions(hasProgress: false, onPlay: () {}, onSecondary: () {}));
    expect(find.text('Play'), findsOneWidget);
  });

  testWidgets('shows minutes left with active progress', (tester) async {
    await pump(tester, MobileHeroActions(hasProgress: true, minutesLeft: 42, onPlay: () {}, onSecondary: () {}));
    expect(find.textContaining('42'), findsOneWidget);
  });

  testWidgets('tapping play fires onPlay', (tester) async {
    var played = false;
    await pump(tester, MobileHeroActions(hasProgress: false, onPlay: () => played = true, onSecondary: () {}));

    await tester.tap(find.text('Play'));
    expect(played, isTrue);
  });

  testWidgets('the secondary action switches label with the enum', (tester) async {
    await pump(
      tester,
      MobileHeroActions(
        hasProgress: false,
        secondary: HeroSecondaryAction.addToList,
        onPlay: () {},
        onSecondary: () {},
      ),
    );
    expect(find.text('Add to Watchlist'), findsOneWidget);
  });
}
