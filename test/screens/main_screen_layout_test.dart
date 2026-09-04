import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/widgets/side_navigation_rail.dart';

void main() {
  test('side navigation pushes stable foreground off-screen while temporarily expanded', () {
    const viewportWidth = 1280.0;
    const reservedWidth = SideNavigationRailState.tvCollapsedWidth;

    final collapsed = mainScreenSideNavigationContentLayout(
      viewportWidth: viewportWidth,
      currentSideNavigationWidth: SideNavigationRailState.tvCollapsedWidth,
      reservedSideNavigationWidth: reservedWidth,
    );
    final expanded = mainScreenSideNavigationContentLayout(
      viewportWidth: viewportWidth,
      currentSideNavigationWidth: SideNavigationRailState.expandedWidth,
      reservedSideNavigationWidth: reservedWidth,
    );

    expect(collapsed.width, viewportWidth - SideNavigationRailState.tvCollapsedWidth);
    expect(expanded.width, collapsed.width);
    expect(collapsed.left, SideNavigationRailState.tvCollapsedWidth);
    expect(expanded.left, SideNavigationRailState.expandedWidth);
    expect(collapsed.left + collapsed.width, viewportWidth);
    expect(expanded.left + expanded.width, viewportWidth + SideNavigationRailState.expandedWidth - reservedWidth);
  });

  test('side navigation reserves expanded width when always open', () {
    const viewportWidth = 1280.0;

    final expanded = mainScreenSideNavigationContentLayout(
      viewportWidth: viewportWidth,
      currentSideNavigationWidth: SideNavigationRailState.expandedWidth,
      reservedSideNavigationWidth: SideNavigationRailState.expandedWidth,
    );

    expect(expanded.left, SideNavigationRailState.expandedWidth);
    expect(expanded.width, viewportWidth - SideNavigationRailState.expandedWidth);
    expect(expanded.left + expanded.width, viewportWidth);
  });

  test('tvOS Menu pass-through only enables at root with sidebar focus', () {
    bool shouldPass({
      bool isAppleTV = true,
      bool isShowingProfileSelection = false,
      bool isOverlaySheetOpen = false,
      bool isRouteCurrent = true,
      bool isSidebarFocused = true,
      bool hasVisibleTabs = true,
      bool isCurrentTabRoot = true,
    }) {
      return shouldPassTvosMenuToSystem(
        isAppleTV: isAppleTV,
        isShowingProfileSelection: isShowingProfileSelection,
        isOverlaySheetOpen: isOverlaySheetOpen,
        isRouteCurrent: isRouteCurrent,
        isSidebarFocused: isSidebarFocused,
        hasVisibleTabs: hasVisibleTabs,
        isCurrentTabRoot: isCurrentTabRoot,
      );
    }

    expect(shouldPass(), isTrue);
    expect(shouldPass(isSidebarFocused: false), isFalse);
    expect(shouldPass(isCurrentTabRoot: false), isFalse);
    expect(shouldPass(isOverlaySheetOpen: true), isFalse);
    expect(shouldPass(isRouteCurrent: false), isFalse);
    expect(shouldPass(isAppleTV: false), isFalse);
  });

  // Fase-0 baseline for Pleya Unified TV 2026 (docs/tvos-unified-experience.md
  // hoofdstuk 27): this group is the existing companion-remote tab-cycling
  // and Menu/back-key decision behavior that fase 0 locks in before any
  // unified-catalog code lands. A regression here is a regression against
  // the pre-unified baseline, not a new requirement.
  group('mainScreenAdjacentTabId', () {
    NavigationTab tab(NavigationTabId id) =>
        NavigationTab(id: id, onlineOnly: false, icon: Icons.circle, getLabel: () => id.name);

    final tabs = [tab(NavigationTabId.discover), tab(NavigationTabId.libraries), tab(NavigationTabId.search)];

    test('steps forward through the middle of the list', () {
      expect(
        mainScreenAdjacentTabId(visibleTabs: tabs, currentTab: NavigationTabId.discover, forward: true),
        NavigationTabId.libraries,
      );
    });

    test('steps backward through the middle of the list', () {
      expect(
        mainScreenAdjacentTabId(visibleTabs: tabs, currentTab: NavigationTabId.search, forward: false),
        NavigationTabId.libraries,
      );
    });

    test('forward wraps from the last tab back to the first', () {
      expect(
        mainScreenAdjacentTabId(visibleTabs: tabs, currentTab: NavigationTabId.search, forward: true),
        NavigationTabId.discover,
      );
    });

    test('backward wraps from the first tab back to the last', () {
      expect(
        mainScreenAdjacentTabId(visibleTabs: tabs, currentTab: NavigationTabId.discover, forward: false),
        NavigationTabId.search,
      );
    });

    test('a single visible tab wraps to itself in either direction', () {
      final single = [tabs[1]];

      expect(
        mainScreenAdjacentTabId(visibleTabs: single, currentTab: NavigationTabId.libraries, forward: true),
        NavigationTabId.libraries,
      );
      expect(
        mainScreenAdjacentTabId(visibleTabs: single, currentTab: NavigationTabId.libraries, forward: false),
        NavigationTabId.libraries,
      );
    });

    test('a current tab absent from the visible list is left untouched', () {
      expect(mainScreenAdjacentTabId(visibleTabs: tabs, currentTab: NavigationTabId.settings, forward: true), isNull);
      expect(mainScreenAdjacentTabId(visibleTabs: tabs, currentTab: NavigationTabId.settings, forward: false), isNull);
    });
  });

  group('mainBackKeyDecision', () {
    MainBackDecision decide({
      bool hasVisibleTabs = true,
      bool isAtHomeTab = false,
      bool isAppleTV = false,
      bool hasRecentBackPress = false,
    }) {
      return mainBackKeyDecision(
        hasVisibleTabs: hasVisibleTabs,
        isAtHomeTab: isAtHomeTab,
        isAppleTV: isAppleTV,
        hasRecentBackPress: hasRecentBackPress,
      );
    }

    test('no visible tabs swallows the press regardless of anything else', () {
      expect(decide(hasVisibleTabs: false), MainBackDecision.noVisibleTabs);
      expect(
        decide(hasVisibleTabs: false, isAtHomeTab: true, isAppleTV: true, hasRecentBackPress: true),
        MainBackDecision.noVisibleTabs,
      );
    });

    test('not on the home tab navigates home first, even on tvOS or with a recent press', () {
      expect(decide(isAtHomeTab: false), MainBackDecision.goHome);
      expect(decide(isAtHomeTab: false, isAppleTV: true), MainBackDecision.goHome);
      expect(decide(isAtHomeTab: false, hasRecentBackPress: true), MainBackDecision.goHome);
    });

    test('on the home tab, tvOS never arms the exit prompt', () {
      expect(decide(isAtHomeTab: true, isAppleTV: true), MainBackDecision.tvMenuPassthroughStale);
      expect(
        decide(isAtHomeTab: true, isAppleTV: true, hasRecentBackPress: true),
        MainBackDecision.tvMenuPassthroughStale,
      );
    });

    test('on the home tab off tvOS, a recent press exits', () {
      expect(decide(isAtHomeTab: true, hasRecentBackPress: true), MainBackDecision.exitNow);
    });

    test('on the home tab off tvOS, a first press arms the exit prompt', () {
      expect(decide(isAtHomeTab: true, hasRecentBackPress: false), MainBackDecision.armExitPrompt);
    });
  });

  test('profile switch waits for one post-bind invalidation', () {
    expect(
      profileInvalidationAction(
        previousProfileId: 'owner',
        currentProfileId: 'kids',
        wasBindingPreviously: false,
        isBindingNow: false,
        hasPendingProfileSwitchInvalidation: false,
        pendingProfileSwitchInvalidationId: null,
      ),
      ProfileInvalidationAction.waitForProfileSwitch,
    );

    expect(
      profileInvalidationAction(
        previousProfileId: 'kids',
        currentProfileId: 'kids',
        wasBindingPreviously: true,
        isBindingNow: false,
        hasPendingProfileSwitchInvalidation: true,
        pendingProfileSwitchInvalidationId: 'kids',
      ),
      ProfileInvalidationAction.none,
    );
  });

  test('same-profile rebind invalidates once when binding settles', () {
    expect(
      profileInvalidationAction(
        previousProfileId: 'owner',
        currentProfileId: 'owner',
        wasBindingPreviously: true,
        isBindingNow: false,
        hasPendingProfileSwitchInvalidation: false,
        pendingProfileSwitchInvalidationId: null,
      ),
      ProfileInvalidationAction.invalidateNow,
    );

    expect(
      profileInvalidationAction(
        previousProfileId: 'owner',
        currentProfileId: 'owner',
        wasBindingPreviously: false,
        isBindingNow: false,
        hasPendingProfileSwitchInvalidation: false,
        pendingProfileSwitchInvalidationId: null,
      ),
      ProfileInvalidationAction.none,
    );
  });

  testWidgets('side navigation bleed animates from the previous value', (tester) async {
    Widget build(double targetBleed) {
      return Directionality(
        textDirection: TextDirection.ltr,
        child: Stack(
          children: [
            SideNavigationBleedBuilder(
              targetBleed: targetBleed,
              builder: (context, bleed, _) => Positioned(
                key: const ValueKey('bleed-position'),
                top: 0,
                left: -bleed,
                width: 1280,
                height: 10,
                child: const SizedBox.shrink(),
              ),
            ),
          ],
        ),
      );
    }

    double left() => tester.widget<Positioned>(find.byKey(const ValueKey('bleed-position'))).left!;

    await tester.pumpWidget(build(SideNavigationRailState.tvCollapsedWidth));
    expect(left(), -SideNavigationRailState.tvCollapsedWidth);

    await tester.pumpWidget(build(SideNavigationRailState.expandedWidth));
    expect(left(), closeTo(-SideNavigationRailState.tvCollapsedWidth, 0.001));

    await tester.pump(const Duration(milliseconds: 100));
    expect(left(), lessThan(-SideNavigationRailState.tvCollapsedWidth));
    expect(left(), greaterThan(-SideNavigationRailState.expandedWidth));

    await tester.pumpAndSettle();
    expect(left(), closeTo(-SideNavigationRailState.expandedWidth, 0.001));
  });
}
