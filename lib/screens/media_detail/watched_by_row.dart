import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/item_watcher.dart';
import '../../widgets/watcher_avatar.dart';

/// Plex-style "Watched by …" row: an overlapping avatar cluster followed by a
/// names sentence (the active user shown as "You"). Render only when
/// [watchers] is non-empty.
///
/// Which watcher is the signed-in user is decided upstream, in
/// [ItemWatchersService]: Tautulli and the Plex Media Server number the same
/// person differently, so only the code that knows which source produced the
/// list can answer that.
class WatchedByRow extends StatelessWidget {
  final List<ItemWatcher> watchers;

  /// What the list actually supports claiming. A series aggregate cannot say
  /// people finished it, so the sentence changes with this rather than
  /// overstating.
  final ItemWatchersScope scope;

  final TextStyle? textStyle;
  final double avatarSize;

  /// How far an avatar lies over the one before it, 35 percent when left out.
  final double? avatarOverlap;

  /// Between the avatars and the sentence.
  final double textGap;

  /// The ring that keeps overlapping avatars apart, on every side.
  final double ringWidth;

  final int maxLines;

  const WatchedByRow({
    super.key,
    required this.watchers,
    this.scope = ItemWatchersScope.watched,
    this.textStyle,
    this.avatarSize = 30,
    this.avatarOverlap,
    this.textGap = 12,
    this.ringWidth = 2,
    this.maxLines = 2,
  });

  static const _maxAvatars = 4;

  @override
  Widget build(BuildContext context) {
    if (watchers.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);

    return Row(
      crossAxisAlignment: .center,
      children: [
        _buildAvatarCluster(theme),
        SizedBox(width: textGap),
        Expanded(
          child: Text(
            switch (scope) {
              ItemWatchersScope.watched => t.discover.watchedBy(names: _namesSentence()),
              ItemWatchersScope.watchingSeries => t.discover.watchingSeriesBy(names: _namesSentence()),
              ItemWatchersScope.activity => t.discover.activityBy(
                names: namesSentence(watchers, you: t.discover.activityByYou),
              ),
            },
            style: textStyle ?? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: maxLines,
            overflow: .ellipsis,
          ),
        ),
      ],
    );
  }

  String _namesSentence() => namesSentence(watchers);

  /// The names part of the sentence, shared with the iPhone activity card.
  /// [you] is the viewer's own name where the sentence around it needs another
  /// form than "You": "Activity by you", "Activiteit van jou".
  static String namesSentence(List<ItemWatcher> watchers, {String? you}) {
    // Self first, so "You" is never buried in the "and N others" overflow;
    // everyone else keeps recency order.
    final ordered = [...watchers.where((w) => w.isSelf), ...watchers.where((w) => !w.isSelf)];
    return joinNames(
      [for (final w in ordered) w.isSelf ? you ?? t.discover.watchedByYou : w.displayName],
      and: t.discover.watchedByAnd,
      others: (n) => t.discover.watchedByOthers(count: n),
    );
  }

  /// "You", "You and Bob", "You, Bob and Carol", "You, Bob and 3 others".
  /// Pure so it's unit-testable without the i18n runtime.
  static String joinNames(List<String> names, {required String and, required String Function(int) others}) {
    if (names.isEmpty) return '';
    if (names.length == 1) return names[0];
    if (names.length <= 3) {
      return '${names.sublist(0, names.length - 1).join(', ')} $and ${names.last}';
    }
    // 4+: show the first two by name, collapse the rest into "and N others".
    return '${names[0]}, ${names[1]} $and ${others(names.length - 2)}';
  }

  Widget _buildAvatarCluster(ThemeData theme) {
    final shown = watchers.take(_maxAvatars).toList();
    final overflow = watchers.length - shown.length;
    final overlap = avatarOverlap ?? avatarSize * 0.35;
    final step = avatarSize - overlap;
    final bubbleCount = overflow > 0 ? 1 : 0;
    final ring = ringWidth * 2; // _ringed adds its border on every side
    final width = avatarSize + ring + (shown.length - 1 + bubbleCount) * step;

    return SizedBox(
      width: width,
      height: avatarSize + ring,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: _ringed(
                theme,
                WatcherAvatar(
                  displayName: shown[i].displayName,
                  thumbUrl: shown[i].thumbUrl,
                  initials: shown[i].initials,
                  size: avatarSize,
                ),
              ),
            ),
          if (overflow > 0)
            Positioned(
              left: shown.length * step,
              child: _ringed(theme, _OverflowBubble(count: overflow, size: avatarSize)),
            ),
        ],
      ),
    );
  }

  // Thin surface ring so overlapping avatars stay visually separated.
  Widget _ringed(ThemeData theme, Widget child) => Container(
    decoration: BoxDecoration(
      shape: BoxShape.circle,
      border: Border.all(color: theme.colorScheme.surface, width: ringWidth),
    ),
    child: child,
  );
}

class _OverflowBubble extends StatelessWidget {
  final int count;
  final double size;

  const _OverflowBubble({required this.count, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: size,
      height: size,
      alignment: .center,
      decoration: BoxDecoration(shape: BoxShape.circle, color: theme.colorScheme.surfaceContainerHighest),
      child: Text(
        '+$count',
        style: TextStyle(
          color: theme.colorScheme.onSurfaceVariant,
          fontSize: size * 0.36,
          fontWeight: .w600,
          height: 1.0,
        ),
      ),
    );
  }
}
