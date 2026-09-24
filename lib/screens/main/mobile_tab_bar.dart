import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../navigation/navigation_tabs.dart';
import '../../theme/mono_theme.dart' show kAccent;
import '../main_screen.dart' show mobileTabBarTheme;

/// The mobile bottom bar, extracted verbatim out of
/// `_MainScreenState._buildBottomNavigationBar` (no behavior change). State
/// stays in `_MainScreenState`: this widget only renders what it is given.
class MobileTabBar extends StatelessWidget {
  const MobileTabBar({
    super.key,
    required this.tabs,
    required this.currentIndex,
    required this.onDestinationSelected,
    required this.hideLabels,
    required this.presentation,
    required this.onLibraryLongPress,
  });

  final List<NavigationTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool hideLabels;
  final TabBarPresentation presentation;
  final void Function(BuildContext context) onLibraryLongPress;

  /// Wraps one tab's icon/selectedIcon in [AutomationNode] so `nav.<id>`
  /// resolves on both the mobile bar and the desktop/TV rail
  /// ([SideNavigationRail] mounts the same id) — iOS Unified 2026 fase 1,
  /// `docs/ios-unified-2026-fase1-plan.md` stap 3.
  static NavigationDestination _withNavTabAutomation(NavigationTab tab, TabBarPresentation presentation) {
    final destination = tab.toDestination(presentation: presentation);
    final id = AutomationIds.navTab(tab.id);
    Widget wrap(Widget icon) => AutomationNode(id: id, role: 'nav.item', child: icon);
    return NavigationDestination(
      icon: wrap(destination.icon),
      selectedIcon: destination.selectedIcon == null ? null : wrap(destination.selectedIcon!),
      label: destination.label,
      tooltip: destination.tooltip,
      enabled: destination.enabled,
    );
  }

  @override
  Widget build(BuildContext context) {
    final isUnified = presentation == TabBarPresentation.unified2026;

    final bar = NavigationBar(
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onDestinationSelected: onDestinationSelected,
      labelBehavior: hideLabels
          ? NavigationDestinationLabelBehavior.alwaysHide
          : NavigationDestinationLabelBehavior.alwaysShow,
      destinations: tabs.map((tab) => _withNavTabAutomation(tab, presentation)).toList(),
    );
    final navigationBar = isUnified
        ? NavigationBarTheme(data: mobileTabBarTheme(NavigationBarTheme.of(context)), child: bar)
        : bar;

    // Netflix mobile: frosted near-black bar. Blur the content scrolling
    // behind it; the translucent color comes from navigationBarTheme.
    Widget frosted(Widget bar) => ClipRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bar),
    );

    Widget withNavBarAutomation(Widget bar) => AutomationNode(id: AutomationIds.navBar, role: 'nav', child: bar);

    final librariesIndex = tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries);
    if (tabs.isEmpty) return frosted(withNavBarAutomation(navigationBar));

    return frosted(
      withNavBarAutomation(
        LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth) return navigationBar;

            final itemWidth = constraints.maxWidth / tabs.length;
            final isRtl = Directionality.of(context) == TextDirection.rtl;

            double itemLeft(int index) => isRtl ? constraints.maxWidth - (itemWidth * (index + 1)) : itemWidth * index;

            return Stack(
              children: [
                navigationBar,
                // The classic bar's solid red indicator above the active icon.
                // The unified bar has none: there the active slot itself is
                // red (fase 1 stap 9).
                if (!isUnified && currentIndex >= 0)
                  Positioned(
                    left: itemLeft(currentIndex) + (itemWidth - 18) / 2,
                    top: 0,
                    width: 18,
                    height: 3,
                    child: IgnorePointer(
                      child: DecoratedBox(
                        decoration: BoxDecoration(color: kAccent, borderRadius: BorderRadius.circular(2)),
                      ),
                    ),
                  ),
                if (librariesIndex >= 0)
                  Positioned(
                    left: itemLeft(librariesIndex),
                    top: 0,
                    bottom: 0,
                    width: itemWidth,
                    child: GestureDetector(
                      behavior: HitTestBehavior.translucent,
                      excludeFromSemantics: true,
                      onLongPress: () {
                        Feedback.forLongPress(context);
                        onLibraryLongPress(context);
                      },
                      child: const SizedBox.expand(),
                    ),
                  ),
              ],
            );
          },
        ),
      ),
    );
  }
}
