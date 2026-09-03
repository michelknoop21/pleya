/// The mobile bottom bar's fase-1 presentation: no brand dot, no red 18×3
/// indicator, and an active slot drawn in `kAccent` instead
/// (`docs/ios-unified-2026-fase1-plan.md` stap 9).
///
/// The tabset itself is not this file's subject and is deliberately untouched
/// by fase 1; `account_entry_point_test.dart` and `navigation_tabs_test.dart`
/// own that contract.
library;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/profiles/active_profile_provider.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/theme/mono_theme.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:provider/provider.dart';

/// The five slots an iPhone renders: Home, Bibliotheken, Zoeken, Downloads,
/// Mijn Pleya. Built from the real tab list so a tabset change breaks here
/// too, rather than this file quietly testing a fixture of its own.
List<NavigationTab> _phoneTabs() => NavigationTab.getVisibleTabs(isOffline: false, isMobile: true).where((tab) {
  return tab.id != NavigationTabId.settings && tab.id != NavigationTabId.watchlist;
}).toList();

void main() {
  testWidgets('the active slot is red and the removed indicator is gone', (tester) async {
    tester.view.physicalSize = const Size(393, 852);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    final tabs = _phoneTabs();
    var selected = 0;

    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Provider<ActiveProfileProvider?>.value(
          value: null,
          child: StatefulBuilder(
            builder: (context, setState) => Scaffold(
              bottomNavigationBar: NavigationBarTheme(
                data: mobileTabBarTheme(NavigationBarTheme.of(context)),
                child: NavigationBar(
                  selectedIndex: selected,
                  onDestinationSelected: (i) => setState(() => selected = i),
                  destinations: tabs.map((tab) => tab.toDestination()).toList(),
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.byType(NavigationDestination), findsNWidgets(tabs.length));

    Color? labelColor(String label) => tester.widget<Text>(find.text(label)).style?.color;
    expect(labelColor(tabs.first.getLabel()), kAccent, reason: 'the selected label is red');
    expect(labelColor(tabs[1].getLabel()), isNot(kAccent));

    // The glyph half of the same rule: the built destination for the selected
    // slot paints its icon in kAccent, the unselected one does not.
    final selectedGlyphs = tester.widgetList<NavGlyph>(find.byType(NavGlyph)).where((g) => g.color == kAccent);
    expect(selectedGlyphs, hasLength(1), reason: 'exactly one slot is drawn in the accent');

    await tester.tap(find.text(tabs[1].getLabel()));
    await tester.pumpAndSettle();
    expect(labelColor(tabs[1].getLabel()), kAccent);
    expect(labelColor(tabs.first.getLabel()), isNot(kAccent));
  });

  testWidgets('the bar reserves no dot slot above the glyph', (tester) async {
    // The dot used to be a 5×5 Container in a Column above every glyph. Its
    // removal is what lets the bar keep Material's own slot height.
    await tester.pumpWidget(
      MaterialApp(
        theme: monoTheme(dark: true),
        home: Provider<ActiveProfileProvider?>.value(
          value: null,
          child: Scaffold(
            bottomNavigationBar: NavigationBar(
              selectedIndex: 0,
              destinations: _phoneTabs().map((tab) => tab.toDestination()).toList(),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    final dots = find.byWidgetPredicate((w) {
      if (w is! Container) return false;
      final constraints = w.constraints;
      return constraints != null && constraints.maxWidth == 5 && constraints.maxHeight == 5;
    });
    expect(dots, findsNothing);
  });
}
