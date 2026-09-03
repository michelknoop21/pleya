import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/mobile/mobile_page_header.dart';
import 'package:pleya/widgets/pleya_logo.dart';
import 'package:pleya/widgets/pleya_wordmark.dart';

/// The lockup replaces the old loose P-icon and typed "PLEYA" (DEC-065 §1,
/// rapport §3) — see `docs/ios-unified-2026-fase1-plan.md` stap 5's BEWIJS.
void main() {
  Future<void> pump(WidgetTester tester, {required VoidCallback onSearchTap}) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(body: MobilePageHeader(activeProfile: null, onSearchTap: onSearchTap)),
      ),
    );
  }

  testWidgets('never draws PleyaLogo', (tester) async {
    await pump(tester, onSearchTap: () {});
    expect(find.byType(PleyaLogo), findsNothing);
  });

  testWidgets('draws the lockup at 28pt', (tester) async {
    await pump(tester, onSearchTap: () {});
    final wordmark = tester.widget<PleyaWordmark>(find.byType(PleyaWordmark));
    expect(wordmark.height, 28);
  });

  testWidgets('the search action fires the callback', (tester) async {
    var tapped = false;
    await pump(tester, onSearchTap: () => tapped = true);

    await tester.tap(find.byIcon(Symbols.search_rounded));
    expect(tapped, isTrue);
  });

  testWidgets('extra actions render between the lockup and search', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Scaffold(
          body: MobilePageHeader(
            activeProfile: null,
            onSearchTap: () {},
            actions: const [Icon(Icons.live_tv, key: Key('probe'))],
          ),
        ),
      ),
    );
    expect(find.byKey(const Key('probe')), findsOneWidget);
  });
}
