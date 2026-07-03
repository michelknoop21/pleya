import '../../media/media_hub.dart';
import '../../media/media_item.dart';

/// Stable identity for cross-row de-duplication. Uses the item's global key
/// (server + rating key), which collapses the same title appearing in several
/// hubs on the same server.
String hubItemDedupKey(MediaItem item) => item.globalKey;

/// Limits how often the same item may appear across the home feed. Netflix-style
/// feeds avoid showing the same title in five different rows; this keeps each
/// item to [maxAppearances] and drops any hub left with fewer than [minHubItems]
/// unique entries. First occurrences win, so higher-priority rows keep their
/// items. Pure — no I/O — so it is cheap to run on every home load.
///
/// [alreadyShownKeys] pre-seeds items surfaced elsewhere (e.g. the Continue
/// Watching row) so they aren't repeated wholesale in the hubs below.
List<MediaHub> dedupeAcrossHubs(
  List<MediaHub> hubs, {
  Set<String> alreadyShownKeys = const {},
  int maxAppearances = 2,
  int minHubItems = 3,
}) {
  final counts = <String, int>{for (final k in alreadyShownKeys) k: 1};
  final result = <MediaHub>[];

  for (final hub in hubs) {
    final kept = <MediaItem>[];
    for (final item in hub.items) {
      final key = hubItemDedupKey(item);
      final seen = counts[key] ?? 0;
      if (seen >= maxAppearances) continue;
      counts[key] = seen + 1;
      kept.add(item);
    }

    if (kept.length == hub.items.length) {
      result.add(hub); // nothing removed — keep original instance
    } else if (kept.length >= minHubItems) {
      result.add(hub.copyWith(items: kept));
    }
    // else: too few unique items remain — drop the hub entirely
  }

  return result;
}
