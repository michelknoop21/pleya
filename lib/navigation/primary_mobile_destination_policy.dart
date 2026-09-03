import 'navigation_tabs.dart';

/// Whether this profile has e-books it can actually open.
///
/// Three states rather than a bool, because "we do not know yet" and "there are
/// none" lead to different bars and only one of them is a decision. Sources
/// bind asynchronously after a profile switch, so a cold start passes through
/// [unknown] on every launch.
enum BooksAvailability {
  /// No answer yet: the books source has not resolved for this profile.
  unknown,

  /// Resolved: this profile has no accessible e-books.
  unavailable,

  /// Resolved: this profile has at least one e-book it may open.
  available,
}

/// The capability snapshot the mobile bar is composed from.
///
/// A value type on purpose. The policy answers from one snapshot instead of
/// reading four providers at four different moments, which is what would let
/// the fourth slot change twice on the way to the same answer.
class MobileDestinationCapabilities {
  final BooksAvailability books;
  final bool hasLiveTv;
  final bool hasWatchlist;
  final bool isOffline;

  const MobileDestinationCapabilities({
    this.books = BooksAvailability.unknown,
    this.hasLiveTv = false,
    this.hasWatchlist = false,
    this.isOffline = false,
  });
}

/// The single place that decides which destinations the mobile bottom bar
/// carries, and in which order ([DEC-094](../../docs/DECISIONS.md)).
///
/// Home, Series and Films are fixed, My Pleya is fixed at the end, and the
/// fourth slot follows the content the profile actually has: Books, else Live
/// TV, else Watchlist, else Downloads. Downloads is last because it is the one
/// candidate that is not online-only, so the bar can always reach five slots.
///
/// It exists as one policy rather than a set of `if (hasBooks)` checks spread
/// over the bar, the screens list and the selection projection: those three
/// have to agree on every frame, and three copies of the same condition is
/// exactly how they stop agreeing.
class PrimaryMobileDestinationPolicy {
  const PrimaryMobileDestinationPolicy._();

  /// The fixed part of the bar: what sits left of the dynamic slot.
  static const List<NavigationTabId> leadingDestinations = [
    NavigationTabId.discover,
    NavigationTabId.series,
    NavigationTabId.movies,
  ];

  /// The dynamic slot's candidates, in the order they win.
  static const List<NavigationTabId> dynamicCandidates = [
    NavigationTabId.books,
    NavigationTabId.liveTv,
    NavigationTabId.watchlist,
    NavigationTabId.downloads,
  ];

  /// Which destination holds the fourth slot, or `null` while the answer is
  /// still being resolved.
  ///
  /// Returning `null` on [BooksAvailability.unknown] is the anti-flapping rule.
  /// Treating "not known yet" as "no books" would hand the slot to Live TV on
  /// the frame before the books source answers, and take it away again right
  /// after: Boeken → Live TV → Boeken, twice within a second of launch. A slot
  /// that is briefly absent settles once; a slot that is briefly wrong settles
  /// twice and looks broken both times.
  static NavigationTabId? dynamicDestination(MobileDestinationCapabilities capabilities) {
    return switch (capabilities.books) {
      BooksAvailability.available => NavigationTabId.books,
      BooksAvailability.unknown => null,
      BooksAvailability.unavailable =>
        capabilities.hasLiveTv
            ? NavigationTabId.liveTv
            : capabilities.hasWatchlist
            ? NavigationTabId.watchlist
            : NavigationTabId.downloads,
    };
  }

  /// The bar's destinations, in display order.
  ///
  /// Offline is deliberately not the same bar with pieces missing: Home, Series
  /// and Films all need a server, so what is left is what the user came for.
  /// That is the behaviour the bar already had before this policy existed.
  static List<NavigationTabId> primaryDestinations(MobileDestinationCapabilities capabilities) {
    if (capabilities.isOffline) {
      return const [NavigationTabId.downloads, NavigationTabId.myPleya];
    }
    final dynamicSlot = dynamicDestination(capabilities);
    return [...leadingDestinations, ?dynamicSlot, NavigationTabId.myPleya];
  }
}
