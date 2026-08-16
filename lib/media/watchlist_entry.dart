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

  /// When the title was added, in milliseconds since epoch, but only when the
  /// source really reports it. Plenty do not: the Plex watchlist endpoint puts
  /// no timestamp on its items, and Jellyfin has no favorited-at field at all.
  final int? addedAt;

  /// Where this title sat in the list its source handed over, 0 being the most
  /// recent that source knows about.
  ///
  /// This is **ordinal, not time**. Plex returns its watchlist newest-first
  /// and that sequence is the only recency signal it gives, so the position is
  /// kept as a position. Turning it into a synthetic timestamp would create a
  /// number that looks comparable to a real Jellyfin timestamp and is not.
  final int sourcePosition;

  WatchlistMembership({required this.scope, required this.remoteKey, this.addedAt, this.sourcePosition = 0}) {
    if (remoteKey.isEmpty) {
      throw ArgumentError.value(remoteKey, 'remoteKey', 'A watchlist membership needs a remote key');
    }
    if (sourcePosition < 0) {
      throw ArgumentError.value(sourcePosition, 'sourcePosition', 'A source position cannot be negative');
    }
  }

  WatchlistMembership copyWith({int? addedAt, int? sourcePosition}) => WatchlistMembership(
    scope: scope,
    remoteKey: remoteKey,
    addedAt: addedAt ?? this.addedAt,
    sourcePosition: sourcePosition ?? this.sourcePosition,
  );

  Map<String, Object?> toJson() => {
    'scope': scope.toJson(),
    'remoteKey': remoteKey,
    if (addedAt != null) 'addedAt': addedAt,
    'sourcePosition': sourcePosition,
  };

  /// Null when the row is unreadable. A membership without a scope or a
  /// remote key cannot be removed later, so keeping it would put a title on
  /// the list that the user cannot get off it again.
  static WatchlistMembership? fromJson(Object? json) {
    if (json is! Map) return null;
    final scope = WatchlistScopeId.fromJson(json['scope']);
    final remoteKey = json['remoteKey'];
    if (scope == null || remoteKey is! String || remoteKey.isEmpty) return null;
    final addedAt = json['addedAt'];
    final sourcePosition = json['sourcePosition'];
    return WatchlistMembership(
      scope: scope,
      remoteKey: remoteKey,
      addedAt: addedAt is int ? addedAt : null,
      sourcePosition: sourcePosition is int && sourcePosition >= 0 ? sourcePosition : 0,
    );
  }

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchlistMembership &&
          other.scope == scope &&
          other.remoteKey == remoteKey &&
          other.addedAt == addedAt &&
          other.sourcePosition == sourcePosition;

  @override
  int get hashCode => Object.hash(scope, remoteKey, addedAt, sourcePosition);

  @override
  String toString() => 'WatchlistMembership(${scope.storageKey}, $remoteKey, addedAt: $addedAt, at: $sourcePosition)';
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

  Map<String, Object?> toJson() => {
    'key': key,
    'kind': kind.id,
    'item': item.toJson(),
    if (guid != null) 'guid': guid,
    'externalIds': externalIds.toJson(),
    if (posterRef != null) 'posterRef': posterRef,
    'memberships': memberships.map((m) => m.toJson()).toList(),
    'availability': availability.name,
    'coverageComplete': coverageComplete,
    if (lastKnownMatch != null) 'lastKnownMatch': lastKnownMatch!.toJson(),
  };

  /// Null when the row cannot be read back into a valid entry.
  ///
  /// The invariants hold on the way in as well as at construction: a row whose
  /// memberships all failed to parse is not an entry with an empty list, it is
  /// not an entry at all, and dropping it beats resurrecting a title nobody
  /// can remove.
  static WatchlistEntry? fromJson(Object? json) {
    if (json is! Map) return null;
    final key = json['key'];
    final itemJson = json['item'];
    if (key is! String || key.isEmpty || itemJson is! Map<String, dynamic>) return null;

    final memberships = <WatchlistMembership>[];
    final rawMemberships = json['memberships'];
    if (rawMemberships is List) {
      for (final raw in rawMemberships) {
        final membership = WatchlistMembership.fromJson(raw);
        if (membership != null) memberships.add(membership);
      }
    }
    if (memberships.isEmpty) return null;

    final MediaItem item;
    try {
      item = MediaItem.fromJson(itemJson);
    } catch (_) {
      return null;
    }

    final lastKnownJson = json['lastKnownMatch'];
    MediaItem? lastKnownMatch;
    if (lastKnownJson is Map<String, dynamic>) {
      try {
        lastKnownMatch = MediaItem.fromJson(lastKnownJson);
      } catch (_) {
        lastKnownMatch = null;
      }
    }

    final externalIds = json['externalIds'];
    final guid = json['guid'];
    final posterRef = json['posterRef'];

    return WatchlistEntry(
      key: key,
      kind: MediaKind.fromString(json['kind'] as String?),
      item: item,
      guid: guid is String ? guid : null,
      externalIds: externalIds is Map<String, Object?> ? ExternalIds.fromJson(externalIds) : const ExternalIds(),
      posterRef: posterRef is String ? posterRef : null,
      memberships: memberships,
      availability: _availabilityFromName(json['availability']),
      coverageComplete: json['coverageComplete'] == true,
      lastKnownMatch: lastKnownMatch,
    );
  }

  static WatchlistAvailability _availabilityFromName(Object? name) => switch (name) {
    'checking' => WatchlistAvailability.checking,
    'available' => WatchlistAvailability.available,
    'notFound' => WatchlistAvailability.notFound,
    _ => WatchlistAvailability.unknown,
  };

  /// Rank of this entry within its best-placed source: the lowest source
  /// priority it has a membership in, and its position inside that source.
  ///
  /// Lower is more recent, in both halves.
  (int priority, int position) rankWithin(Map<WatchlistScopeId, int> sourcePriority) {
    var best = (sourcePriority.length, 0);
    for (final membership in memberships) {
      final priority = sourcePriority[membership.scope];
      if (priority == null) continue;
      final candidate = (priority, membership.sourcePosition);
      if (candidate.$1 < best.$1 || (candidate.$1 == best.$1 && candidate.$2 < best.$2)) {
        best = candidate;
      }
    }
    return best;
  }

  /// "Recently added", newest first, for a list merged from several sources.
  ///
  /// [sourcePriority] maps each source's scope to its position in the
  /// repository, so the comparator can fall back on a deterministic order
  /// instead of on whichever source happened to be merged first.
  ///
  /// The rules, in order:
  ///
  /// 1. Two entries that both carry a real timestamp compare on it.
  /// 2. Anything else compares on source priority, then on the position that
  ///    source gave it. Plex hands over its watchlist newest-first without
  ///    timestamps, and that sequence is preserved as a sequence.
  /// 3. A tie breaks on title, and then on key, so the order is total.
  ///
  /// A timestamp is never invented from a position. The two are different
  /// kinds of thing: a position is ordinal and only means something inside its
  /// own source, while a timestamp is comparable across all of them. Minting
  /// one from the other would produce a number that looks comparable and is
  /// not, and the whole list would silently sort on a fiction.
  static Comparator<WatchlistEntry> byRecentlyAdded(Map<WatchlistScopeId, int> sourcePriority) {
    return (a, b) {
      final aAdded = a.addedAt;
      final bAdded = b.addedAt;
      if (aAdded != null && bAdded != null && aAdded != bAdded) return bAdded.compareTo(aAdded);

      final aRank = a.rankWithin(sourcePriority);
      final bRank = b.rankWithin(sourcePriority);
      if (aRank.$1 != bRank.$1) return aRank.$1.compareTo(bRank.$1);
      if (aRank.$2 != bRank.$2) return aRank.$2.compareTo(bRank.$2);

      return compareByTitle(a, b);
    };
  }

  /// Title order, case-insensitive, using the sort title when the source
  /// supplies one. Ties break on [key] so the order is total.
  static int compareByTitle(WatchlistEntry a, WatchlistEntry b) {
    final byTitle = a._sortTitle.compareTo(b._sortTitle);
    return byTitle != 0 ? byTitle : a.key.compareTo(b.key);
  }

  String get _sortTitle => (item.titleSort ?? item.title ?? '').toLowerCase();

  /// The fresher of two memberships in the same scope.
  ///
  /// A real timestamp decides. Without one the lower source position wins,
  /// because within a single source that is what "more recent" means there.
  static WatchlistMembership _newer(WatchlistMembership a, WatchlistMembership b) {
    final aAdded = a.addedAt;
    final bAdded = b.addedAt;
    if (aAdded != null && bAdded != null) return bAdded > aAdded ? b : a;
    if (bAdded == null && aAdded == null) return b.sourcePosition < a.sourcePosition ? b : a;
    return aAdded != null ? a : b;
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
