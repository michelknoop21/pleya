/// Manages focus memory for hub navigation.
///
/// Tracks two things:
/// 1. Per-hub memory: Each hub remembers which item was last focused
/// 2. Global column hint: When entering a hub that hasn't been visited,
///    we use the column position from the last focused hub as a hint
class HubFocusMemory {
  static final Map<String, int> _perHubMemory = {};

  /// Identity of the remembered item, for hubs whose contents reorder.
  ///
  /// A position alone is not a place: Continue Watching moves the title you
  /// just finished to the front, so restoring index N drops the cursor on
  /// whatever slid into that slot. Callers that know the item pass its key and
  /// get the position back by identity; the index stays as the fallback for
  /// hubs that have no stable key, and for when the item is simply gone.
  static final Map<String, String> _perHubItemKey = {};

  static int _lastColumnHint = 0;

  /// Records the focused position, and — when [itemKey] is given — which item
  /// occupied it. Passing no key clears any previous identity rather than
  /// leaving a stale one attached to a new position.
  static void setForHub(String hubKey, int index, {String? itemKey}) {
    _perHubMemory[hubKey] = index;
    if (itemKey == null) {
      _perHubItemKey.remove(hubKey);
    } else {
      _perHubItemKey[hubKey] = itemKey;
    }
    _lastColumnHint = index;
  }

  /// Where the remembered item sits in [itemKeys] now, or null when this hub
  /// has no identity memory or the item has dropped out of the list.
  static int? rememberedItemIndex(String hubKey, List<String> itemKeys) {
    final key = _perHubItemKey[hubKey];
    if (key == null) return null;
    final index = itemKeys.indexOf(key);
    return index < 0 ? null : index;
  }

  /// Get the remembered index for a hub, or fall back to column hint
  static int getForHub(String hubKey, int itemCount) {
    if (itemCount <= 0) return 0;

    // If this hub has memory, use it
    if (_perHubMemory.containsKey(hubKey)) {
      return _perHubMemory[hubKey]!.clamp(0, itemCount - 1);
    }

    // Otherwise use the last column hint (clamped to this hub's item count)
    return _lastColumnHint.clamp(0, itemCount - 1);
  }

  /// Get only this hub's remembered index, without falling back to the global column hint.
  static int getForHubOnly(String hubKey, int itemCount, {int fallback = 0}) {
    if (itemCount <= 0) return 0;
    final remembered = _perHubMemory[hubKey];
    return (remembered ?? fallback).clamp(0, itemCount - 1);
  }

  /// Clear all memory (e.g., when leaving a screen)
  static void clear() {
    _perHubMemory.clear();
    _perHubItemKey.clear();
    _lastColumnHint = 0;
  }
}
