import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/screens/main_screen.dart';

/// The tabset iOS Unified 2026 fase 2 gives the iPhone, and the promise that
/// comes with it: no destination lost a slot without gaining an entry point
/// somewhere else ([DEC-094], `01-series-landing.png`, `05-zoeken.png`).
///
/// Built from the real `getVisibleTabs` and the real
/// `mainScreenBottomNavigationTabs` rather than a fixture, so a tabset change
/// breaks here too.
List<NavigationTabId> _ids(List<NavigationTab> tabs) => tabs.map((t) => t.id).toList();

List<NavigationTabId> _visible({
  required bool isOffline,
  bool hasLiveTv = true,
  bool hasSeerr = true,
  bool hasWatchlist = true,
  required bool isPhone,
}) => _ids(
  NavigationTab.getVisibleTabs(
    isOffline: isOffline,
    hasLiveTv: hasLiveTv,
    hasSeerr: hasSeerr,
    hasWatchlist: hasWatchlist,
    isMobile: true,
    isPhone: isPhone,
  ),
);

List<NavigationTabId> _bar({
  required bool isOffline,
  bool hasLiveTv = true,
  bool hasSeerr = true,
  bool hasWatchlist = true,
  required bool isPhone,
  NavigationTabId currentTab = NavigationTabId.discover,
}) => _ids(
  mainScreenBottomNavigationTabs(
    visibleTabs: NavigationTab.getVisibleTabs(
      isOffline: isOffline,
      hasLiveTv: hasLiveTv,
      hasSeerr: hasSeerr,
      hasWatchlist: hasWatchlist,
      isMobile: true,
      isPhone: isPhone,
    ),
    isMobile: true,
    isPhone: isPhone,
    isOffline: isOffline,
    currentTab: currentTab,
  ),
);

void main() {
  group('the phone bottom bar', () {
    test('online is Home, Series, Films, Live TV and Mijn Pleya, in that order', () {
      expect(_bar(isOffline: false, isPhone: true), [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.liveTv,
        NavigationTabId.myPleya,
      ]);
    });

    test('Series comes before Films, which is the opposite of the TV order', () {
      final bar = _bar(isOffline: false, isPhone: true);
      expect(
        bar.indexOf(NavigationTabId.series),
        lessThan(bar.indexOf(NavigationTabId.movies)),
        reason: '01-series-landing.png draws Series in slot two',
      );
      final all = allNavigationTabs.map((t) => t.id).toList();
      expect(
        all.indexOf(NavigationTabId.movies),
        lessThan(all.indexOf(NavigationTabId.series)),
        reason: 'the shared list keeps the TV order it was given under a TV authority',
      );
    });

    test('drops to four without a tuner rather than padding out to five', () {
      expect(_bar(isOffline: false, hasLiveTv: false, isPhone: true), [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.myPleya,
      ]);
    });

    test('stays at five or fewer, so no overflow menu is ever needed', () {
      for (final offline in [false, true]) {
        for (final liveTv in [false, true]) {
          for (final seerr in [false, true]) {
            for (final watchlist in [false, true]) {
              final bar = _bar(
                isOffline: offline,
                hasLiveTv: liveTv,
                hasSeerr: seerr,
                hasWatchlist: watchlist,
                isPhone: true,
              );
              expect(bar.length, lessThanOrEqualTo(5), reason: 'offline=$offline liveTv=$liveTv seerr=$seerr');
            }
          }
        }
      }
    });

    test('offline is unchanged by fase 2: Downloads plus Mijn Pleya', () {
      expect(_bar(isOffline: true, isPhone: true), [NavigationTabId.downloads, NavigationTabId.myPleya]);
    });
  });

  group('the iPad is untouched by fase 2', () {
    test('it keeps its own bar, without Series and Films', () {
      expect(_bar(isOffline: false, isPhone: false), [
        NavigationTabId.discover,
        NavigationTabId.libraries,
        NavigationTabId.liveTv,
        NavigationTabId.search,
        NavigationTabId.myPleya,
      ]);
    });

    test('Series and Films are not even destinations there', () {
      final visible = _visible(isOffline: false, isPhone: false);
      expect(visible, isNot(contains(NavigationTabId.series)));
      expect(visible, isNot(contains(NavigationTabId.movies)));
    });
  });

  group('which slot lights up', () {
    test('on the phone Series and Films light themselves', () {
      final bar = _bar(isOffline: false, isPhone: true);
      for (final id in [NavigationTabId.series, NavigationTabId.movies, NavigationTabId.discover]) {
        expect(mainScreenSelectedBarTab(currentTab: id, isOffline: false, barTabs: bar), id);
      }
    });

    test('on the phone Bibliotheken lights Mijn Pleya, because that is where its entry point is', () {
      expect(
        mainScreenSelectedBarTab(
          currentTab: NavigationTabId.libraries,
          isOffline: false,
          barTabs: _bar(isOffline: false, isPhone: true),
        ),
        NavigationTabId.myPleya,
        reason: 'falling back to barTabs.first would light Home while the user is in Bibliotheken',
      );
    });

    test('on the phone Zoeken lights Home, because that is where its entry point is', () {
      expect(
        mainScreenSelectedBarTab(
          currentTab: NavigationTabId.search,
          isOffline: false,
          barTabs: _bar(isOffline: false, isPhone: true),
        ),
        NavigationTabId.discover,
        reason: '05-zoeken.png shows the search surface with Home active',
      );
    });

    test('on the iPad both still light themselves, because they still have a slot', () {
      final bar = _bar(isOffline: false, isPhone: false);
      for (final id in [NavigationTabId.libraries, NavigationTabId.search]) {
        expect(mainScreenSelectedBarTab(currentTab: id, isOffline: false, barTabs: bar), id);
      }
    });
  });

  group('no destination is lost', () {
    test('everything that left the phone bar is still a destination', () {
      final visible = _visible(isOffline: false, isPhone: true);
      final bar = _bar(isOffline: false, isPhone: true);

      for (final id in [
        NavigationTabId.libraries,
        NavigationTabId.search,
        NavigationTabId.watchlist,
        NavigationTabId.downloads,
        NavigationTabId.requests,
        NavigationTabId.settings,
      ]) {
        expect(bar, isNot(contains(id)), reason: '$id has no bar slot on a phone');
        expect(
          visible,
          contains(id),
          reason: '$id must stay in getVisibleTabs, which is the list _buildScreens and _selectTab both walk',
        );
      }
    });

    test('offline the four online-only destinations are the ones that go, as they always did', () {
      final visible = _visible(isOffline: true, isPhone: true);
      for (final id in [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.libraries,
        NavigationTabId.search,
        NavigationTabId.liveTv,
        NavigationTabId.requests,
      ]) {
        expect(visible, isNot(contains(id)), reason: '$id is onlineOnly');
      }
      for (final id in [
        NavigationTabId.watchlist,
        NavigationTabId.downloads,
        NavigationTabId.settings,
        NavigationTabId.myPleya,
      ]) {
        expect(visible, contains(id), reason: '$id stays reachable offline');
      }
    });
  });

  group('the startup section', () {
    test('an unreachable stored section still falls back to Home rather than nowhere', () {
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: false,
          isMobile: true,
          isPhone: false,
          preferredStartup: NavigationTabId.series,
        ),
        NavigationTabId.discover,
        reason: 'Series is not offered as a startup section, and an old value must not strand the app',
      );
    });

    test('a phone honours a stored section that is visible', () {
      expect(
        NavigationTab.resolveDefaultTab(
          isOffline: false,
          hasLiveTv: false,
          isMobile: true,
          isPhone: true,
          preferredStartup: NavigationTabId.search,
        ),
        NavigationTabId.search,
      );
    });
  });
}
