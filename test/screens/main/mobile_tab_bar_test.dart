/// `MobileTabBar` rendered on its own (task 4, pure extraction out of
/// `main_screen.dart`): exactly one bar, exactly one blur, and a tap reports
/// the tapped index back to the caller. The tabset's own contract lives in
/// `test/navigation/mobile_tab_bar_test.dart`.
library;

import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/screens/main/mobile_tab_bar.dart';
import 'package:provider/provider.dart';

List<NavigationTab> _phoneTabs() => NavigationTab.getVisibleTabs(isOffline: false, isMobile: true).where((tab) {
  return tab.id != NavigationTabId.settings && tab.id != NavigationTabId.watchlist;
}).toList();

void main() {
  testWidgets('renders one NavigationBar and one BackdropFilter, and reports taps by index', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tabs = _phoneTabs();
    int? tappedIndex;

    await tester.pumpWidget(
      MaterialApp(
        home: Provider<ActiveProfileProvider?>.value(
          value: null,
          child: Scaffold(
            bottomNavigationBar: MobileTabBar(
              tabs: tabs,
              currentIndex: 0,
              onDestinationSelected: (i) => tappedIndex = i,
              hideLabels: false,
              presentation: TabBarPresentation.unified2026,
              onLibraryLongPress: (_) {},
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationBar), findsOneWidget);
    expect(find.byType(BackdropFilter), findsOneWidget);

    await tester.tap(find.text(tabs[1].getLabel()));
    await tester.pumpAndSettle();
    expect(tappedIndex, 1);
  });
}
