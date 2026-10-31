import 'package:flutter/material.dart';

import '../../../i18n/strings.g.dart';
import '../../../media/item_watcher.dart';
import '../../../widgets/watcher_avatar.dart';
import '../watched_by_row.dart';
import 'detail_dark_style.dart';

/// Who watched this, who is watching it now and how often it was played, in
/// one dark pill under the source line (`.act` in D-01/D-03, DEC-140; Plex
/// look since variant B). iPhone only;
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
    this.scope,
    this.ownProgressLabel,
  });

  final List<ItemWatcher> watchers;
  final String? nowWatchingName;
  final int? playCount;
  final int? viewerCount;
  final bool isSeries;

  /// What the list supports claiming, when that is more than [isSeries] says.
  final ItemWatchersScope? scope;

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
    final onSurface = Theme.of(context).colorScheme.onSurface;

    final muted = onSurface.withValues(alpha: 0.70);
    final progress = isSeries ? ownProgressLabel : null;
    final plays = playCount;
    final viewers = viewerCount;
    final details = [
      ?progress,
      if (plays != null && plays > 0) t.discover.activityPlays(count: plays),
      if (viewers != null && viewers > 0) t.discover.activityViewers(count: viewers),
    ];

    return Container(
      margin: const EdgeInsets.only(top: 18),
      padding: const EdgeInsets.fromLTRB(8, 8, 18, 8),
      decoration: BoxDecoration(
        color: kDetailPillColor,
        border: Border.all(color: kDetailPillEdge),
        borderRadius: BorderRadius.circular(32),
      ),
      child: Row(
        children: [
          if (watchers.isNotEmpty) ...[_avatars(), const SizedBox(width: 14)],
          Expanded(
            child: Column(
              crossAxisAlignment: .start,
              children: [
                if (watchers.isNotEmpty)
                  Text(
                    switch ((scope, isSeries)) {
                      (ItemWatchersScope.activity, _) => t.discover.activityBy(
                        names: WatchedByRow.namesSentence(watchers, you: t.discover.activityByYou),
                      ),
                      (_, true) => t.discover.watchingSeriesBy(names: WatchedByRow.namesSentence(watchers)),
                      (_, false) => t.discover.watchedBy(names: WatchedByRow.namesSentence(watchers)),
                    },
                    style: TextStyle(color: onSurface, fontSize: 15, fontWeight: .w700),
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
                            style: TextStyle(color: onSurface, fontWeight: .w700),
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
                child: WatcherAvatar(
                  displayName: shown[i].displayName,
                  thumbUrl: shown[i].thumbUrl,
                  initials: shown[i].initials,
                  size: _avatarSize,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
