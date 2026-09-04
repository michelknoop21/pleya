import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/navigation/tv/tv_destination.dart';
import 'package:pleya/utils/platform_detector.dart';

void main() {
  group('buildTvDestinations without live tv', () {
    final destinations = buildTvDestinations(const TvNavConditions(hasLiveTv: false));

    test('the order is exactly search, home, series, movies, my pleya', () {
      expect(destinations, [
        TvDestinationId.search,
        TvDestinationId.home,
        TvDestinationId.series,
        TvDestinationId.movies,
        TvDestinationId.myPleya,
      ]);
    });

    test('series comes before movies, per DEC-064', () {
      expect(destinations.indexOf(TvDestinationId.series), lessThan(destinations.indexOf(TvDestinationId.movies)));
    });

    test('live tv is absent', () {
      expect(destinations, isNot(contains(TvDestinationId.liveTv)));
    });

    test('my pleya is present', () {
      expect(destinations, contains(TvDestinationId.myPleya));
    });
  });

  group('buildTvDestinations with live tv', () {
    final destinations = buildTvDestinations(const TvNavConditions(hasLiveTv: true));

    test('live tv sits between movies and my pleya', () {
      expect(destinations, [
        TvDestinationId.search,
        TvDestinationId.home,
        TvDestinationId.series,
        TvDestinationId.movies,
        TvDestinationId.liveTv,
        TvDestinationId.myPleya,
      ]);
    });

    test('the relative order of the other destinations is unchanged', () {
      final withoutLiveTv = destinations.where((d) => d != TvDestinationId.liveTv).toList();
      expect(withoutLiveTv, buildTvDestinations(const TvNavConditions(hasLiveTv: false)));
    });

    test('my pleya is present', () {
      expect(destinations, contains(TvDestinationId.myPleya));
    });
  });

  group('TvDestinationId.tab', () {
    test('search maps to the search tab', () {
      expect(TvDestinationId.search.tab, NavigationTabId.search);
    });

    test('home maps to the discover tab', () {
      expect(TvDestinationId.home.tab, NavigationTabId.discover);
    });

    test('series maps to the series tab', () {
      expect(TvDestinationId.series.tab, NavigationTabId.series);
    });

    test('movies maps to the movies tab', () {
      expect(TvDestinationId.movies.tab, NavigationTabId.movies);
    });

    test('live tv maps to the live tv tab', () {
      expect(TvDestinationId.liveTv.tab, NavigationTabId.liveTv);
    });

    test('my pleya maps to the my pleya tab', () {
      expect(TvDestinationId.myPleya.tab, NavigationTabId.myPleya);
    });
  });

  group('TvDestinationId.isCompact', () {
    test('only search is drawn compact', () {
      for (final id in TvDestinationId.values) {
        expect(id.isCompact, id == TvDestinationId.search, reason: 'unexpected compact flag for $id');
      }
    });
  });

  group('TvDestinationId.focusKey', () {
    test('every destination has a distinct focus key', () {
      final keys = TvDestinationId.values.map((id) => id.focusKey).toSet();
      expect(keys.length, TvDestinationId.values.length);
    });

    test('the focus key does not depend on list position', () {
      for (final id in TvDestinationId.values) {
        final withoutLiveTv = id.focusKey;
        final inLiveTvList = buildTvDestinations(
          const TvNavConditions(hasLiveTv: true),
        ).firstWhere((d) => d == id, orElse: () => id).focusKey;
        expect(inLiveTvList, withoutLiveTv, reason: 'focusKey for $id changed depending on whether liveTv is present');
      }
    });
  });

  group('tvDestinationForTab', () {
    test('libraries lights up my pleya', () {
      expect(tvDestinationForTab(NavigationTabId.libraries), TvDestinationId.myPleya);
    });

    test('watchlist lights up my pleya', () {
      expect(tvDestinationForTab(NavigationTabId.watchlist), TvDestinationId.myPleya);
    });

    test('requests lights up my pleya', () {
      expect(tvDestinationForTab(NavigationTabId.requests), TvDestinationId.myPleya);
    });

    test('downloads lights up my pleya', () {
      expect(tvDestinationForTab(NavigationTabId.downloads), TvDestinationId.myPleya);
    });

    test('settings lights up my pleya', () {
      expect(tvDestinationForTab(NavigationTabId.settings), TvDestinationId.myPleya);
    });

    test('my pleya lights up my pleya', () {
      expect(tvDestinationForTab(NavigationTabId.myPleya), TvDestinationId.myPleya);
    });

    test('discover lights up home', () {
      expect(tvDestinationForTab(NavigationTabId.discover), TvDestinationId.home);
    });

    test('movies lights up movies', () {
      expect(tvDestinationForTab(NavigationTabId.movies), TvDestinationId.movies);
    });

    test('series lights up series', () {
      expect(tvDestinationForTab(NavigationTabId.series), TvDestinationId.series);
    });

    test('live tv lights up live tv', () {
      expect(tvDestinationForTab(NavigationTabId.liveTv), TvDestinationId.liveTv);
    });

    test('search lights up search', () {
      expect(tvDestinationForTab(NavigationTabId.search), TvDestinationId.search);
    });
  });

  group('tvRootDestination', () {
    test('the root destination is home', () {
      expect(tvRootDestination, TvDestinationId.home);
    });

    test('the root destination is not the first entry of the bar', () {
      final destinations = buildTvDestinations(const TvNavConditions(hasLiveTv: false));
      expect(destinations.first, isNot(tvRootDestination));
      expect(destinations.first, TvDestinationId.search);
    });
  });

  // ---------------------------------------------------------------------------
  // The wiring, not just the model
  // ---------------------------------------------------------------------------

  group('every destination resolves to a tab the TV shell actually builds', () {
    setUp(() => TvDetectionService.debugSetAppleTVOverride(true));
    tearDown(() => TvDetectionService.debugSetAppleTVOverride(null));

    List<NavigationTabId> visibleOnTv({bool isOffline = false}) => NavigationTab.getVisibleTabs(
      isOffline: isOffline,
      hasLiveTv: true,
      hasSeerr: true,
      hasWatchlist: true,
      // A TV is deliberately not "mobile" — see `PlatformDetector.isMobile`.
      isMobile: false,
    ).map((tab) => tab.id).toList();

    test('the bar cannot name a destination the screens list will not build', () {
      // This is the test the phase was missing. `MainScreen` walks
      // `getVisibleTabs` twice — once to build the screens list, once to guard
      // `_selectTab` — so a destination whose tab is filtered out there renders
      // a pill that lights up and does nothing, with its whole subtree dead.
      // Mijn Pleya was in exactly that state: gated on `isMobile`, which is
      // false on a TV.
      final visible = visibleOnTv();
      for (final destination in buildTvDestinations(const TvNavConditions(hasLiveTv: true))) {
        expect(
          visible,
          contains(destination.tab),
          reason: '${destination.name} is in the bar but its tab is not visible on TV',
        );
      }
    });

    test('Mijn Pleya is visible on TV, and still on mobile', () {
      expect(visibleOnTv(), contains(NavigationTabId.myPleya));
      TvDetectionService.debugSetAppleTVOverride(null);
      final mobile = NavigationTab.getVisibleTabs(isOffline: false, isMobile: true).map((t) => t.id);
      expect(mobile, contains(NavigationTabId.myPleya));
    });

    test('Mijn Pleya stays reachable offline, because it is the only way to sign out', () {
      expect(visibleOnTv(isOffline: true), contains(NavigationTabId.myPleya));
    });

    test('every Mijn Pleya section maps back to a tab the shell knows', () {
      // The redirect in `_selectTab` sends these five tabs into Mijn Pleya, so
      // each has to light the Mijn Pleya pill rather than nothing.
      for (final tab in [
        NavigationTabId.libraries,
        NavigationTabId.watchlist,
        NavigationTabId.requests,
        NavigationTabId.downloads,
        NavigationTabId.settings,
      ]) {
        expect(tvDestinationForTab(tab), TvDestinationId.myPleya);
      }
    });
  });
}
