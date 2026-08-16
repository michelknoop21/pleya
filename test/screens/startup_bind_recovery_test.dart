import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/main.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
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
      final tabs = mainScreenBottomNavigationTabs(
        visibleTabs: allNavigationTabs,
        isMobile: true,
        isOffline: false,
        currentTab: NavigationTabId.discover,
      );

      expect(_ids(tabs), isNot(contains(NavigationTabId.settings)));
    });

    test('mobile offline includes Downloads but still not Settings', () {
      final offlineTabs = allNavigationTabs
          .where((tab) => tab.id == NavigationTabId.downloads || tab.id == NavigationTabId.settings)
          .toList();
      final tabs = mainScreenBottomNavigationTabs(
        visibleTabs: offlineTabs,
        isMobile: true,
        isOffline: true,
        currentTab: NavigationTabId.downloads,
      );

      expect(_ids(tabs), [NavigationTabId.downloads]);
    });

    test('Settings stays out of the bar even while it is the active screen', () {
      // Changed behaviour: Settings used to reappear as a bar item when
      // selected. It is now reached through the gear in My Pleya, and the bar
      // projects the selection onto My Pleya instead of growing a sixth slot.
      final tabs = mainScreenBottomNavigationTabs(
        visibleTabs: allNavigationTabs,
        isMobile: true,
        isOffline: false,
        currentTab: NavigationTabId.settings,
      );

      expect(_ids(tabs), isNot(contains(NavigationTabId.settings)));
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.settings, isOffline: false, barTabs: _ids(tabs)),
        NavigationTabId.myPleya,
      );
    });

    test('non-mobile returns all visible tabs unchanged', () {
      final tabs = mainScreenBottomNavigationTabs(
        visibleTabs: allNavigationTabs,
        isMobile: false,
        isOffline: false,
        currentTab: NavigationTabId.discover,
      );

      expect(tabs, same(allNavigationTabs));
    });
  });
}
