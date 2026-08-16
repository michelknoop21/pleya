import '../utils/external_ids.dart';
import 'media_item.dart';
import 'media_kind.dart';
import 'watchlist_scope.dart';

/// How far the app got in answering "can this title be played from one of the
/// servers this profile can reach".
///
/// [unknown] and [checking] are not the same thing. The list resolves lazily,
/// driven by the viewport, so most entries sit at [unknown] because nothing
/// has been scheduled for them yet. Only [checking] means a lookup is running.
enum WatchlistAvailability {
  /// Not looked up yet, and nothing scheduled.
  unknown,

  /// A lookup is running right now.
  checking,

  /// Found on a server this profile can reach.
  available,

  /// Looked up and not found. Read together with
  /// [WatchlistEntry.coverageComplete] before drawing any conclusion.
  notFound,
}

/// One source that holds this title on a watchlist.
///
/// [remoteKey] is not nullable on purpose. Without a remote identity a
/// membership cannot be removed reliably, and it certainly cannot be added
/// back when a partly failed removal has to be compensated. A source that
/// cannot produce a key does not produce a membership either.
class WatchlistMembership {
  /// Which watchlist, on which account, for which user, under which profile.
  final WatchlistScopeId scope;

  /// The id this source uses for the title: the discover rating key for Plex,
  /// the item id for Jellyfin.
  final String remoteKey;

  /// When the title was added, in milliseconds since epoch, when the source
  /// reports it. Plenty of sources do not.
  final int? addedAt;

  WatchlistMembership({required this.scope, required this.remoteKey, this.addedAt}) {
    if (remoteKey.isEmpty) {
      throw ArgumentError.value(remoteKey, 'remoteKey', 'A watchlist membership needs a remote key');
    }
  }

  WatchlistMembership copyWith({int? addedAt}) =>
      WatchlistMembership(scope: scope, remoteKey: remoteKey, addedAt: addedAt ?? this.addedAt);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchlistMembership && other.scope == scope && other.remoteKey == remoteKey && other.addedAt == addedAt;

  @override
  int get hashCode => Object.hash(scope, remoteKey, addedAt);

  @override
  String toString() => 'WatchlistMembership(${scope.storageKey}, $remoteKey, addedAt: $addedAt)';
}

/// One title on the merged kijklijst.
///
/// **An entry always holds at least one membership.** The same film can sit on
/// the Plex watchlist and be a Jellyfin favorite at the same time. A model that
/// can only carry one source loses the other one during the merge, and then
/// removing the title leaves the forgotten copy behind: the title comes back
/// on the next refresh and it reads as "removing does not work". An entry
/// without memberships is not a watchlist item at all, so the constructor
/// rejects it rather than letting an empty one travel through the app.
class WatchlistEntry {
  /// Canonical identity, from `watchlistKeyForItem`. Shared with the same
  /// title as seen on a server, so the detail screen and this list agree.
  final String key;

  final MediaKind kind;

  /// Catalogue item as the source described it. `serverId` is null for a
  /// discover item, which is exactly why this is not a [MediaItem] variant.
  final MediaItem item;

  /// Source guid, when the source has one (`plex://movie/...`).
  final String? guid;

  final ExternalIds externalIds;

  /// Opaque poster reference. Deliberately not a ready-made URL: an account
  /// token must not end up baked into a persistent image cache key.
  final String? posterRef;

  /// Every source that holds this title. Never empty.
  final List<WatchlistMembership> memberships;

  final WatchlistAvailability availability;

  /// Whether every server this profile was expected to check actually
  /// answered. A [WatchlistAvailability.notFound] with `false` here says
  /// nothing durable: the missing server may hold the title.
  final bool coverageComplete;

  /// Last server item this title resolved to. Named for what it is: it may
  /// come from an older snapshot while that server is offline right now, so
  /// it is not proof that the title can be played.
  final MediaItem? lastKnownMatch;

  WatchlistEntry({
    required this.key,
    required this.kind,
    required this.item,
    required List<WatchlistMembership> memberships,
    this.guid,
    this.externalIds = const ExternalIds(),
    this.posterRef,
    this.availability = WatchlistAvailability.unknown,
    this.coverageComplete = false,
    this.lastKnownMatch,
  }) : memberships = List.unmodifiable(_requireMemberships(memberships)) {
    if (key.isEmpty) {
      throw ArgumentError.value(key, 'key', 'A watchlist entry needs a canonical key');
    }
  }

  static List<WatchlistMembership> _requireMemberships(List<WatchlistMembership> memberships) {
    if (memberships.isEmpty) {
      throw ArgumentError.value(memberships, 'memberships', 'A watchlist entry needs at least one membership');
    }
    return memberships;
  }

  /// The membership held by [scope], or null when this scope does not hold the
  /// title.
  WatchlistMembership? membershipFor(WatchlistScopeId scope) {
    for (final membership in memberships) {
      if (membership.scope == scope) return membership;
    }
    return null;
  }

  /// Newest `addedAt` across all memberships, or null when no source reported
  /// one. Used for "Recently added": a title added to Jellyfin last year and
  /// to the Plex watchlist this morning is a recent addition.
  int? get addedAt {
    int? newest;
    for (final membership in memberships) {
      final added = membership.addedAt;
      if (added == null) continue;
      if (newest == null || added > newest) newest = added;
    }
    return newest;
  }

  /// This entry with [scope]'s membership dropped, or `null` when that was the
  /// last one and the title leaves the list entirely.
  ///
  /// Removing a title is a walk over every membership; this returns the state
  /// after one of those steps, which is also the state a compensating write
  /// has to restore when a later step fails.
  WatchlistEntry? withoutMembership(WatchlistScopeId scope) {
    final remaining = memberships.where((m) => m.scope != scope).toList();
    if (remaining.length == memberships.length) return this;
    if (remaining.isEmpty) return null;
    return copyWith(memberships: remaining);
  }

  /// Fold [other] into this entry, keeping this entry's identity.
  ///
  /// Memberships are joined, never dropped: that union is the whole point of
  /// the model. When both sides hold the same scope, the membership with the
  /// newer timestamp wins so a stale snapshot cannot age a title backwards.
  /// The resolve result ([availability], [coverageComplete], [lastKnownMatch])
  /// travels as one unit and is taken from whichever side got further, because
  /// mixing "available" with the other side's null match would claim a match
  /// the app does not hold.
  WatchlistEntry mergeWith(WatchlistEntry other) {
    final merged = <WatchlistScopeId, WatchlistMembership>{};
    for (final membership in [...memberships, ...other.memberships]) {
      final existing = merged[membership.scope];
      merged[membership.scope] = existing == null ? membership : _newer(existing, membership);
    }

    final winner = _rank(other.availability) > _rank(availability) ? other : this;

    return WatchlistEntry(
      key: key,
      kind: kind != MediaKind.unknown ? kind : other.kind,
      item: item,
      guid: guid ?? other.guid,
      externalIds: ExternalIds(
        imdb: externalIds.imdb ?? other.externalIds.imdb,
        tmdb: externalIds.tmdb ?? other.externalIds.tmdb,
        tvdb: externalIds.tvdb ?? other.externalIds.tvdb,
      ),
      posterRef: posterRef ?? other.posterRef,
      memberships: merged.values.toList(),
      availability: winner.availability,
      coverageComplete: winner.coverageComplete,
      lastKnownMatch: winner.lastKnownMatch,
    );
  }

  WatchlistEntry copyWith({
    List<WatchlistMembership>? memberships,
    String? posterRef,
    WatchlistAvailability? availability,
    bool? coverageComplete,
    MediaItem? lastKnownMatch,
  }) {
    return WatchlistEntry(
      key: key,
      kind: kind,
      item: item,
      guid: guid,
      externalIds: externalIds,
      posterRef: posterRef ?? this.posterRef,
      memberships: memberships ?? this.memberships,
      availability: availability ?? this.availability,
      coverageComplete: coverageComplete ?? this.coverageComplete,
      lastKnownMatch: lastKnownMatch ?? this.lastKnownMatch,
    );
  }

  /// "Recently added", newest first.
  ///
  /// An entry whose sources never reported a timestamp counts as the oldest
  /// known and then falls back to title, so the order does not silently depend
  /// on which source happened to be merged first.
  static int compareByRecentlyAdded(WatchlistEntry a, WatchlistEntry b) {
    final aAdded = a.addedAt;
    final bAdded = b.addedAt;
    if (aAdded != bAdded) {
      if (aAdded == null) return 1;
      if (bAdded == null) return -1;
      return bAdded.compareTo(aAdded);
    }
    return compareByTitle(a, b);
  }

  /// Title order, case-insensitive, using the sort title when the source
  /// supplies one. Ties break on [key] so the order is total.
  static int compareByTitle(WatchlistEntry a, WatchlistEntry b) {
    final byTitle = a._sortTitle.compareTo(b._sortTitle);
    return byTitle != 0 ? byTitle : a.key.compareTo(b.key);
  }

  String get _sortTitle => (item.titleSort ?? item.title ?? '').toLowerCase();

  static WatchlistMembership _newer(WatchlistMembership a, WatchlistMembership b) {
    final aAdded = a.addedAt;
    final bAdded = b.addedAt;
    if (bAdded == null) return a;
    if (aAdded == null) return b;
    return bAdded > aAdded ? b : a;
  }

  static int _rank(WatchlistAvailability availability) => switch (availability) {
    WatchlistAvailability.unknown => 0,
    WatchlistAvailability.checking => 1,
    WatchlistAvailability.notFound => 2,
    WatchlistAvailability.available => 3,
  };

  @override
  String toString() => 'WatchlistEntry($key, ${item.title}, ${memberships.length} membership(s), ${availability.name})';
}
