import 'dart:collection';

/// Remembers what the client needs to speak the ownership model from DEC-049.
///
/// Two things, and neither of them fits in the neutral `MediaServerClient`
/// surface:
///
///   * the **revision** the server last reported per item. Every write carries
///     it back as `base_revision`, and that equality is the causality claim.
///     Without it the server falls back to the ownership rule, and this client
///     would lose a write the moment another device touched the item;
///   * the **playback session** this client opened per item. `session_id` is
///     client-generated and holds for one viewing; the neutral progress-report
///     signature carries a `playSessionId` that Plex and Jellyfin fill with
///     their own session concept, so the Pleya session is kept here instead of
///     read from a parameter that means something else on the other two
///     backends.
///
/// Bounded on purpose. A profile that browses a large library would otherwise
/// grow one entry per item it ever opened, for a value that only matters while
/// something is playing.
class PleyaServerWatchLedger {
  PleyaServerWatchLedger({int capacity = 256}) : _capacity = capacity;

  final int _capacity;
  final LinkedHashMap<String, int> _revisions = LinkedHashMap<String, int>();
  final LinkedHashMap<String, String> _sessions = LinkedHashMap<String, String>();

  /// The revision to send as `base_revision`, or null when this client has
  /// never seen one for [itemId].
  ///
  /// Null is a meaningful answer and not a fallback to zero: zero claims "there
  /// is no state yet", and claiming that about an item this client simply has
  /// not read would get a legitimate write refused.
  int? revisionOf(String itemId) => _revisions[itemId];

  /// Record the revision the server just reported.
  void remember(String itemId, int? revision) {
    if (revision == null) return;
    _revisions.remove(itemId);
    _revisions[itemId] = revision;
    _trim(_revisions);
  }

  /// The session id for the viewing that is running, opening one when this is
  /// the first event for [itemId].
  String sessionFor(String itemId, String Function() mint) {
    final existing = _sessions.remove(itemId);
    if (existing != null) {
      _sessions[itemId] = existing;
      return existing;
    }
    final fresh = mint();
    _sessions[itemId] = fresh;
    _trim(_sessions);
    return fresh;
  }

  /// Start a new viewing. Called when playback starts, so a second viewing of
  /// the same title does not reuse the session the server has already leased to
  /// the first one.
  String openSession(String itemId, String Function() mint) {
    final fresh = mint();
    _sessions.remove(itemId);
    _sessions[itemId] = fresh;
    _trim(_sessions);
    return fresh;
  }

  /// End the viewing. The server keeps the lease until it expires; this only
  /// stops the client from reusing the id for the next viewing.
  void closeSession(String itemId) => _sessions.remove(itemId);

  void _trim(LinkedHashMap<String, Object> map) {
    while (map.length > _capacity) {
      map.remove(map.keys.first);
    }
  }
}
