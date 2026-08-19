import 'package:flutter/foundation.dart';

import '../media/media_item.dart';

/// Stable identity of a hub item, and the single place that decides what
/// "the same item" means for a row.
///
/// [MediaItem.globalKey] is `serverId:id`, so it is scoped to the server the
/// item came from and carries no backend-specific assumption: it lives on the
/// base [MediaItem], and Plex, Jellyfin and local items all fill it the same
/// way. A bare Plex ratingKey would not do, because two servers can hand out
/// the same one.
///
/// It falls back to the bare id when an item has no `serverId`. Hub items come
/// from a server and do carry one; the fallback exists for detached items and
/// is only ever compared against other items in the same list.
String hubItemIdentity(MediaItem item) => item.globalKey;

/// What a hub's cursor points at.
///
/// Three states that must never collapse into one nullable field: a concrete
/// media item, the trailing "View All" card, and "nothing chosen yet". A null
/// key cannot tell the last two apart, and that ambiguity is what let an
/// activation fall through to whatever sat at the old index.
@immutable
sealed class HubFocusTarget {
  const HubFocusTarget();
}

/// No deliberate choice yet: the row was just built and the cursor is wherever
/// it was restored to. Activation may fall back to the index.
final class HubFocusNone extends HubFocusTarget {
  const HubFocusNone();
}

/// A media item, held by identity rather than by position.
final class HubFocusItem extends HubFocusTarget {
  const HubFocusItem(this.identity);

  final String identity;

  @override
  bool operator ==(Object other) => other is HubFocusItem && other.identity == identity;

  @override
  int get hashCode => identity.hashCode;
}

/// The trailing card that opens the whole hub.
final class HubFocusViewAll extends HubFocusTarget {
  const HubFocusViewAll();
}

/// How an activation reached its target. Reported in the log so a wrong-title
/// report can be answered from one line instead of reconstructed from HTTP.
enum HubActivationStrategy {
  /// Resolved through the remembered identity. The normal path.
  identity,

  /// No identity yet, so the index decided. First frame, or a restore.
  initialIndex,

  /// The trailing "View All" card.
  viewAll,

  /// A known identity is no longer in the list. The activation is dropped
  /// rather than silently opening whoever took that slot.
  staleDropped,

  /// Nothing to activate: empty row, or an index outside it.
  none,
}

/// Outcome of resolving one activation.
@immutable
class HubActivation {
  const HubActivation({required this.strategy, this.item, this.index = -1});

  /// The item to act on. Null for [HubActivationStrategy.viewAll],
  /// [HubActivationStrategy.staleDropped] and [HubActivationStrategy.none].
  final MediaItem? item;

  final HubActivationStrategy strategy;

  /// Where the resolved item sits now, or -1 when there is no item.
  final int index;

  bool get opensItem => item != null;
}

/// Decides what a hub activation acts on, from the row as it stands right now.
///
/// Pure on purpose, the same reason `resolveOverlaySheetGeometry` is: the rule
/// that matters here is "which item", and it should be testable without a
/// widget tree, a focus system or a navigator.
///
/// The order is deliberate. Identity wins over position, because the list under
/// the cursor refreshes: a row can reorder or lose an item between the frame
/// the user looked at and the moment they press. Only when there is no identity
/// yet does the index get to decide.
HubActivation resolveHubActivation({
  required List<MediaItem> items,
  required bool hasMore,
  required int focusedIndex,
  required HubFocusTarget target,
}) {
  if (target is HubFocusViewAll) {
    return hasMore
        ? const HubActivation(strategy: HubActivationStrategy.viewAll)
        : const HubActivation(strategy: HubActivationStrategy.none);
  }

  if (target is HubFocusItem) {
    final index = items.indexWhere((item) => hubItemIdentity(item) == target.identity);
    if (index >= 0) {
      return HubActivation(strategy: HubActivationStrategy.identity, item: items[index], index: index);
    }
    // The item the user was looking at is gone. Opening whatever slid into its
    // slot is the bug this type exists to prevent.
    return const HubActivation(strategy: HubActivationStrategy.staleDropped);
  }

  // HubFocusNone: nothing deliberate has been chosen, so the cursor position is
  // the best information there is.
  if (focusedIndex == items.length && hasMore) {
    return const HubActivation(strategy: HubActivationStrategy.viewAll);
  }
  if (focusedIndex < 0 || focusedIndex >= items.length) {
    return const HubActivation(strategy: HubActivationStrategy.none);
  }
  return HubActivation(strategy: HubActivationStrategy.initialIndex, item: items[focusedIndex], index: focusedIndex);
}
