/// SYS-1e: "Over" ▸ Licenties stays inside the TV shell.
///
/// Same defect as SYS-1d, one file over: `TvAboutScreen` is mounted through
/// `tvMyPleyaNestedRoute`, which has no `Navigator` of its own, so a bare
/// `Navigator.push` from its Licenses tile resolves to the profile navigator
/// above the shell and draws over `TvTopNavigation` entirely.
///
/// Pumped against the production `TvRootShell` and `TvTopNavigation`, the same
/// harness `tv_libraries_screen_test.dart` uses for the SYS-1d fix.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:pleya/focus/focus_memory_tracker.dart';
import 'package:pleya/focus/input_mode_tracker.dart';
import 'package:pleya/i18n/strings.g.dart';
import 'package:pleya/navigation/tv/tv_content_focus_authority.dart';
import 'package:pleya/navigation/tv/tv_content_route_registry.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/navigation/tv/tv_navigation_coordinator.dart';
import 'package:pleya/screens/tv/sections/tv_about_screen.dart';
import 'package:pleya/screens/tv/tv_root_shell.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/tv/tv_top_navigation.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    LocaleSettings.setLocaleSync(AppLocale.en);
    PackageInfo.setMockInitialValues(
      appName: 'Pleya',
      packageName: 'nl.michelknoop.pleya',
      version: '2.8.0',
      buildNumber: '212',
      buildSignature: '',
    );
  });

  group('SYS-1e: opening Licenties from Over keeps the TV shell mounted', () {
    late TvNavigationCoordinator coordinator;
    late FocusMemoryTracker navNodes;
    late FocusScopeNode navScope;
    late FocusScopeNode contentScope;

    setUp(() {
      coordinator = TvNavigationCoordinator()..updateConditions(const TvNavConditions(hasLiveTv: false));
      navNodes = FocusMemoryTracker(debugLabelPrefix: 'sys1eNav');
      navScope = FocusScopeNode(debugLabel: 'nav');
      contentScope = FocusScopeNode(debugLabel: 'content');
    });

    tearDown(() {
      coordinator.dispose();
      navNodes.dispose();
      navScope.dispose();
      contentScope.dispose();
    });

    Future<Object?> pushViaRegistry(TvNestedRoute route) {
      final destination = coordinator.active;
      return coordinator.pushNested(destination, route).result;
    }

    Future<void> pumpInShell(WidgetTester tester) async {
      tester.view.physicalSize = const Size(1280, 720);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      tvContentRouteRegistry.attach(pushViaRegistry);
      addTearDown(() => tvContentRouteRegistry.detach(pushViaRegistry));

      await tester.pumpWidget(
        TranslationProvider(
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: monoTheme(dark: true),
            home: InputModeTracker(
              child: TvRootShell(
                coordinator: coordinator,
                contentFocus: TvContentFocusAuthority(),
                navNodes: navNodes,
                navFocusScope: navScope,
                contentFocusScope: contentScope,
                isNavFocused: false,
                profile: null,
                onSelectDestination: (_) {},
                onFocusDestination: coordinator.activate,
                onFocusContent: ({bool restorePreviousFocus = true}) {},
                onFocusNav: () {},
                onOpenProfiles: () {},
                onOverlaySheetOpenChanged: (_) {},
                onKeyEvent: (_) => KeyEventResult.ignored,
                selectLibrary: null,
                openSettings: null,
                dismissNestedRoute: ([_]) {},
                child: const TvAboutScreen(),
              ),
            ),
          ),
        ),
      );
      await tester.pumpAndSettle();
    }

    Future<void> activateByLabel(WidgetTester tester, String label) async {
      final focus = Focus.maybeOf(tester.element(find.text(label)), scopeOk: true)!;
      focus.requestFocus();
      await tester.pump();
      await tester.sendKeyEvent(LogicalKeyboardKey.select);
      await tester.pumpAndSettle();
    }

    testWidgets('opening Licenties from Over keeps the TV shell mounted', (tester) async {
      await pumpInShell(tester);

      await activateByLabel(tester, t.about.openSourceLicenses);

      // Hoofdstuk 33's shared shell is binding on all eight references; a
      // kale Navigator.push draws a new route over TvRootShell entirely and
      // takes the bar with it, which is exactly SYS-1's symptom.
      expect(find.byType(TvTopNavigation), findsOneWidget);
    });
  });
}
