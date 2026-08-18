import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../focus/key_event_utils.dart';
import '../../i18n/strings.g.dart';
import '../../media/watch_session.dart';
import '../../providers/now_watching_provider.dart';
import '../../screens/now_watching_screen.dart';
import '../../theme/mono_theme.dart';
import '../../utils/media_navigation_helper.dart';
import '../../utils/platform_detector.dart';
import '../clickable_cursor.dart';
import '../watcher_avatar.dart';
import 'now_watching_panel.dart';

/// Presence in the app bar: a small avatar cluster with a live dot, shown only
/// while someone else is streaming.
///
/// It exists rather than reserves space. Nothing playing means no button, so
/// the toolbar and the page under it never shift when a stream starts or stops
/// — which is exactly why this is not a row on the home screen.
///
/// The dot turns amber when the server is transcoding, the one state an admin
/// can act on without opening anything.
///
/// Tapping opens [NowWatchingPanel]: an overlay under the button on desktop,
/// a sheet on a phone. Opening is what raises the polling tempo; the ambient
/// once-a-minute question belongs to the surface that hosts this control.
///
/// Not used on TV. A pointer overlay under a toolbar button cannot be reached
/// with a remote, so there the sidebar carries a now-watching entry that opens
/// [NowWatchingScreen] as a page.
class NowWatchingButton extends StatefulWidget {
  const NowWatchingButton({super.key});

  @override
  State<NowWatchingButton> createState() => NowWatchingButtonState();
}

class NowWatchingButtonState extends State<NowWatchingButton> {
  final _buttonKey = GlobalKey();
  OverlayEntry? _overlay;
  NowWatchingProvider? _provider;

  static const _maxAvatars = 2;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _provider = context.read<NowWatchingProvider?>();
  }

  @override
  void deactivate() {
    _closePanel();
    super.deactivate();
  }

  @override
  void dispose() {
    _closePanel();
    super.dispose();
  }

  void _closePanel() {
    if (_overlay == null) return;
    _overlay?.remove();
    _overlay = null;
    _provider?.releaseDetail();
  }

  /// Opens or closes the list. Public because the app bar's focus row drives
  /// its buttons through the action, not through the widget, exactly as
  /// [ServerActivitiesButton] is driven.
  void togglePanel() {
    if (_overlay != null) {
      _closePanel();
      return;
    }
    PlatformDetector.isMobile(context) ? _openSheet() : _openOverlay();
  }

  Future<void> _openSheet() async {
    final provider = _provider;
    if (provider == null) return;
    // Claimed here and released in the finally, so the faster tempo can never
    // outlive the thing that asked for it.
    provider.watchDetail();
    try {
      await showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => SafeArea(
          child: SingleChildScrollView(
            child: ListenableBuilder(
              listenable: provider,
              builder: (context, _) => NowWatchingPanel(now: provider.now, onOpenSession: _openSession),
            ),
          ),
        ),
      );
    } finally {
      provider.releaseDetail();
    }
  }

  void _openOverlay() {
    final box = _buttonKey.currentContext?.findRenderObject() as RenderBox?;
    final provider = _provider;
    if (box == null || provider == null) return;

    final offset = box.localToGlobal(Offset.zero);
    final screen = MediaQuery.sizeOf(context);
    final right = screen.width - (offset.dx + box.size.width);
    final top = offset.dy + box.size.height + 4;

    _overlay = OverlayEntry(
      builder: (_) => Stack(
        children: [
          Positioned.fill(
            child: GestureDetector(onTap: _closePanel, behavior: HitTestBehavior.opaque),
          ),
          Positioned(
            right: right,
            top: top,
            child: Focus(
              autofocus: true,
              onKeyEvent: (_, event) => handleBackKeyAction(event, _closePanel),
              child: Material(
                elevation: 8,
                borderRadius: BorderRadius.circular(12),
                clipBehavior: Clip.antiAlias,
                color: Theme.of(context).colorScheme.surface,
                child: SizedBox(
                  width: 380,
                  child: ListenableBuilder(
                    listenable: provider,
                    builder: (context, _) => NowWatchingPanel(now: provider.now, onOpenSession: _openSession),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    Overlay.of(context).insert(_overlay!);
    // Only now, with the overlay really on screen, is the faster tempo claimed:
    // an early return above must not leave a subscription nobody can release.
    provider.watchDetail();
  }

  /// Opens the title, not the session. A session is a snapshot of someone
  /// else's evening; the detail page is where there is something to do.
  Future<void> _openSession(WatchSession session) async {
    final ratingKey = session.ratingKey;
    final provider = _provider;
    if (ratingKey == null || provider == null) return;
    _closePanel();

    final item = await provider.resolveItem(ratingKey);
    if (item == null || !mounted) return;
    await navigateToMediaItem(context, item);
  }

  @override
  Widget build(BuildContext context) {
    final now = context.watch<NowWatchingProvider?>()?.now;
    if (now == null || !now.hasOthers) {
      // The button stops drawing when the last stream ends, but the overlay is
      // in the Overlay, not in this subtree, so it survives that on its own: an
      // empty panel would hang over the page until the user clicked next to it.
      // Closing is deferred, because a build cannot remove an OverlayEntry.
      if (_overlay != null) {
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _closePanel();
        });
      }
      return const SizedBox.shrink();
    }

    final theme = Theme.of(context);
    final shown = now.sessions.take(_maxAvatars).toList();

    return Semantics(
      button: true,
      label: t.nowWatching.tooltip,
      child: Tooltip(
        message: t.nowWatching.tooltip,
        child: ClickableCursor(
          child: GestureDetector(
            key: _buttonKey,
            onTap: togglePanel,
            child: Container(
              margin: const EdgeInsets.symmetric(horizontal: 4),
              padding: const EdgeInsets.fromLTRB(7, 4, 9, 4),
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(999),
                color: theme.colorScheme.onSurface.withValues(alpha: 0.07),
                border: Border.all(color: theme.colorScheme.onSurface.withValues(alpha: 0.12)),
              ),
              child: Row(
                mainAxisSize: .min,
                children: [
                  Container(
                    width: 7,
                    height: 7,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: now.hasTranscode ? kAccentAlt : kSuccess),
                  ),
                  const SizedBox(width: 7),
                  _AvatarCluster(sessions: shown),
                  const SizedBox(width: 6),
                  Text('${now.sessions.length}', style: theme.textTheme.labelMedium?.copyWith(fontWeight: .w700)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The faces, overlapping, the same way the "Watched by" row draws them. Two at
/// most: this is a glance, and the count next to it carries the rest.
class _AvatarCluster extends StatelessWidget {
  const _AvatarCluster({required this.sessions});

  final List<WatchSession> sessions;

  static const _size = 22.0;
  static const _step = _size * 0.68;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SizedBox(
      width: _size + (sessions.length - 1) * _step + 4,
      height: _size + 4,
      child: Stack(
        children: [
          for (var i = 0; i < sessions.length; i++)
            Positioned(
              left: i * _step,
              child: Container(
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  border: Border.all(color: theme.colorScheme.surface, width: 2),
                ),
                child: WatcherAvatar(displayName: sessions[i].userName, thumbUrl: sessions[i].userThumb, size: _size),
              ),
            ),
        ],
      ),
    );
  }
}
