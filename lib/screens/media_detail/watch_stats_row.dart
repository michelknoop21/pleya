import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/media_watch_stats.dart';
import '../../utils/formatters.dart';
import '../../widgets/app_icon.dart';

/// One quiet line of server statistics under the watchers row: how often a
/// title was played, by how many people, and how much time went into it.
///
/// Render only when [stats] has something. There is no empty state and no
/// spinner: this arrives after the page does, and a title nobody played simply
/// has no line.
class WatchStatsRow extends StatelessWidget {
  final MediaWatchStats stats;
  final TextStyle? textStyle;

  const WatchStatsRow({super.key, required this.stats, this.textStyle});

  @override
  Widget build(BuildContext context) {
    if (stats.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final style =
        textStyle ?? theme.textTheme.bodySmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.7));

    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        AppIcon(Symbols.bar_chart_rounded, fill: 1, size: 16, color: style?.color),
        const SizedBox(width: 8),
        Expanded(
          child: Text(parts(stats).join(' · '), style: style, maxLines: 2, overflow: TextOverflow.ellipsis),
        ),
      ],
    );
  }

  /// The sentence fragments, in order. Pure so the wording stays testable
  /// without pumping a widget.
  static List<String> parts(MediaWatchStats stats) {
    return [
      t.discover.statsPlays(count: stats.totalPlays),
      if (stats.userCount != null && stats.userCount! > 0) t.discover.statsViewers(count: stats.userCount!),
      // Below a minute prettyDuration renders nothing useful, so a title that
      // was only ever started gets a play count and no time.
      if (stats.totalTime.inMinutes > 0)
        t.discover.statsWatchTime(duration: formatDurationTextual(stats.totalTime.inMilliseconds)),
      if (stats.playsLast30Days != null && stats.playsLast30Days! > 0)
        t.discover.statsRecent(count: stats.playsLast30Days!),
    ];
  }
}
