import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../i18n/strings.g.dart';
import '../../media/watch_session.dart';
import '../../services/download_artwork_helpers.dart';
import '../../services/image_cache_service.dart';
import '../../theme/mono_theme.dart';
import '../../utils/formatters.dart';
import '../watcher_avatar.dart';

/// One active stream: what is playing, who is watching, and what the server is
/// doing to deliver it.
///
/// Rendered in the panel behind the app-bar control and on the TV screen, so
/// the same row has a compact and a roomy size rather than two implementations.
class NowWatchingRow extends StatelessWidget {
  const NowWatchingRow({super.key, required this.session, this.large = false});

  final WatchSession session;

  /// Ten-foot sizing for the TV screen.
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final stillWidth = large ? 112.0 : 76.0;

    return Padding(
      padding: EdgeInsets.symmetric(horizontal: large ? 20 : 14, vertical: large ? 12 : 10),
      child: Row(
        crossAxisAlignment: .center,
        children: [
          _Still(session: session, width: stillWidth),
          SizedBox(width: large ? 16 : 11),
          Expanded(
            child: _Details(session: session, large: large),
          ),
          SizedBox(width: large ? 16 : 10),
          _Status(session: session, large: large, theme: theme),
        ],
      ),
    );
  }
}

/// The frame from the title, with playback progress along the bottom edge.
class _Still extends StatelessWidget {
  const _Still({required this.session, required this.width});

  final WatchSession session;
  final double width;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final url = session.artUrl;

    return ClipRRect(
      borderRadius: BorderRadius.circular(7),
      child: SizedBox(
        width: width,
        height: width * 9 / 16,
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (url != null && url.isNotEmpty)
              CachedNetworkImage(
                imageUrl: url,
                // Hash the token-free URL, so a rotating Plex token never lands
                // in a persistent cache key.
                cacheKey: artworkStorageKey(url),
                cacheManager: PlexImageCacheManager.instance,
                fit: BoxFit.cover,
                placeholder: (_, _) => _placeholder(theme),
                errorBuilder: (_, _, _) => _placeholder(theme),
              )
            else
              _placeholder(theme),
            Align(
              alignment: .bottomCenter,
              child: LinearProgressIndicator(
                value: session.progressPercent / 100,
                minHeight: 3,
                backgroundColor: Colors.white24,
                valueColor: AlwaysStoppedAnimation(kAccent),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _placeholder(ThemeData theme) => ColoredBox(
    color: theme.colorScheme.surfaceContainerHighest,
    child: Icon(Symbols.movie_rounded, size: 18, color: theme.colorScheme.onSurfaceVariant),
  );
}

class _Details extends StatelessWidget {
  const _Details({required this.session, required this.large});

  final WatchSession session;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = theme.colorScheme.onSurfaceVariant;
    final subtitle = session.subtitle;

    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        Text.rich(
          TextSpan(
            text: session.title,
            children: [
              if (subtitle != null)
                TextSpan(
                  text: '  $subtitle',
                  style: (large ? theme.textTheme.bodyMedium : theme.textTheme.bodySmall)?.copyWith(color: muted),
                ),
            ],
          ),
          style: (large ? theme.textTheme.titleSmall : theme.textTheme.bodyMedium)?.copyWith(fontWeight: .w600),
          maxLines: 1,
          overflow: .ellipsis,
        ),
        const SizedBox(height: 3),
        Row(
          children: [
            WatcherAvatar(displayName: session.userName, thumbUrl: session.userThumb, size: large ? 22 : 18),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                [session.userName, ?session.playerLabel, ?_network(session)].join(' · '),
                style: theme.textTheme.bodySmall?.copyWith(color: muted),
                maxLines: 1,
                overflow: .ellipsis,
              ),
            ),
          ],
        ),
        if (_technical(session) case final line?) ...[
          const SizedBox(height: 3),
          Text(
            line,
            style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurface.withValues(alpha: 0.45)),
            maxLines: 1,
            overflow: .ellipsis,
          ),
        ],
      ],
    );
  }

  static String? _network(WatchSession s) => switch (s.isLan) {
    true => t.nowWatching.onLan,
    false => t.nowWatching.onWan,
    null => null,
  };

  /// What the server is doing and what it costs, in one line. Empty for a
  /// direct play with no reported bandwidth, where there is nothing to say.
  static String? _technical(WatchSession s) {
    final parts = [
      ?s.transcodeSummary,
      if (s.isTranscoding && s.hardwareTranscode) t.nowWatching.hardware,
      if (s.bandwidthKbps > 0) ByteFormatter.formatBitrate(s.bandwidthKbps),
    ];
    return parts.isEmpty ? null : parts.join(' · ');
  }
}

class _Status extends StatelessWidget {
  const _Status({required this.session, required this.large, required this.theme});

  final WatchSession session;
  final bool large;
  final ThemeData theme;

  @override
  Widget build(BuildContext context) {
    final remaining = session.remainingSeconds;

    return Column(
      crossAxisAlignment: .end,
      mainAxisSize: .min,
      children: [
        _pill(),
        const SizedBox(height: 5),
        Text(
          remaining == null || session.isPaused
              ? '${session.progressPercent}%'
              : t.nowWatching.remaining(time: formatDurationTextual(remaining * 1000)),
          style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
        ),
      ],
    );
  }

  Widget _pill() {
    final (label, color) = switch (session) {
      final s when s.isPaused => (t.nowWatching.paused, theme.colorScheme.onSurfaceVariant),
      final s when s.delivery == StreamDelivery.transcode => (t.nowWatching.transcode, kAccentAlt),
      final s when s.delivery == StreamDelivery.directStream => (t.nowWatching.directStream, kSuccess),
      _ => (t.nowWatching.directPlay, kSuccess),
    };

    return Container(
      padding: EdgeInsets.symmetric(horizontal: large ? 9 : 7, vertical: 2),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(5),
        border: Border.all(color: color.withValues(alpha: 0.45)),
      ),
      child: Text(
        label,
        style: (large ? theme.textTheme.labelMedium : theme.textTheme.labelSmall)?.copyWith(
          color: color,
          fontWeight: .w700,
        ),
      ),
    );
  }
}
