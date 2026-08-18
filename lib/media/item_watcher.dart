/// Someone who watched a given media item, as reported by a source that the
/// signed-in admin is entitled to read.
///
/// Two sources fill this, and they do not share an id space: the Plex Media
/// Server calls its owner account 1, while Tautulli uses the plex.tv account id
/// (4725462 for the same person on the measured server). So [id] is only
/// comparable within one source, and "is this me" is decided by whoever built
/// the list rather than by the widget rendering it.
class ItemWatcher {
  /// Source-local identifier, used for de-duplication and as a widget key.
  final String id;

  final String displayName;

  /// Absolute avatar URL, or null for the initials fallback. Tautulli supplies
  /// one for every user; the Plex Media Server's `/accounts` returned an empty
  /// thumb for all of them on the measured server, so the fallback is the
  /// normal case there rather than an edge case.
  final String? thumbUrl;

  /// Last-viewed epoch seconds, when the source reports it. Null from
  /// Tautulli's per-title aggregate, which only counts.
  final int? viewedAt;

  /// Number of plays, when the source reports it. 0 when unknown.
  final int plays;

  /// Whether this is the signed-in user, shown as "You".
  final bool isSelf;

  const ItemWatcher({
    required this.id,
    required this.displayName,
    this.thumbUrl,
    this.viewedAt,
    this.plays = 0,
    this.isSelf = false,
  });

  /// Most recent first where a timestamp exists, most plays first otherwise.
  static int compare(ItemWatcher a, ItemWatcher b) {
    final at = a.viewedAt;
    final bt = b.viewedAt;
    if (at != null && bt != null) return bt.compareTo(at);
    return b.plays.compareTo(a.plays);
  }
}

/// What a watcher list actually claims, so the copy above it can be true.
///
/// Tautulli reports per-episode completion for a movie but only totals for a
/// series, and the Plex fallback reports completed plays either way. Saying
/// "watched by" over a series would therefore overstate what is known.
enum ItemWatchersScope {
  /// Everyone the source says finished this title.
  watched,

  /// Everyone with plays in this series, finished or not.
  watchingSeries,
}

/// A resolved watcher list plus the claim it supports.
typedef ItemWatchers = ({List<ItemWatcher> watchers, ItemWatchersScope scope});
