import 'package:flutter/material.dart';

import 'navigation_tabs.dart';

/// Carries the Netflix desktop top-nav state (tabs + selection) down to each
/// screen's own top bar, so the nav renders inside the existing app bar
/// instead of a second bar stacked on top. Active only on desktop non-TV.
class TopNavScope extends InheritedWidget {
  final bool active;
  final NavigationTabId currentTab;
  final List<NavigationTab> tabs;
  final ValueChanged<NavigationTabId> onSelectTab;

  const TopNavScope({
    super.key,
    required this.active,
    required this.currentTab,
    required this.tabs,
    required this.onSelectTab,
    required super.child,
  });

  static TopNavScope? of(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<TopNavScope>();
  }

  /// True when the desktop top nav owns the top chrome for this subtree.
  static bool isActive(BuildContext context) => of(context)?.active ?? false;

  @override
  bool updateShouldNotify(TopNavScope oldWidget) {
    return active != oldWidget.active ||
        currentTab != oldWidget.currentTab ||
        !identical(tabs, oldWidget.tabs);
  }
}
