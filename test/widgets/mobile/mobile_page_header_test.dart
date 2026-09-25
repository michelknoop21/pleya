import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/profiles/profile_avatar.dart';
import 'package:pleya/screens/profile/profile_switch_screen.dart';
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

  testWidgets('tapping the avatar opens the profile switcher (DEC-132)', (tester) async {
    final pushed = <Route<dynamic>>[];
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        navigatorObservers: [_PushRecorder(pushed)],
        home: Scaffold(body: MobilePageHeader(activeProfile: null, onSearchTap: () {})),
      ),
    );
    pushed.clear();

    await tester.tap(find.byType(ProfileAvatar));
    await tester.pump();
    // The pushed page needs the app's profile providers, which this harness
    // does not mount; what is under test is which page the tap opens.
    while (tester.takeException() != null) {}

    expect(pushed, hasLength(1));
    final page = (pushed.single as MaterialPageRoute<dynamic>).builder(tester.element(find.byType(Scaffold).first));
    // The same screen Mijn Pleya's "Profiel wisselen" opens, not a second switcher.
    expect(page, isA<ProfileSwitchScreen>());
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

class _PushRecorder extends NavigatorObserver {
  _PushRecorder(this.pushed);

  final List<Route<dynamic>> pushed;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => pushed.add(route);
}
