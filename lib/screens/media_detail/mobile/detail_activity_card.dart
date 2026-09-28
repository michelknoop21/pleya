import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/item_watcher.dart';
import '../../../widgets/watcher_avatar.dart';
import '../watched_by_row.dart';

/// Who watched this, who is watching it now and how often it was played, in
/// one card under the source line (`.act` in D-01/D-03, DEC-140). iPhone only;
/// TV, iPad and desktop keep [WatchedByRow] and its siblings.
///
/// Takes what the detail page already loaded, so it fetches nothing and adds
/// no gate of its own: no watchers and nobody watching means no card.
class DetailActivityCard extends StatelessWidget {
  const DetailActivityCard({
    super.key,
    required this.watchers,
    required this.nowWatchingName,
    required this.playCount,
    required this.viewerCount,
    required this.isSeries,
    this.ownProgressLabel,
  });

  final List<ItemWatcher> watchers;
  final String? nowWatchingName;
  final int? playCount;
  final int? viewerCount;
  final bool isSeries;

  /// "Jij bent bij S1 A3"; only shown for a series.
  final String? ownProgressLabel;

  static const _avatarSize = 36.0;
  static const _overlap = 10.0;
  static const _maxAvatars = 3;
  static const _live = Color(0xFFE5140F);

  @override
  Widget build(BuildContext context) {
    final name = nowWatchingName;
    if (watchers.isEmpty && name == null) return const SizedBox.shrink();

    final muted = Colors.white.withValues(alpha: 0.70);
    final progress = isSeries ? ownProgressLabel : null;
    final plays = playCount;
    final viewers = viewerCount;
    final details = [
      ?progress,
      if (plays != null && plays > 0) t.discover.activityPlays(count: plays),
      if (viewers != null && viewers > 0) t.discover.activityViewers(count: viewers),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 14),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
      decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(14)),
      child: Row(
        children: [
          if (watchers.isNotEmpty) ...[_avatars(), const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                if (watchers.isNotEmpty)
                  Text(
                    isSeries
                        ? t.discover.watchingSeriesBy(names: WatchedByRow.namesSentence(watchers))
                        : t.discover.watchedBy(names: WatchedByRow.namesSentence(watchers)),
                    style: const TextStyle(color: Colors.white, fontSize: 15, fontWeight: .w700),
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
                if (name != null || details.isNotEmpty)
                  Text.rich(
                    TextSpan(
                      children: [
                        if (name != null) ...[
                          WidgetSpan(
                            alignment: .middle,
                            child: Container(
                              key: const Key('media-detail.activity.live-dot'),
                              width: 7,
                              height: 7,
                              margin: const EdgeInsets.only(right: 5),
                              decoration: const BoxDecoration(color: _live, shape: BoxShape.circle),
                            ),
                          ),
                          TextSpan(
                            text: t.nowWatching.watchingNow(name: name),
                            style: const TextStyle(color: Colors.white, fontWeight: .w700),
                          ),
                          if (details.isNotEmpty) const TextSpan(text: ' · '),
                        ],
                        TextSpan(text: details.join(' · ')),
                      ],
                    ),
                    style: TextStyle(color: muted, fontSize: 13.5),
                    maxLines: 2,
                    overflow: .ellipsis,
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _avatars() {
    // Self first, like the names sentence.
    final shown = [...watchers.where((w) => w.isSelf), ...watchers.where((w) => !w.isSelf)].take(_maxAvatars).toList();
    const ringed = _avatarSize + 4; // 2 px ring on every side
    const step = ringed - _overlap;
    return SizedBox(
      width: ringed + (shown.length - 1) * step,
      height: ringed,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: const Color(0xFF141414), width: 2),
                ),
                child: WatcherAvatar(displayName: shown[i].displayName, thumbUrl: shown[i].thumbUrl, size: _avatarSize),
              ),
            ),
        ],
      ),
    );
  }
}
