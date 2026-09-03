import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/navigation/navigation_tabs.dart';
import 'package:pleya/navigation/primary_mobile_destination_policy.dart';

MobileDestinationCapabilities caps({
  BooksAvailability books = BooksAvailability.unavailable,
  bool hasLiveTv = false,
  bool hasWatchlist = false,
  bool isOffline = false,
}) =>
    MobileDestinationCapabilities(books: books, hasLiveTv: hasLiveTv, hasWatchlist: hasWatchlist, isOffline: isOffline);

void main() {
  group('the dynamic fourth slot', () {
    test('Boeken wins from everything else', () {
      expect(
        PrimaryMobileDestinationPolicy.dynamicDestination(
          caps(books: BooksAvailability.available, hasLiveTv: true, hasWatchlist: true),
        ),
        NavigationTabId.books,
      );
    });

    test('without books it falls to Live TV, then Kijklijst, then Downloads', () {
      expect(
        PrimaryMobileDestinationPolicy.dynamicDestination(caps(hasLiveTv: true, hasWatchlist: true)),
        NavigationTabId.liveTv,
      );
      expect(PrimaryMobileDestinationPolicy.dynamicDestination(caps(hasWatchlist: true)), NavigationTabId.watchlist);
      expect(PrimaryMobileDestinationPolicy.dynamicDestination(caps()), NavigationTabId.downloads);
    });

    test('Downloads is the floor, so the slot is never empty once books resolved', () {
      for (final liveTv in [false, true]) {
        for (final watchlist in [false, true]) {
          expect(
            PrimaryMobileDestinationPolicy.dynamicDestination(caps(hasLiveTv: liveTv, hasWatchlist: watchlist)),
            isNotNull,
            reason: 'liveTv=$liveTv watchlist=$watchlist',
          );
        }
      }
    });

    test('an unresolved books answer reserves the slot instead of guessing', () {
      // The flap DEC-069 forbids: treating unknown as "no books" hands the slot
      // to Live TV and takes it back one frame later.
      expect(
        PrimaryMobileDestinationPolicy.dynamicDestination(
          caps(books: BooksAvailability.unknown, hasLiveTv: true, hasWatchlist: true),
        ),
        isNull,
      );
    });

    test('every candidate the policy can name is one the enum has', () {
      for (final id in PrimaryMobileDestinationPolicy.dynamicCandidates) {
        expect(NavigationTabId.values, contains(id));
      }
    });
  });

  group('the primary bar', () {
    test('online it is Home, Series, Films, the dynamic slot and Mijn Pleya', () {
      expect(PrimaryMobileDestinationPolicy.primaryDestinations(caps(books: BooksAvailability.available)), [
        NavigationTabId.discover,
        NavigationTabId.series,
        NavigationTabId.movies,
        NavigationTabId.books,
        NavigationTabId.myPleya,
      ]);
    });

    test('Zoeken is not a destination in it', () {
      for (final books in BooksAvailability.values) {
        expect(
          PrimaryMobileDestinationPolicy.primaryDestinations(caps(books: books, hasLiveTv: true, hasWatchlist: true)),
          isNot(contains(NavigationTabId.search)),
        );
      }
    });

    test('offline it is Downloads plus Mijn Pleya, unchanged from before', () {
      expect(
        PrimaryMobileDestinationPolicy.primaryDestinations(
          caps(isOffline: true, books: BooksAvailability.available, hasLiveTv: true),
        ),
        [NavigationTabId.downloads, NavigationTabId.myPleya],
      );
    });

    test('the first three slots never move', () {
      for (final books in BooksAvailability.values) {
        for (final liveTv in [false, true]) {
          final tabs = PrimaryMobileDestinationPolicy.primaryDestinations(caps(books: books, hasLiveTv: liveTv));

          expect(tabs.take(3), PrimaryMobileDestinationPolicy.leadingDestinations, reason: '$books liveTv=$liveTv');
          expect(tabs.last, NavigationTabId.myPleya);
        }
      }
    });

    test('it holds no duplicates, whatever the capabilities are', () {
      for (final books in BooksAvailability.values) {
        for (final liveTv in [false, true]) {
          for (final watchlist in [false, true]) {
            for (final offline in [false, true]) {
              final tabs = PrimaryMobileDestinationPolicy.primaryDestinations(
                caps(books: books, hasLiveTv: liveTv, hasWatchlist: watchlist, isOffline: offline),
              );

              expect(tabs.toSet().length, tabs.length, reason: '$tabs');
            }
          }
        }
      }
    });
  });
}
