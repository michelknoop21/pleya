import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/screens/main/mobile_main_scaffold.dart';
import 'package:pleya/screens/main/mobile_tab_bar.dart';
import 'package:pleya/screens/main_screen.dart' show mainScreenBottomNavigationTabs;
import 'package:pleya/services/device_performance.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:provider/provider.dart';

/// The iPhone bar as `MainScreen` builds it: Home, Series, Movies, My Pleya.
List<NavigationTab> glassPhoneTabs() => mainScreenBottomNavigationTabs(
  visibleTabs: NavigationTab.getVisibleTabs(isOffline: false, isMobile: true, isPhone: true),
  isMobile: true,
  isPhone: true,
  isOffline: false,
  currentTab: NavigationTabId.discover,
);

/// The app theme on an iPhone. Glass only applies to handheld iOS and Apple
/// TV (`glassAppliesTo`), so every iPhone glass test builds its
/// `MaterialApp` with this theme instead of the test default (Android).
ThemeData glassPhoneTheme() => monoTheme(dark: true).copyWith(platform: TargetPlatform.iOS);

/// Puts the iPhone on the fake tier (a reduced-performance device): the
/// `BackdropFilter` stack the test renderer can actually paint and measure.
/// Without this an iOS theme resolves to the real tier.
void useFakeGlassTier() {
  DevicePerformance.debugReset(autoReduced: true);
  addTearDown(DevicePerformance.debugReset);
}

/// iPhone 17 Pro: 393x852 logical at 3x with a 34pt home indicator, Liquid
/// Glass set to [glass]. The pixel ratio matters: `PlatformDetector.isTablet`
/// works in inches, and 393x852 at 1x reads as a 15" tablet (glass off).
/// Fake tier unless [realTier]; pair with [glassPhoneTheme].
/// Call after `resetSharedPreferencesForTest()`.
Future<void> glassPhone(WidgetTester tester, {required bool glass, bool realTier = false}) async {
  tester.view.physicalSize = const Size(1179, 2556);
  tester.view.devicePixelRatio = 3;
  tester.view.padding = const FakeViewPadding(top: 62 * 3, bottom: 34 * 3);
  addTearDown(tester.view.reset);
  if (!realTier) useFakeGlassTier();
  await tester.runAsync(() => SettingsService.getInstance());
  await SettingsService.instance.write(SettingsService.liquidGlass, glass);
}

/// [MobileMainScaffold] exactly as `MainScreen` mounts it, with [MobileTabBar]
/// on the phone tabs and [body] as the tab root. [wrapApp] adds the providers
/// a real screen needs above the `MaterialApp`, ActiveProfileProvider included.
Widget glassMainShell(
  WidgetBuilder body, {
  Widget? reconnectStrip,
  bool transparentForeground = false,
  Widget Function(Widget app)? wrapApp,
}) {
  final tabs = glassPhoneTabs();
  final shell = MobileMainScaffold(
    body: Builder(builder: body),
    reconnectStrip: reconnectStrip,
    tabBar: MobileTabBar(
      tabs: tabs,
      currentIndex: 0,
      onDestinationSelected: (_) {},
      hideLabels: false,
      presentation: TabBarPresentation.unified2026,
      onLibraryLongPress: (_) {},
      debugTransparentForeground: transparentForeground,
    ),
  );
  // The bar's My Pleya slot reads ActiveProfileProvider; a caller's [wrapApp]
  // provides the real one, and a null one here would shadow it.
  if (wrapApp != null) return wrapApp(MaterialApp(theme: glassPhoneTheme(), home: shell));
  return MaterialApp(
    theme: glassPhoneTheme(),
    home: Provider<ActiveProfileProvider?>.value(value: null, child: shell),
  );
}
