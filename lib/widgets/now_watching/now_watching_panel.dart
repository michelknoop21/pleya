import 'package:flutter/material.dart';

import '../../focus/focus_theme.dart';
import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/watch_session.dart';
import '../../theme/mono_theme.dart';
import '../../utils/formatters.dart';
import '../clickable_cursor.dart';
import 'now_watching_row.dart';

/// The list behind the presence control: a summary line and one row per stream.
///
/// Shared by the desktop overlay, the mobile sheet and the TV screen, which is
/// why it is a plain column rather than a scaffold or a popover. It never draws
/// an empty state: with nothing playing there is nothing to open, and the
/// surfaces that host this are gone before it could be seen.
class NowWatchingPanel extends StatelessWidget {
  const NowWatchingPanel({super.key, required this.now, this.large = false, this.onOpenSession});

  final NowWatching now;

  /// Ten-foot sizing, used on TV.
  final bool large;

  /// Opens the title a stream is playing. Rows without a rating key stay inert.
  final void Function(WatchSession session)? onOpenSession;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: .min,
      crossAxisAlignment: .stretch,
      children: [
        _Header(now: now, large: large),
        Divider(height: 1, color: theme.dividerColor),
        for (final session in now.sessions)
          _Tappable(
            key: ValueKey(session.id),
            onTap: session.ratingKey == null || onOpenSession == null ? null : () => onOpenSession!(session),
            child: NowWatchingRow(session: session, large: large),
          ),
      ],
    );
  }
}

/// Title, live dot and the totals. Amber whenever something is transcoding,
/// which is the one state an admin can act on without reading a row.
class _Header extends StatelessWidget {
  const _Header({required this.now, required this.large});

  final NowWatching now;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Padding(
      padding: EdgeInsets.fromLTRB(large ? 20 : 14, large ? 16 : 12, large ? 20 : 14, large ? 14 : 11),
      child: Row(
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(shape: BoxShape.circle, color: now.hasTranscode ? kAccentAlt : kSuccess),
          ),
          const SizedBox(width: 9),
          Text(
            t.nowWatching.title,
            style: (large ? theme.textTheme.titleMedium : theme.textTheme.titleSmall)?.copyWith(fontWeight: .bold),
          ),
          const Spacer(),
          Flexible(
            child: Text(
              summaryLine(now),
              textAlign: .right,
              style: theme.textTheme.labelSmall?.copyWith(color: theme.colorScheme.onSurfaceVariant),
              maxLines: 1,
              overflow: .ellipsis,
            ),
          ),
        ],
      ),
    );
  }

  /// "3 streams · 1 transcoding · 24.6 Mbps". The bandwidth is the server's
  /// total, so it stays honest even when the admin's own stream is filtered out
  /// of the rows above it.
  static String summaryLine(NowWatching now) => [
    now.sessions.length == 1 ? t.nowWatching.oneStream : t.nowWatching.streams(count: now.sessions.length),
    if (now.hasTranscode) t.nowWatching.transcoding(count: now.transcodeCount),
    if (now.totalBandwidthKbps > 0) ByteFormatter.formatBitrate(now.totalBandwidthKbps),
  ].join(' · ');
}

/// A row that reacts to a pointer and to a remote, with the app's usual focus
/// border. Inert when there is nothing to open, rather than a dead click
/// target.
class _Tappable extends StatefulWidget {
  const _Tappable({super.key, required this.child, this.onTap});

  final Widget child;
  final VoidCallback? onTap;

  @override
  State<_Tappable> createState() => _TappableState();
}

class _TappableState extends State<_Tappable> {
  final _focusNode = FocusNode();
  bool _focused = false;

  @override
  void dispose() {
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (widget.onTap == null) return widget.child;

    return Focus(
      focusNode: _focusNode,
      onFocusChange: (value) => setState(() => _focused = value),
      onKeyEvent: (_, event) => handleOneShotSelect(event, widget.onTap!),
      child: ClickableCursor(
        child: GestureDetector(
          onTap: widget.onTap,
          child: DecoratedBox(
            decoration: FocusTheme.focusDecoration(context, isFocused: _focused, borderRadius: 8),
            child: widget.child,
          ),
        ),
      ),
    );
  }
}
