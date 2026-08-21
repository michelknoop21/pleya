import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../utils/platform_detector.dart';
import 'notice_card.dart';
import 'notice_controller.dart';

/// Global overlay that renders [noticeController]'s visible notices. Lives
/// as a `Stack` layer inside `MaterialApp.builder` (see `main.dart`'s
/// `_AppShell`), not as a hand-inserted root `OverlayEntry` — the
/// CLAUDE.md gotcha is about an `OverlayEntry` pushed onto the *root*
/// overlay outliving `ProfileSessionScreen`'s nested `Navigator`. A `Stack`
/// child at the `MaterialApp.builder` level has no such lifecycle mismatch:
/// it remounts with the rest of the app shell, never independently. Its own
/// `BuildContext` is still never used for navigation — see [NoticeAction].
class NoticeHost extends StatelessWidget {
  const NoticeHost({super.key});

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: noticeController,
      builder: (context, _) {
        final entries = noticeController.visible;
        if (entries.isEmpty) return const SizedBox.shrink();
        if (PlatformDetector.isTV()) return _TvLayer(entries: entries);
        if (PlatformDetector.isDesktopOS()) return _DesktopLayer(entries: entries);
        return _MobileLayer(entries: entries);
      },
    );
  }
}

Widget _fadeIn(BuildContext context, Widget child) {
  return TweenAnimationBuilder<double>(
    tween: Tween(begin: 0, end: 1),
    duration: reduceMotion(context, tokens(context).fast),
    curve: Curves.easeOut,
    builder: (context, value, builtChild) => Opacity(opacity: value, child: builtChild),
    child: child,
  );
}

/// Full width minus 16px margins, stacked above the mobile `NavigationBar`.
/// Swiping a card away dismisses it.
class _MobileLayer extends StatelessWidget {
  final List<NoticeEntry> entries;
  const _MobileLayer({required this.entries});

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final bottomInset = MediaQuery.paddingOf(context).bottom;
    // Approximates the Material 3 NavigationBar's default height (80) plus a
    // margin. NoticeHost sits above MainScreen at the MaterialApp.builder
    // level and has no way to read the bar's actual (label-mode-dependent)
    // height from there.
    const navBarClearance = 88.0;
    return Align(
      alignment: Alignment.bottomCenter,
      child: Padding(
        padding: EdgeInsets.only(left: 16, right: 16, bottom: bottomInset + navBarClearance),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < entries.length; i++) ...[
              if (i > 0) SizedBox(height: t.space / 2),
              _fadeIn(
                context,
                Dismissible(
                  key: ValueKey(entries[i].id),
                  direction: DismissDirection.horizontal,
                  onDismissed: (_) => noticeController.dismiss(entries[i].id),
                  child: NoticeCard(entry: entries[i], onDismiss: () => noticeController.dismiss(entries[i].id)),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Fixed 420px width, bottom-right, newest nearest the corner.
class _DesktopLayer extends StatelessWidget {
  final List<NoticeEntry> entries;
  const _DesktopLayer({required this.entries});

  static const double _width = 420;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    return Align(
      alignment: Alignment.bottomRight,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: SizedBox(
          width: _width,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < entries.length; i++) ...[
                if (i > 0) SizedBox(height: t.space / 2),
                _fadeIn(
                  context,
                  NoticeCard(entry: entries[i], onDismiss: () => noticeController.dismiss(entries[i].id)),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Top-right, inside `TvLayoutConstants.horizontalInset`, scaled by
/// `TvLayoutConstants.scaleOf`. Buttons are D-pad-focusable. Newest nearest
/// the top-right corner, so entries are rendered oldest-first from there
/// (reverse of the controller's insertion order).
class _TvLayer extends StatelessWidget {
  final List<NoticeEntry> entries;
  const _TvLayer({required this.entries});

  static const double _width = 420;
  static const double _topInset = 32;

  @override
  Widget build(BuildContext context) {
    final t = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final ordered = entries.reversed.toList(growable: false);
    return Align(
      alignment: Alignment.topRight,
      child: Padding(
        padding: EdgeInsets.fromLTRB(
          TvLayoutConstants.horizontalInset * scale,
          _topInset * scale,
          TvLayoutConstants.horizontalInset * scale,
          0,
        ),
        child: SizedBox(
          width: _width * scale,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              for (var i = 0; i < ordered.length; i++) ...[
                if (i > 0) SizedBox(height: t.space / 2 * scale),
                _fadeIn(
                  context,
                  NoticeCard(
                    entry: ordered[i],
                    onDismiss: () => noticeController.dismiss(ordered[i].id),
                    tv: true,
                    scale: scale,
                  ),
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
