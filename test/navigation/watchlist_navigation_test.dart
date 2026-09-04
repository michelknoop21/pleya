import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/navigation/primary_mobile_destination_policy.dart';
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
  BooksAvailability books = BooksAvailability.unavailable,
}) {
  return ids(
    mainScreenBottomNavigationTabs(
      visibleTabs: NavigationTab.getVisibleTabs(
        isOffline: isOffline,
        hasLiveTv: hasLiveTv,
        hasSeerr: hasSeerr,
        hasWatchlist: hasWatchlist,
        hasBooks: books == BooksAvailability.available,
        isMobile: true,
      ),
      isMobile: true,
      capabilities: MobileDestinationCapabilities(
        books: books,
        hasLiveTv: hasLiveTv,
        hasWatchlist: hasWatchlist,
        isOffline: isOffline,
      ),
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

    test('Series, Films and Boeken never reach the desktop or TV sidebar', () {
      // DEC-094 adds three phone destinations. The rail already reaches every
      // one of them through Bibliotheken, so it must be byte-for-byte the list
      // it was before, with or without books.
      for (final hasBooks in [false, true]) {
        final rail = ids(
          NavigationTab.getVisibleTabs(
            isOffline: false,
            hasLiveTv: true,
            hasSeerr: true,
            hasWatchlist: true,
            hasBooks: hasBooks,
            isMobile: false,
          ),
        );

        expect(rail, [
          NavigationTabId.discover,
          NavigationTabId.libraries,
          NavigationTabId.liveTv,
          NavigationTabId.search,
          NavigationTabId.watchlist,
          NavigationTabId.requests,
          NavigationTabId.downloads,
          NavigationTabId.settings,
        ], reason: 'hasBooks=$hasBooks');
      }
    });

    test('Boeken needs books, not just a phone', () {
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasBooks: false, isMobile: true)),
        isNot(contains(NavigationTabId.books)),
      );
      expect(
        ids(NavigationTab.getVisibleTabs(isOffline: false, hasBooks: true, isMobile: true)),
        contains(NavigationTabId.books),
      );
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
    test('online is Home, Series, Films, the dynamic slot and My Pleya', () {
      // DEC-094 and golden 00: five fixed positions, the fourth decided by
      // content. With a tuner and no books that fourth slot is Live TV.
      expect(bar(isOffline: false), [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.liveTv,
        NavigationTabId.myPleya,
      ]);
    });

    test('never holds Zoeken, Bibliotheken, Requests or Settings while online', () {
      final tabs = bar(isOffline: false);

      // Zoeken moved to the header icon and Bibliotheken behind My Pleya.
      expect(tabs, isNot(contains(NavigationTabId.search)));
      expect(tabs, isNot(contains(NavigationTabId.libraries)));
      expect(tabs, isNot(contains(NavigationTabId.requests)));
      expect(tabs, isNot(contains(NavigationTabId.settings)));
    });

    test('the fourth slot follows Boeken, Live TV, Kijklijst, Downloads in that order', () {
      NavigationTabId? fourth(List<NavigationTabId> tabs) => tabs.length == 5 ? tabs[3] : null;

      expect(
        fourth(bar(isOffline: false, books: BooksAvailability.available, hasLiveTv: true, hasWatchlist: true)),
        NavigationTabId.books,
      );
      expect(fourth(bar(isOffline: false, hasLiveTv: true, hasWatchlist: true)), NavigationTabId.liveTv);
      expect(fourth(bar(isOffline: false, hasLiveTv: false, hasWatchlist: true)), NavigationTabId.watchlist);
      expect(fourth(bar(isOffline: false, hasLiveTv: false, hasWatchlist: false)), NavigationTabId.downloads);
    });

    test('while books are still unknown the slot stays empty rather than flapping', () {
      // The startup sequence DEC-094 forbids is Boeken -> Live TV -> Boeken.
      // Four slots settle once; a wrong fourth slot settles twice.
      final booting = bar(isOffline: false, books: BooksAvailability.unknown, hasLiveTv: true);

      expect(booting, [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
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
              for (final books in BooksAvailability.values) {
                final tabs = bar(
                  isOffline: offline,
                  hasLiveTv: liveTv,
                  hasSeerr: seerr,
                  hasWatchlist: watchlist,
                  books: books,
                );
                expect(
                  tabs.length,
                  lessThanOrEqualTo(5),
                  reason: 'offline=$offline liveTv=$liveTv seerr=$seerr books=$books',
                );
              }
            }
          }
        }
      }
    });

    test('online it never falls below four, so the shell never looks broken', () {
      for (final liveTv in [false, true]) {
        for (final watchlist in [false, true]) {
          for (final books in BooksAvailability.values) {
            final tabs = bar(isOffline: false, hasLiveTv: liveTv, hasWatchlist: watchlist, books: books);
            expect(tabs.length, greaterThanOrEqualTo(4), reason: 'liveTv=$liveTv watchlist=$watchlist books=$books');
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
      final tabs = mainScreenBottomNavigationTabs(visibleTabs: visible, isMobile: false);

      expect(ids(tabs), ids(visible));
    });
  });

  group('the bottom-bar selection projection', () {
    test('online, the bar destinations point at themselves', () {
      for (final id in [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.liveTv,
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
        NavigationTabId.series,
        NavigationTabId.movies,
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

    /// The two destinations DEC-094 took out of the bar without putting them
    /// in the dynamic slot. Both used to name themselves, fail the
    /// `barTabs.contains` check, and fall through to `barTabs.first`: opening
    /// Zoeken from the Home header showed Zoeken with Home marked, and the
    /// same happened for Bibliotheken, which since the My Pleya rows is
    /// reached from there.
    test('online, Bibliotheken lights up My Pleya, where it is reached from', () {
      expect(
        mainScreenSelectedBarTab(
          currentTab: NavigationTabId.libraries,
          isOffline: false,
          barTabs: bar(isOffline: false),
        ),
        NavigationTabId.myPleya,
      );
    });

    test('online, Zoeken lights up Home, where its glyph lives', () {
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.search, isOffline: false, barTabs: bar(isOffline: false)),
        NavigationTabId.discover,
      );
    });

    /// Boeken, Live TV, Kijklijst and Downloads compete for one slot, so
    /// whether a destination has a slot depends on the profile. Each has to
    /// mark itself when it won and My Pleya when it did not; a single answer
    /// could only be right for one of the two.
    test('a dynamic-slot candidate marks itself when it won and My Pleya when it did not', () {
      final withLiveTv = bar(isOffline: false, hasLiveTv: true);
      final withBooks = bar(isOffline: false, hasLiveTv: true, books: BooksAvailability.available);

      expect(withLiveTv, contains(NavigationTabId.liveTv));
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.liveTv, isOffline: false, barTabs: withLiveTv),
        NavigationTabId.liveTv,
      );

      expect(withBooks, isNot(contains(NavigationTabId.liveTv)));
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.liveTv, isOffline: false, barTabs: withBooks),
        NavigationTabId.myPleya,
        reason: 'Boeken took the slot, so Live TV is reached through My Pleya and marks that',
      );

      final withWatchlist = bar(isOffline: false, hasLiveTv: false, hasWatchlist: true);
      expect(withWatchlist, contains(NavigationTabId.watchlist));
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.watchlist, isOffline: false, barTabs: withWatchlist),
        NavigationTabId.watchlist,
        reason: 'the Kijklijst slot marks itself rather than the hub it is also listed in',
      );

      final withDownloads = bar(isOffline: false, hasLiveTv: false, hasWatchlist: false);
      expect(withDownloads, contains(NavigationTabId.downloads));
      expect(
        mainScreenSelectedBarTab(currentTab: NavigationTabId.downloads, isOffline: false, barTabs: withDownloads),
        NavigationTabId.downloads,
      );
    });

    test('every tab projects onto a destination that is actually in the bar', () {
      for (final offline in [false, true]) {
        final tabs = bar(isOffline: offline, books: BooksAvailability.available);
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
          for (final books in BooksAvailability.values) {
            final tabs = bar(isOffline: offline, hasLiveTv: liveTv, books: books);
            for (final id in NavigationTabId.values) {
              final index = tabs.indexOf(mainScreenSelectedBarTab(currentTab: id, isOffline: offline, barTabs: tabs));
              expect(
                index,
                inInclusiveRange(0, tabs.length - 1),
                reason: '$id in offline=$offline liveTv=$liveTv books=$books',
              );
            }
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
