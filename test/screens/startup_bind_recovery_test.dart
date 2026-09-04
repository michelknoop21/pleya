import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/main.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/navigation/primary_mobile_destination_policy.dart';
import 'package:pleya/screens/main_screen.dart';

List<NavigationTabId> _ids(List<NavigationTab> tabs) => tabs.map((tab) => tab.id).toList();

void main() {
  group('startup bind recovery', () {
    test('enters offline mode only when initial bind failed with no online servers', () {
      expect(shouldEnterOfflineModeAfterStartupBind(bindingSucceeded: false, hasOnlineServers: false), isTrue);
      expect(shouldEnterOfflineModeAfterStartupBind(bindingSucceeded: true, hasOnlineServers: false), isFalse);
      expect(shouldEnterOfflineModeAfterStartupBind(bindingSucceeded: false, hasOnlineServers: true), isFalse);
    });

    test('retries active profile bind when reconnect has no visible servers', () {
      expect(
        shouldRetryActiveProfileBindAfterReconnect(
          hasActiveProfile: true,
          hasVisibleConnectedServers: false,
          hasManagerOnlineServers: true,
          hasKnownOfflineServers: false,
        ),
        isTrue,
      );
      expect(
        shouldRetryActiveProfileBindAfterReconnect(
          hasActiveProfile: true,
          hasVisibleConnectedServers: false,
          hasManagerOnlineServers: false,
          hasKnownOfflineServers: false,
        ),
        isTrue,
      );
      expect(
        shouldRetryActiveProfileBindAfterReconnect(
          hasActiveProfile: true,
          hasVisibleConnectedServers: true,
          hasManagerOnlineServers: true,
          hasKnownOfflineServers: false,
        ),
        isFalse,
      );
      expect(
        shouldRetryActiveProfileBindAfterReconnect(
          hasActiveProfile: false,
          hasVisibleConnectedServers: false,
          hasManagerOnlineServers: true,
          hasKnownOfflineServers: false,
        ),
        isFalse,
      );
      expect(
        shouldRetryActiveProfileBindAfterReconnect(
          hasActiveProfile: true,
          hasVisibleConnectedServers: false,
          hasManagerOnlineServers: false,
          hasKnownOfflineServers: true,
        ),
        isFalse,
      );
    });

    test('explicit offline startup stays offline until a visible server connects', () {
      expect(
        shouldRenderMainScreenOffline(
          providerOffline: false,
          startupOfflineUntilConnected: true,
          hasVisibleConnectedServers: false,
        ),
        isTrue,
      );
      expect(
        shouldRenderMainScreenOffline(
          providerOffline: false,
          startupOfflineUntilConnected: true,
          hasVisibleConnectedServers: true,
        ),
        isFalse,
      );
      expect(
        shouldRenderMainScreenOffline(
          providerOffline: true,
          startupOfflineUntilConnected: false,
          hasVisibleConnectedServers: true,
        ),
        isTrue,
      );
    });
  });

  group('main screen bottom navigation tabs', () {
    test('mobile online hides Settings, which now lives behind the gear in My Pleya', () {
      final tabs = mainScreenBottomNavigationTabs(visibleTabs: allNavigationTabs, isMobile: true);

      expect(_ids(tabs), isNot(contains(NavigationTabId.settings)));
    });

    test('mobile offline includes Downloads but still not Settings', () {
      final offlineTabs = allNavigationTabs
          .where((tab) => tab.id == NavigationTabId.downloads || tab.id == NavigationTabId.settings)
          .toList();
      final tabs = mainScreenBottomNavigationTabs(
        visibleTabs: offlineTabs,
        isMobile: true,
        capabilities: const MobileDestinationCapabilities(isOffline: true),
      );

      expect(_ids(tabs), [NavigationTabId.downloads]);
    });

    test('Settings stays out of the bar even while it is the active screen', () {
      // Changed behaviour: Settings used to reappear as a bar item when
      // selected. It is now reached through the gear in My Pleya, and the bar
      // projects the selection onto My Pleya instead of growing a sixth slot.
      final tabs = mainScreenBottomNavigationTabs(visibleTabs: allNavigationTabs, isMobile: true);

      expect(_ids(tabs), isNot(contains(NavigationTabId.settings)));
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.settings, isOffline: false, barTabs: _ids(tabs)),
        NavigationTabId.myPleya,
      );
    });

    test('non-mobile returns all visible tabs unchanged', () {
      final tabs = mainScreenBottomNavigationTabs(visibleTabs: allNavigationTabs, isMobile: false);

      expect(tabs, same(allNavigationTabs));
    });
  });

  /// `_isMobile` flips inside `build`, and the screens are rebuilt in a
  /// post-frame callback afterwards, so for one frame the shell holds a stack
  /// built for the old answer. The index into that stack therefore has to be
  /// resolved against the list the screens were built from, never against the
  /// list the shell would build now.
  group('the selected index reads the list the screens were built from', () {
    List<NavigationTabId> orderFor({required bool isMobile}) => NavigationTab.getVisibleTabs(
      isOffline: false,
      hasLiveTv: true,
      hasSeerr: true,
      hasWatchlist: true,
      hasBooks: true,
      isMobile: isMobile,
    ).map((tab) => tab.id).toList();

    test('every tab in the list resolves to its own entry', () {
      for (final isMobile in [false, true]) {
        final order = orderFor(isMobile: isMobile);
        for (final id in order) {
          expect(
            order[mainScreenSelectedIndex(screenOrder: order, currentTab: id)],
            id,
            reason: '$id, mobile=$isMobile',
          );
        }
      }
    });

    test('the desktop and mobile lists really do disagree about position', () {
      // The premise. Without this the test below proves nothing: on the phone
      // Series, Films and Boeken sit between Home and Bibliotheken, so the
      // same destination is at a different index in each list.
      final desktop = orderFor(isMobile: false);
      final mobile = orderFor(isMobile: true);

      expect(desktop.indexOf(NavigationTabId.libraries), isNot(mobile.indexOf(NavigationTabId.libraries)));
    });

    test('a stale stack is indexed by its own order, not by the fresh one', () {
      // The failing frame, written out: the shell has decided it is mobile,
      // `_screens` is still the desktop list, and the saved startup section is
      // Bibliotheken. Resolving against the mobile list picks position 4 and
      // hands back whatever the desktop list holds there; resolving against
      // the desktop list — which is what `_screenOrder` records — picks
      // Bibliotheken.
      final builtFrom = orderFor(isMobile: false);
      final fresh = orderFor(isMobile: true);

      final index = mainScreenSelectedIndex(screenOrder: builtFrom, currentTab: NavigationTabId.libraries);

      expect(builtFrom[index], NavigationTabId.libraries);
      expect(
        builtFrom[fresh.indexOf(NavigationTabId.libraries)],
        isNot(NavigationTabId.libraries),
        reason: 'this is the wrong screen the old computation rendered for one frame',
      );
    });

    test('a tab the stack has no entry for falls back to the first, not out of range', () {
      // Going the other way: My Pleya exists on the phone only, so a
      // mobile-to-desktop flip leaves it current with no entry to show.
      final desktop = orderFor(isMobile: false);

      expect(desktop, isNot(contains(NavigationTabId.myPleya)));
      expect(mainScreenSelectedIndex(screenOrder: desktop, currentTab: NavigationTabId.myPleya), 0);
      expect(mainScreenSelectedIndex(screenOrder: const [], currentTab: NavigationTabId.discover), 0);
    });
  });
}
