import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../automation/automation_node.dart';
import '../../navigation/navigation_tabs.dart';
import '../../theme/glass/glass_settings.dart';
import '../../theme/glass/glass_surface.dart';
import '../../theme/glass/glass_text.dart';
import '../../theme/mono_theme.dart' show kAccent;

/// The mobile bottom bar's own selected-slot colour: the active label turns
/// [kAccent], matching the active glyph `_TabIcon` already draws. iOS Unified
/// 2026 fase 1, `docs/ios-unified-2026-fase1-plan.md` stap 9.
///
/// Applied at the bar rather than in `monoTheme` on purpose: the theme's
/// `navigationBarTheme` is inherited by every `NavigationBar` in the app, and
/// this red is a decision about this one bar.
NavigationBarThemeData mobileTabBarTheme(NavigationBarThemeData base) {
  final baseLabel = base.labelTextStyle;
  return base.copyWith(
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final style = baseLabel?.resolve(states) ?? const TextStyle();
      return states.contains(WidgetState.selected) ? style.copyWith(color: kAccent) : style;
    }),
  );
}

/// Fill of the active slot's capsule on the glass bar, see [MobileTabBar].
const Color _kGlassActiveSlot = Color(0x80000000);

/// Whether the bar floats as a glass capsule. The main Scaffold keys
/// `extendBody` on this same answer, so the tab roots scroll under the bar
/// and get its height back as `MediaQuery` bottom padding.
bool mobileTabBarFloats(BuildContext context) => glassTierFor(context) != GlassTier.off;

/// [mobileTabBarTheme] for the floating glass bar (mockup LG-01): inactive
/// labels and glyphs full white with the glass drop shadow instead of the
/// theme's 60% grey, the active slot opaque [kAccent]. The plate itself is
/// the background, so the bar paints none of its own.
NavigationBarThemeData mobileGlassTabBarTheme(NavigationBarThemeData base) {
  final baseLabel = base.labelTextStyle;
  final baseIcon = base.iconTheme;
  return base.copyWith(
    backgroundColor: Colors.transparent,
    surfaceTintColor: Colors.transparent,
    shadowColor: Colors.transparent,
    indicatorColor: Colors.transparent,
    elevation: 0,
    height: 64,
    labelTextStyle: WidgetStateProperty.resolveWith((states) {
      final selected = states.contains(WidgetState.selected);
      final style = baseLabel?.resolve(states) ?? const TextStyle();
      final color = MobileTabBar.debugGlassLabelColor ?? (selected ? kAccent : Colors.white);
      return glassText(style.copyWith(color: color));
    }),
    iconTheme: WidgetStateProperty.resolveWith((states) {
      final icon = baseIcon?.resolve(states) ?? const IconThemeData();
      return icon.copyWith(opacity: 1, color: Colors.white, shadows: kGlassIconShadows);
    }),
  );
}

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

  /// Overrides the glass bar's label color. The contrast test paints the
  /// labels transparent (shadows kept) to read the background under them;
  /// see `textContrastOverBackground`.
  @visibleForTesting
  static Color? debugGlassLabelColor;

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
    final glassOn = mobileTabBarFloats(context);
    final NavigationBarThemeData Function(NavigationBarThemeData) themed = glassOn
        ? mobileGlassTabBarTheme
        : mobileTabBarTheme;
    final navigationBar = isUnified || glassOn
        ? NavigationBarTheme(data: themed(NavigationBarTheme.of(context)), child: bar)
        : bar;

    // Netflix mobile: frosted near-black bar. Blur the content scrolling
    // behind it; the translucent color comes from navigationBarTheme.
    Widget frosted(Widget bar) => ClipRect(
      child: BackdropFilter(filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: bar),
    );

    Widget withNavBarAutomation(Widget bar) => AutomationNode(id: AutomationIds.navBar, role: 'nav', child: bar);

    // Glass (LG-01): a floating capsule 16 from the sides and 10 above the
    // home indicator, instead of the full-width frosted strip. The bar's own
    // SafeArea is stripped, the Padding already carries the inset.
    Widget shell(Widget bar) {
      if (!glassOn) return frosted(bar);
      return Padding(
        padding: EdgeInsets.fromLTRB(16, 0, 16, MediaQuery.paddingOf(context).bottom + 10),
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
