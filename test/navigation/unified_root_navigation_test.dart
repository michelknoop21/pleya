import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/screens/main_screen.dart';

/// The Unified 2026 root navigation, and the iPad boundary around it. iOS
/// Unified 2026 fase 2, mockups 01, 02, 05 and 18.
///
/// Destination visibility and bar presentation are pinned apart on purpose:
/// they are two policies ([RootNavigationSet] and [TabBarPresentation]) that
/// happen to be resolved from the same predicate today and may not always be.
/// `mobile_tab_bar_test.dart` owns the paint half.

List<NavigationTabId> _ids(List<NavigationTab> tabs) => tabs.map((tab) => tab.id).toList();

List<NavigationTab> _visible({
  required RootNavigationSet rootSet,
  bool isOffline = false,
  bool hasLiveTv = true,
  bool hasSeerr = true,
  bool hasWatchlist = true,
}) => NavigationTab.getVisibleTabs(
  isOffline: isOffline,
  hasLiveTv: hasLiveTv,
  hasSeerr: hasSeerr,
  hasWatchlist: hasWatchlist,
  isMobile: true,
  rootSet: rootSet,
);

List<NavigationTabId> _bar({
  required RootNavigationSet rootSet,
  bool isOffline = false,
  bool hasLiveTv = true,
  NavigationTabId currentTab = NavigationTabId.discover,
}) => _ids(
  mainScreenBottomNavigationTabs(
    visibleTabs: _visible(rootSet: rootSet, isOffline: isOffline, hasLiveTv: hasLiveTv),
    isMobile: true,
    isOffline: isOffline,
    currentTab: currentTab,
    rootSet: rootSet,
  ),
);

void main() {
  group('the iPhone bar', () {
    test('is Home · Series · Films · Live TV · Mijn Pleya, in that order', () {
      expect(_bar(rootSet: RootNavigationSet.unified2026), [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.liveTv,
        NavigationTabId.myPleya,
      ]);
    });

    test('puts Series before Films, which is the opposite of the TV order', () {
      final bar = _bar(rootSet: RootNavigationSet.unified2026);
      expect(bar.indexOf(NavigationTabId.series), lessThan(bar.indexOf(NavigationTabId.movies)));

      // And it does so without touching the shared list the desktop and TV
      // side rail render from, where Films still comes first (hoofdstuk 3).
      final shared = allNavigationTabs.map((tab) => tab.id).toList();
      expect(shared.indexOf(NavigationTabId.movies), lessThan(shared.indexOf(NavigationTabId.series)));
    });

    test('drops Live TV from the middle without disturbing the rest', () {
      expect(_bar(rootSet: RootNavigationSet.unified2026, hasLiveTv: false), [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.myPleya,
      ]);
    });

    test('keeps Bibliotheken and Zoeken as destinations: they left the bar, not the app', () {
      final visible = _ids(_visible(rootSet: RootNavigationSet.unified2026));
      expect(visible, contains(NavigationTabId.libraries));
      expect(visible, contains(NavigationTabId.search));

      final bar = _bar(rootSet: RootNavigationSet.unified2026);
      expect(bar, isNot(contains(NavigationTabId.libraries)));
      expect(bar, isNot(contains(NavigationTabId.search)));
    });

    test('leaves the offline bar exactly as it was, Downloads before Mijn Pleya', () {
      // The regression this caught, and the reason it is worth its own
      // assertion: the first version of the order projection named Mijn Pleya
      // as the fifth bar slot, which ranked it ahead of Downloads and flipped
      // the offline bar to `Mijn Pleya · Downloads`. Mijn Pleya is already
      // last in the shared list precisely because it is the rightmost slot, so
      // the projection names only the four before it. A future rank change
      // that forgets this turns this test red rather than the offline bar
      // around.
      final bar = _bar(rootSet: RootNavigationSet.unified2026, isOffline: true);
      expect(bar, [NavigationTabId.downloads, NavigationTabId.myPleya]);
      expect(
        bar.indexOf(NavigationTabId.downloads),
        lessThan(bar.indexOf(NavigationTabId.myPleya)),
        reason: 'offline, Downloads is what the user came for and stays the leftmost slot',
      );
    });

    test('still opens on Home', () {
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: true,
          hasSeerr: true,
          hasWatchlist: true,
          isMobile: true,
          rootSet: RootNavigationSet.unified2026,
          preferredStartup: null,
        ),
        NavigationTabId.discover,
      );
    });

    test('honours a startup section that no longer has a bar slot', () {
      // Zoeken is still a destination, so a stored preference for it still
      // resolves. Dropping the slot may not silently drop the setting.
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: true,
          hasSeerr: true,
          hasWatchlist: true,
          isMobile: true,
          rootSet: RootNavigationSet.unified2026,
          preferredStartup: NavigationTabId.search,
        ),
        NavigationTabId.search,
      );
    });
  });

  group('the iPhone bar selection', () {
    test('Bibliotheken lights My Pleya, the tile it is reached through', () {
      expect(
        mainScreenSelectedBarTab(
          currentTab: NavigationTabId.libraries,
          isOffline: false,
          barTabs: _bar(rootSet: RootNavigationSet.unified2026),
        ),
        NavigationTabId.myPleya,
      );
    });

    test('Zoeken lights Home, as mockup 05 draws it', () {
      expect(
        mainScreenSelectedBarTab(
          currentTab: NavigationTabId.search,
          isOffline: false,
          barTabs: _bar(rootSet: RootNavigationSet.unified2026),
        ),
        NavigationTabId.discover,
      );
    });

    test('Series and Films light themselves', () {
      for (final id in [NavigationTabId.series, NavigationTabId.movies]) {
        expect(
          mainScreenSelectedBarTab(
            currentTab: id,
            isOffline: false,
            barTabs: _bar(rootSet: RootNavigationSet.unified2026),
          ),
          id,
        );
      }
    });

    test('offline still wins for every online-only destination, Bibliotheken included', () {
      final bar = _bar(rootSet: RootNavigationSet.unified2026, isOffline: true);
      for (final id in [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
      ]) {
        expect(mainScreenSelectedBarTab(currentTab: id, isOffline: true, barTabs: bar), NavigationTabId.downloads);
      }
    });

    test('no input lands outside the bar', () {
      for (final rootSet in RootNavigationSet.values) {
        for (final isOffline in [false, true]) {
          final bar = _bar(rootSet: rootSet, isOffline: isOffline);
          for (final id in NavigationTabId.values) {
            expect(
              bar,
              contains(mainScreenSelectedBarTab(currentTab: id, isOffline: isOffline, barTabs: bar)),
              reason: '$id on $rootSet, offline=$isOffline',
            );
          }
        }
      }
    });
  });

  group('the iPad keeps the tabset it had before fase 2', () {
    test('its bar is Home · Bibliotheken · Live TV · Zoeken · Mijn Pleya', () {
      expect(_bar(rootSet: RootNavigationSet.classic), [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
        NavigationTabId.myPleya,
      ]);
    });

    test('Series and Films are not destinations there at all', () {
      final visible = _ids(_visible(rootSet: RootNavigationSet.classic));
      expect(visible, isNot(contains(NavigationTabId.series)));
      expect(visible, isNot(contains(NavigationTabId.movies)));
    });

    test('Bibliotheken still lights its own slot', () {
      expect(
        mainScreenSelectedBarTab(
          currentTab: NavigationTabId.libraries,
          isOffline: false,
          barTabs: _bar(rootSet: RootNavigationSet.classic),
        ),
        NavigationTabId.libraries,
      );
    });

    test('and its offline bar is untouched too', () {
      expect(_bar(rootSet: RootNavigationSet.classic, isOffline: true), [
        NavigationTabId.downloads,
        NavigationTabId.myPleya,
      ]);
    });
  });

  test('the default root set is the classic one, so a caller that forgets cannot migrate a shell', () {
    expect(
      _ids(NavigationTab.getVisibleTabs(isOffline: false, hasLiveTv: true, isMobile: true)),
      _ids(_visible(rootSet: RootNavigationSet.classic, hasSeerr: false, hasWatchlist: false)),
    );
  });
}
