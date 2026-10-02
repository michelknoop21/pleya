import 'dart:math' as math;
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../navigation/navigation_tabs.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/mono_theme.dart' show kAccent;
import 'mobile_tab_bar_theme.dart';

/// Fill of the active slot's capsule on the glass bar, see [MobileTabBar].
const Color _kGlassActiveSlot = Color(0x80000000);

/// Whether the bar floats as a glass capsule. The main Scaffold keys
/// `extendBody` on this same answer, so the tab roots scroll under the bar
/// and get its height back as `MediaQuery` bottom padding.
bool mobileTabBarFloats(BuildContext context) => glassTierFor(context) != GlassTier.off;

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
    @visibleForTesting this.debugTransparentForeground = false,
  });

  final List<NavigationTab> tabs;
  final int currentIndex;
  final ValueChanged<int> onDestinationSelected;
  final bool hideLabels;
  final TabBarPresentation presentation;
  final void Function(BuildContext context) onLibraryLongPress;

  /// Glass only: labels painted transparent (their shadows kept) and glyphs
  /// hidden, so the contrast test can read the background under them; see
  /// `textContrastOverBackground`.
  final bool debugTransparentForeground;

  /// Wraps one tab's icon/selectedIcon in [AutomationNode] so `nav.<id>`
  /// resolves on both the mobile bar and the desktop/TV rail
  /// ([SideNavigationRail] mounts the same id) — iOS Unified 2026 fase 1,
  /// `docs/ios-unified-2026-fase1-plan.md` stap 3.
  static NavigationDestination _withNavTabAutomation(
    NavigationTab tab,
    TabBarPresentation presentation, {
    bool hideGlyph = false,
  }) {
    final destination = tab.toDestination(presentation: presentation);
    final id = AutomationIds.navTab(tab.id);
    Widget wrap(Widget icon) => AutomationNode(
      id: id,
      role: 'nav.item',
      child: hideGlyph ? Opacity(opacity: 0, child: icon) : icon,
    );
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
    final glassOn = mobileTabBarFloats(context);
    final transparent = glassOn && debugTransparentForeground;

    final bar = NavigationBar(
      selectedIndex: currentIndex >= 0 ? currentIndex : 0,
      onDestinationSelected: onDestinationSelected,
      labelBehavior: hideLabels
          ? NavigationDestinationLabelBehavior.alwaysHide
          : NavigationDestinationLabelBehavior.alwaysShow,
      destinations: tabs.map((tab) => _withNavTabAutomation(tab, presentation, hideGlyph: transparent)).toList(),
    );
    final base = NavigationBarTheme.of(context);
    final navigationBar = glassOn
        ? NavigationBarTheme(
            data: mobileGlassTabBarTheme(base, labelColor: transparent ? Colors.transparent : Colors.white),
            child: bar,
          )
        : isUnified
        ? NavigationBarTheme(data: mobileTabBarTheme(base), child: bar)
        : bar;

    // Netflix mobile: frosted near-black bar. Blur the content scrolling
    // behind it; the translucent color comes from navigationBarTheme.
    Widget frosted(Widget bar) => ClipRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bar),
    );

    Widget withNavBarAutomation(Widget bar) => AutomationNode(id: AutomationIds.navBar, role: 'nav', child: bar);

    // Glass (LG-01): a floating capsule 16 from the sides, instead of the
    // full-width frosted strip. Bottom margin max(10, inset - 12): on a home
    // indicator iPhone the capsule sits lower, into the inset, and without an
    // inset it keeps 10. The bar's own SafeArea is stripped, the Padding
    // carries the margin; the Scaffold measures the result for the body.
    Widget shell(Widget bar) {
      if (!glassOn) return frosted(bar);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, math.max(10.0, MediaQuery.paddingOf(context).bottom - 12)),
        child: GlassLayer(
          child: GlassSurface(
            shape: const StadiumBorder(),
            tokens: const GlassTokens.phone(),
            child: MediaQuery.removePadding(context: context, removeBottom: true, child: bar),
          ),
        ),
      );
    }

    final librariesIndex = tabs.indexWhere((tab) => tab.id == NavigationTabId.libraries);
    if (tabs.isEmpty) return shell(withNavBarAutomation(navigationBar));

    return shell(
      withNavBarAutomation(
        LayoutBuilder(
          builder: (context, constraints) {
            if (!constraints.hasBoundedWidth) return navigationBar;

            final itemWidth = constraints.maxWidth / tabs.length;
            final isRtl = Directionality.of(context) == TextDirection.rtl;

            double itemLeft(int index) => isRtl ? constraints.maxWidth - (itemWidth * (index + 1)) : itemWidth * index;

            return Stack(
              children: [
                // Glass: a darker capsule under the active slot, the LG-01
                // selected-slot pill. Dark rather than LG-01's light one:
                // kAccent tops out at 4.36:1 even on pure black, and on the
                // bare plate over the Big Buck Bunny fixture the red label
                // measured 2.33:1 (`mobile_tab_bar_glass_test.dart`).
                if (glassOn && currentIndex >= 0)
                  Positioned(
                    left: itemLeft(currentIndex) + 4,
                    top: 4,
                    bottom: 4,
                    width: itemWidth - 8,
                    child: const IgnorePointer(
                      child: DecoratedBox(
                        decoration: ShapeDecoration(shape: StadiumBorder(), color: _kGlassActiveSlot),
                      ),
                    ),
                  ),
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
