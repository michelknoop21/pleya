import 'package:flutter/widgets.dart';

import 'navigation_tabs.dart';

/// The mobile shell's own entry point, for the surfaces mounted inside it.
///
/// Home and the fase-2 Series/Films landings both open Search from the search
/// action in their header, because that slot leaves the bottom bar when the
/// Unified 2026 root navigation lands. They need the shell's `_selectTab` to
/// do it, and there was no honest way to reach it: `MyPleyaScreen` is a direct
/// child of the shell and takes a callback, but Home is built by
/// `DiscoverScreen`, which desktop and TV build too. Threading a
/// phone-only callback through that screen would put the mobile shell's
/// concern in three trees that do not have one.
///
/// Deliberately one method. This is the shell answering "take me to that
/// destination", not a second navigation API: which destinations exist stays
/// [NavigationTab.getVisibleTabs]'s answer, and what the bar paints stays
/// [TabBarPresentation]'s.
class MobileShellScope extends InheritedWidget {
  /// The shell's tab selection, the same one the bottom bar calls.
  final void Function(NavigationTabId tab) openTab;

  const MobileShellScope({super.key, required this.openTab, required super.child});

  /// Null outside the mobile shell, which is the normal case in a widget test
  /// and on desktop and TV. Callers treat that as "nowhere to go" rather than
  /// asserting, so a surface stays testable on its own.
  static MobileShellScope? maybeOf(BuildContext context) {
    return context.dependOnInheritedWidgetOfExactType<MobileShellScope>();
  }

  @override
  bool updateShouldNotify(MobileShellScope oldWidget) => openTab != oldWidget.openTab;
}
