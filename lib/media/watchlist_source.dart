import 'media_item.dart';
import 'watchlist_entry.dart';
import 'watchlist_scope.dart';

/// One place that holds a watchlist for the active profile.
///
/// Two shapes exist today and they are not the same kind of thing. The Plex
/// account watchlist belongs to a plex.tv account plus a Home user and lives
/// nowhere near a server. Jellyfin favorites belong to a user on one specific
/// server, so a profile with three Jellyfin connections has three of them.
/// That asymmetry is why `fetchWatchlist` cannot sit on `MediaServerClient`.
///
/// A source owns exactly one [scope] and never answers for another. It also
/// decides for itself whether it is allowed to speak: the Plex source
/// re-checks scoped auth on every operation rather than trusting a token it
/// resolved once.
abstract interface class WatchlistSource {
  /// Which list this source speaks for.
  WatchlistScopeId get scope;

  /// Whether this source can hold [item]. A Jellyfin item belongs on the
  /// favorites of its own server; a Plex item with a `plex://` guid belongs on
  /// the account watchlist; anything without a usable identity belongs
  /// nowhere, and saying so here keeps the repository from having to guess.
  bool accepts(MediaItem item);

  /// Everything on this list, in the source's own order.
  ///
  /// The order carries meaning the entries themselves do not: Plex returns
  /// newest-first and does not put a timestamp on the items, so the sequence
  /// is the only "recently added" signal available without a call per title.
  Future<List<WatchlistEntry>> fetch();

  /// Put [item] on this list. Returns the membership that now exists, so the
  /// caller can patch its state without a refetch.
  ///
  /// Adding something that is already on the list is not an error.
  Future<WatchlistMembership> add(MediaItem item);

  /// Take the title identified by [membership] off this list.
  ///
  /// Removing something that is not on the list is not an error either, which
  /// matters for the compensating writes: a retry must not fail on the step
  /// that already succeeded.
  Future<void> remove(WatchlistMembership membership);

  /// Whether [item] is on this list right now, or null when the source cannot
  /// answer cheaply. Callers treat null as "ask the full list".
  Future<bool?> contains(MediaItem item);
}

/// Thrown when a source is asked to act while it cannot prove it is talking
/// for the user the app is showing.
///
/// This is deliberately not an empty result. An empty watchlist and a
/// watchlist the app is not allowed to read look identical to the UI, and the
/// difference is exactly the one that would show one Home user another's list.
class WatchlistScopeUnavailable implements Exception {
  final String reason;

  const WatchlistScopeUnavailable(this.reason);

  @override
  String toString() => 'WatchlistScopeUnavailable: $reason';
}
