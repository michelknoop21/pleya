import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../../i18n/strings.g.dart';
import '../../media/item_watcher.dart';
import '../../services/image_cache_service.dart';
import '../../utils/initials_palette.dart';

/// Plex-style "Watched by …" row: an overlapping avatar cluster followed by a
/// names sentence (the active user shown as "You"). Render only when
/// [watchers] is non-empty.
class WatchedByRow extends StatelessWidget {
  final List<ItemWatcher> watchers;

  /// Plex `accountID` of the active/owner user, rendered as "You". Owned
  /// servers put the owner at accountID 1.
  // ponytail: owner (accountID 1) treated as self; exact per-profile id would
  // need extra plumbing that isn't worth it for the owned-server case.
  final int? selfAccountId;
  final TextStyle? textStyle;
  final double avatarSize;

  const WatchedByRow({
    super.key,
    required this.watchers,
    this.selfAccountId,
    this.textStyle,
    this.avatarSize = 30,
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
        const SizedBox(width: 12),
        Expanded(
          child: Text(
            t.discover.watchedBy(names: _namesSentence()),
            style: textStyle ?? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 2,
            overflow: .ellipsis,
          ),
        ),
      ],
    );
  }

  String _nameFor(ItemWatcher w) =>
      w.accountId == selfAccountId ? t.discover.watchedByYou : w.displayName;

  String _namesSentence() {
    // Self first, so "You" is never buried in the "and N others" overflow;
    // everyone else keeps recency order.
    final ordered = [
      ...watchers.where((w) => w.accountId == selfAccountId),
      ...watchers.where((w) => w.accountId != selfAccountId),
    ];
    return joinNames(
      ordered.map(_nameFor).toList(),
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
    final overlap = avatarSize * 0.35;
    final step = avatarSize - overlap;
    final bubbleCount = overflow > 0 ? 1 : 0;
    const ring = 4.0; // _ringed adds a 2px border on every side
    final width = avatarSize + ring + (shown.length - 1 + bubbleCount) * step;

    return SizedBox(
      width: width,
      height: avatarSize + ring,
      child: Stack(
        children: [
          for (var i = 0; i < shown.length; i++)
            Positioned(
              left: i * step,
              child: _ringed(theme, _WatcherAvatar(watcher: shown[i], size: avatarSize)),
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
          border: Border.all(color: theme.colorScheme.surface, width: 2),
        ),
        child: child,
      );
}

class _WatcherAvatar extends StatelessWidget {
  final ItemWatcher watcher;
  final double size;

  const _WatcherAvatar({required this.watcher, required this.size});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final thumb = watcher.thumbUrl;
    return ClipOval(
      child: SizedBox(
        width: size,
        height: size,
        child: thumb != null && thumb.isNotEmpty
            ? CachedNetworkImage(
                imageUrl: thumb,
                cacheManager: PlexImageCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (_, _) => _initials(theme),
                errorBuilder: (_, _, _) => _initials(theme),
              )
            : _initials(theme),
      ),
    );
  }

  Widget _initials(ThemeData theme) => Container(
        color: colorForName(watcher.displayName, theme),
        alignment: .center,
        child: Text(
          initialOf(watcher.displayName),
          style: TextStyle(color: Colors.white, fontSize: size * 0.42, fontWeight: .w600, height: 1.0),
        ),
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
