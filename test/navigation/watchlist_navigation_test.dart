import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/screens/main_screen.dart';
import 'package:pleya/services/base_shared_preferences_service.dart';
import 'package:pleya/services/settings_service.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../test_helpers/prefs.dart';

List<NavigationTabId> ids(List<NavigationTab> tabs) => tabs.map((t) => t.id).toList();

List<NavigationTabId> bar({
  required bool isOffline,
  bool hasLiveTv = true,
  bool hasSeerr = true,
  bool hasWatchlist = true,
  NavigationTabId currentTab = NavigationTabId.discover,
}) {
  return ids(
    mainScreenBottomNavigationTabs(
      visibleTabs: NavigationTab.getVisibleTabs(
        isOffline: isOffline,
        hasLiveTv: hasLiveTv,
        hasSeerr: hasSeerr,
        hasWatchlist: hasWatchlist,
        isMobile: true,
      ),
      isMobile: true,
      isOffline: isOffline,
      currentTab: currentTab,
    ),
  );
}

void main() {
  group('the existing tabs keep their order and their conditions', () {
    test('the sidebar order is unchanged apart from Watchlist being inserted', () {
      final withWatchlist = ids(
        NavigationTab.getVisibleTabs(isOffline: false, hasLiveTv: true, hasSeerr: true, hasWatchlist: true),
      );
      final without = ids(
        NavigationTab.getVisibleTabs(isOffline: false, hasLiveTv: true, hasSeerr: true, hasWatchlist: false),
      );

      expect(without, [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
        NavigationTabId.requests,
        NavigationTabId.downloads,
        NavigationTabId.settings,
      ]);
      expect(withWatchlist.where((id) => id != NavigationTabId.watchlist), without);
      expect(withWatchlist.indexOf(NavigationTabId.watchlist), 4);
    });

    test('Live TV still depends on a tuner and nothing else', () {
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasLiveTv: false, hasSeerr: true, hasWatchlist: true)),
        isNot(contains(NavigationTabId.liveTv)),
      );
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasLiveTv: true, hasSeerr: true, hasWatchlist: true)),
        contains(NavigationTabId.liveTv),
      );
    });

    test('Requests still depends on Seerr', () {
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasSeerr: false, hasWatchlist: true)),
        isNot(contains(NavigationTabId.requests)),
      );
    });

    test('Watchlist is hidden without a source or a snapshot', () {
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasWatchlist: false)),
        isNot(contains(NavigationTabId.watchlist)),
      );
    });

    test('the defaults leave both new destinations out, so existing callers are unaffected', () {
      final defaults = ids(NavigationTab.getVisibleTabs(isOffline: false, hasLiveTv: true, hasSeerr: true));

      expect(defaults, isNot(contains(NavigationTabId.watchlist)));
      expect(defaults, isNot(contains(NavigationTabId.myPleya)));
    });

    test('My Pleya never appears outside the mobile shell', () {
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasWatchlist: true, isMobile: false)),
        isNot(contains(NavigationTabId.myPleya)),
      );
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: true, hasWatchlist: true, isMobile: false)),
        isNot(contains(NavigationTabId.myPleya)),
      );
    });
  });

  group('the mobile bottom bar', () {
    test('online is Home, Libraries, Live TV, Search and My Pleya', () {
      expect(bar(isOffline: false), [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
        NavigationTabId.myPleya,
      ]);
    });

    test('never holds Downloads, Requests or Settings while online', () {
      final tabs = bar(isOffline: false);

      expect(tabs, isNot(contains(NavigationTabId.downloads)));
      expect(tabs, isNot(contains(NavigationTabId.requests)));
      expect(tabs, isNot(contains(NavigationTabId.settings)));
    });

    test('drops to four without a tuner rather than padding out to five', () {
      expect(bar(isOffline: false, hasLiveTv: false), [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.search,
        NavigationTabId.myPleya,
      ]);
    });

    test('offline is Downloads plus My Pleya, and no Settings tab', () {
      final tabs = bar(isOffline: true);

      expect(tabs, [NavigationTabId.downloads, NavigationTabId.myPleya]);
      expect(tabs, isNot(contains(NavigationTabId.settings)));
    });

    test('stays at five or fewer, so no overflow menu is ever needed', () {
      for (final offline in [false, true]) {
        for (final liveTv in [false, true]) {
          for (final seerr in [false, true]) {
            for (final watchlist in [false, true]) {
              final tabs = bar(isOffline: offline, hasLiveTv: liveTv, hasSeerr: seerr, hasWatchlist: watchlist);
              expect(tabs.length, lessThanOrEqualTo(5), reason: 'offline=$offline liveTv=$liveTv seerr=$seerr');
            }
          }
        }
      }
    });

    test('is untouched on desktop and TV', () {
      final visible = NavigationTab.getVisibleTabs(
        isOffline: false,
        hasLiveTv: true,
        hasSeerr: true,
        hasWatchlist: true,
      );
      final tabs = mainScreenBottomNavigationTabs(
        visibleTabs: visible,
        isMobile: false,
        isOffline: false,
        currentTab: NavigationTabId.discover,
      );

      expect(ids(tabs), ids(visible));
    });
  });

  group('the bottom-bar selection projection', () {
    test('online, the four bar destinations point at themselves', () {
      for (final id in [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
      ]) {
        expect(mainScreenSelectedBarTab(currentTab: id, isOffline: false, barTabs: bar(isOffline: false)), id);
      }
    });

    test('online, everything inside My Pleya lights up My Pleya', () {
      for (final id in [
        NavigationTabId.watchlist,
        NavigationTabId.downloads,
        NavigationTabId.requests,
        NavigationTabId.settings,
        NavigationTabId.myPleya,
      ]) {
        expect(
          mainScreenSelectedBarTab(currentTab: id, isOffline: false, barTabs: bar(isOffline: false)),
          NavigationTabId.myPleya,
          reason: '$id has no bar slot online',
        );
      }
    });

    test('offline, an online-only tab lands on Downloads rather than nowhere', () {
      // `_normalizeTabForMode` moves the selection to Downloads when going
      // offline. This covers the frame before that runs.
      for (final id in [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
      ]) {
        expect(
          mainScreenSelectedBarTab(currentTab: id, isOffline: true, barTabs: bar(isOffline: true)),
          NavigationTabId.downloads,
        );
      }
    });

    test('offline, Downloads points at itself and Settings at My Pleya', () {
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.downloads, isOffline: true, barTabs: bar(isOffline: true)),
        NavigationTabId.downloads,
      );
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.settings, isOffline: true, barTabs: bar(isOffline: true)),
        NavigationTabId.myPleya,
      );
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.myPleya, isOffline: true, barTabs: bar(isOffline: true)),
        NavigationTabId.myPleya,
      );
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.watchlist, isOffline: true, barTabs: bar(isOffline: true)),
        NavigationTabId.myPleya,
      );
    });

    test('every tab projects onto a destination that is actually in the bar', () {
      for (final offline in [false, true]) {
        final tabs = bar(isOffline: offline);
        for (final id in NavigationTabId.values) {
          final projected = mainScreenSelectedBarTab(currentTab: id, isOffline: offline, barTabs: tabs);
          expect(
            tabs.indexOf(projected),
            greaterThanOrEqualTo(0),
            reason: '$id projected to $projected, which is not in the ${offline ? 'offline' : 'online'} bar',
          );
        }
      }
    });

    test('no input ever lands on index -1 or outside the bar', () {
      for (final offline in [false, true]) {
        for (final liveTv in [false, true]) {
          final tabs = bar(isOffline: offline, hasLiveTv: liveTv);
          for (final id in NavigationTabId.values) {
            final index = tabs.indexOf(mainScreenSelectedBarTab(currentTab: id, isOffline: offline, barTabs: tabs));
            expect(index, inInclusiveRange(0, tabs.length - 1), reason: '$id in offline=$offline liveTv=$liveTv');
          }
        }
      }
    });
  });

  group('persisted startup section', () {
    setUp(resetSharedPreferencesForTest);

    test('a stored startup_section still reads back after the new values were inserted', () async {
      // The enum gained two values in the middle of the list. `EnumPref`
      // serialises on `.name`, so nothing may shift. Written and read through
      // the real pref rather than re-implementing the lookup in the test.
      SharedPreferences.setMockInitialValues({'startup_section': 'liveTv'});
      BaseSharedPreferencesService.resetForTesting();
      final service = await SettingsService.getInstance();

      expect(service.read(SettingsService.startupSection), NavigationTabId.liveTv);
    });

    test('every tab name round-trips through the pref', () async {
      final service = await SettingsService.getInstance();

      for (final id in NavigationTabId.values) {
        await service.write(SettingsService.startupSection, id);

        expect(service.read(SettingsService.startupSection), id, reason: '${id.name} did not survive a round trip');
      }
    });

    test('a startup section that is not visible falls back to the first tab', () {
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: false,
          hasWatchlist: false,
          preferredStartup: NavigationTabId.watchlist,
        ),
        NavigationTabId.discover,
      );
    });

    test('a visible startup section is honoured', () {
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: true,
          hasWatchlist: true,
          preferredStartup: NavigationTabId.watchlist,
        ),
        NavigationTabId.watchlist,
      );
    });

    test('offline still prefers Downloads', () {
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: true,
          hasLiveTv: false,
          hasWatchlist: true,
          isMobile: true,
          preferredStartup: NavigationTabId.watchlist,
        ),
        NavigationTabId.downloads,
      );
    });
  });
}
