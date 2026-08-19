/// Bridges the app's offset-based paging onto the protocol's cursors.
///
/// `LibraryQuery` carries `offset` and `limit`, because Plex and Jellyfin both
/// take a start index. Pleya Protocol takes an opaque cursor instead, on
/// purpose: an offset into a list that is being scanned shifts under the
/// reader, and chapter 12.7 of the specification says so.
///
/// The two do not translate. What does work is remembering which cursor opened
/// which offset while a user scrolls, which is the only access pattern a
/// library grid actually has: it asks for 0, then 100, then 200, in order.
///
/// So this ledger records "offset N of this listing starts at cursor C" as
/// pages come back. A caller asking for an offset it has seen the boundary for
/// resumes exactly; one asking for an offset out of nowhere gets the nearest
/// earlier boundary and the client walks forward from there rather than
/// guessing.
///
/// The ledger is per client instance and deliberately not persisted. A cursor
/// belongs to a sort and to a moment; keeping one across a restart would hand
/// the server a token from before the last scan.
class PleyaServerCursorLedger {
  /// listing key -> offset -> cursor that opens that offset.
  final Map<String, Map<int, String>> _cursors = {};

  /// listing key -> the total the server last estimated.
  final Map<String, int> _estimates = {};

  /// Identifies one listing under one ordering. Two sorts of the same library
  /// are two listings, because a cursor is only valid for the sort it was
  /// issued for.
  static String key({required String scope, required String sort}) => '$scope|$sort';

  /// The cursor that opens [offset], or null when this listing has never been
  /// walked that far.
  String? cursorFor(String key, int offset) {
    if (offset <= 0) return null;
    return _cursors[key]?[offset];
  }

  /// The furthest offset at or before [offset] this listing has a cursor for.
  /// Zero when nothing is known, which means "start from the top".
  int nearestKnownOffset(String key, int offset) {
    final known = _cursors[key];
    if (known == null) return 0;
    var best = 0;
    for (final candidate in known.keys) {
      if (candidate <= offset && candidate > best) best = candidate;
    }
    return best;
  }

  /// Record that a page starting at [offset] and holding [count] items came
  /// back with [nextCursor].
  void recordPage(String key, {required int offset, required int count, String? nextCursor, int? totalEstimate}) {
    if (totalEstimate != null) _estimates[key] = totalEstimate;
    if (nextCursor == null || count <= 0) return;
    (_cursors[key] ??= {})[offset + count] = nextCursor;
  }

  /// The server's last estimate for this listing, or null.
  ///
  /// Explicitly an estimate. The protocol says never to show it as an exact
  /// count, and the only thing the app does with it is size a scrollbar.
  int? totalEstimate(String key) => _estimates[key];

  /// Forget one listing. Called when a sort changes, because every cursor for
  /// the old ordering is invalid the moment it does.
  void invalidate(String key) {
    _cursors.remove(key);
    _estimates.remove(key);
  }

  /// Forget everything. Called on a reconnect: the catalogue may have been
  /// rescanned, and a cursor from before that is not something to hand back.
  void clear() {
    _cursors.clear();
    _estimates.clear();
  }
}
