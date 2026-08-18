import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../i18n/strings.g.dart';
import '../../providers/now_watching_provider.dart';
import '../../theme/mono_theme.dart';
import '../../widgets/watcher_avatar.dart';

/// "Robin is watching this now", above the "Watched by" row.
///
/// The second place the now-watching data appears, and the only one that costs
/// no navigation: on the page for a title someone is streaming at this moment,
/// one line says so. It reads from the poll Home already runs, so opening a
/// detail page starts nothing.
///
/// Silent by default. No session for this title, no Tautulli, no server
/// ownership: no line, no placeholder, no reserved height.
class NowWatchingLine extends StatelessWidget {
  const NowWatchingLine({super.key, required this.ratingKey, this.textStyle});

  /// The Plex rating key of the item on screen. An episode matches on its own
  /// key, so a series page stays quiet while someone watches one episode of it:
  /// that is the episode's news, not the show's.
  final String ratingKey;

  final TextStyle? textStyle;

  @override
  Widget build(BuildContext context) {
    final sessions = context.watch<NowWatchingProvider?>()?.sessions ?? const [];
    final session = sessions.where((s) => s.ratingKey == ratingKey).firstOrNull;
    if (session == null) return const SizedBox.shrink();

    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 7,
          height: 7,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: session.isPaused ? theme.colorScheme.onSurfaceVariant : kSuccess,
          ),
        ),
        const SizedBox(width: 10),
        WatcherAvatar(displayName: session.userName, thumbUrl: session.userThumb, size: 22),
        const SizedBox(width: 8),
        Flexible(
          child: Text(
            '${t.nowWatching.watchingNow(name: session.userName)} · ${session.progressPercent}%',
            style: textStyle ?? theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ),
      ],
    );
  }
}
