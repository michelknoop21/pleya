/// Household activity on an item (protocol chapter 14b). Split from
/// `pleya_wire.dart`, which is already past what fits in one reading.
library;

import 'pleya_wire_parse.dart';

/// `ItemActivityEntry`: one person and what they did with an item. On a season
/// or a show the numbers add up everything underneath.
class PleyaItemActivityEntry {
  const PleyaItemActivityEntry({
    required this.userId,
    required this.username,
    required this.initials,
    required this.isSelf,
    required this.lastWatchedAt,
    required this.playCount,
    required this.completedItems,
  });

  final String userId;
  final String username;

  /// From the server, because the protocol has no avatar.
  final String initials;
  final bool isSelf;
  final DateTime lastWatchedAt;

  /// Playback sessions.
  final int playCount;

  /// Different films or episodes finished. Zero means started and not
  /// finished, so a movie must not claim "watched by" over such an entry.
  final int completedItems;

  factory PleyaItemActivityEntry.fromJson(Map<String, dynamic> json) => PleyaItemActivityEntry(
    userId: str(json, 'user_id'),
    username: str(json, 'username'),
    initials: str(json, 'initials'),
    isSelf: boolean(json, 'is_self'),
    lastWatchedAt: timestamp(json, 'last_watched_at'),
    playCount: integer(json, 'play_count'),
    completedItems: integer(json, 'completed_items'),
  );
}

/// `ItemActivity`: most recent viewer first, as the server ordered it.
class PleyaItemActivity {
  const PleyaItemActivity({required this.items});

  final List<PleyaItemActivityEntry> items;

  factory PleyaItemActivity.fromJson(Map<String, dynamic> json) => PleyaItemActivity(
    items: objectList(json['items'], 'items').map(PleyaItemActivityEntry.fromJson).toList(growable: false),
  );
}

/// `ActivitySharing`: whether this user shows up for the rest of the household.
class PleyaActivitySharing {
  const PleyaActivitySharing({required this.shareActivity});

  final bool shareActivity;

  factory PleyaActivitySharing.fromJson(Map<String, dynamic> json) =>
      PleyaActivitySharing(shareActivity: boolean(json, 'share_activity'));

  /// `ActivitySharingRequest` has the same one field and is a closed schema.
  Map<String, dynamic> toRequest() => {'share_activity': shareActivity};
}
