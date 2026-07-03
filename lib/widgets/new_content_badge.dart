import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_kind.dart';
import '../theme/mono_theme.dart' show kBrandGradient;

/// How recently an item must have been added to still count as "new".
const Duration _newWindow = Duration(days: 14);

/// Pure classifier for the corner "new content" badge. Returns the label to
/// show, or null when the item warrants no badge. Kept free of BuildContext so
/// it can be unit-tested and reused by cards, hero, and rows.
///
/// - `NEW EPISODE` — a series with recently-added, not-yet-watched episodes.
/// - `NEW`         — a recently-added movie/episode the user hasn't watched.
///
/// [nowMs] is injectable for tests; defaults to wall-clock at call time.
String? newBadgeLabel(MediaItem item, {int? nowMs}) {
  final added = item.addedAt;
  if (added == null || added <= 0) return null;

  // Servers report addedAt in epoch seconds; guard against ms just in case.
  final addedMs = added > 1000000000000 ? added : added * 1000;
  final now = nowMs ?? DateTime.now().millisecondsSinceEpoch;
  if (now - addedMs > _newWindow.inMilliseconds) return null;
  if (now - addedMs < 0) return null; // clock skew: treat future as not-new

  switch (item.kind) {
    case MediaKind.show:
    case MediaKind.season:
      final leaves = item.leafCount ?? 0;
      final watched = item.viewedLeafCount ?? 0;
      return leaves > 0 && watched < leaves ? 'NEW EPISODE' : null;
    case MediaKind.movie:
    case MediaKind.episode:
      return (item.viewCount ?? 0) == 0 ? 'NEW' : null;
    default:
      return null;
  }
}

/// Small pill rendered in a poster corner when [newBadgeLabel] is non-null.
class NewContentBadge extends StatelessWidget {
  final MediaItem item;
  const NewContentBadge({super.key, required this.item});

  @override
  Widget build(BuildContext context) {
    final label = newBadgeLabel(item);
    if (label == null) return const SizedBox.shrink();
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        gradient: kBrandGradient,
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 9,
          fontWeight: FontWeight.w800,
          letterSpacing: 0.4,
        ),
      ),
    );
  }
}
