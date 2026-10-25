/// The pinned bar of a settings page with a Studio header (A-24) and the
/// scroll tracking that hands the title over from the header to the bar.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../theme/mono_tokens.dart';
import '../desktop_app_bar.dart';

/// Scroll offset past which the large title sits under the pinned bar and the
/// bar's compact title takes over.
const double kSettingsStudioCollapseOffset = 56;

/// The top colour of the Studio header's warm wash: brand red, faint, over the
/// page. The pinned bar carries it while the header is in view, so the wash
/// runs on from the status bar instead of starting on a line under the bar.
Color settingsStudioWashTop(MonoTokens tokens) =>
    Color.alphaBlend(tokens.accent.withValues(alpha: tokens.isLight ? 0.08 : 0.16), tokens.bg);

/// The pinned bar above a Studio header. While the header is in view it has no
/// title and the wash colour; once the header has gone under it, the page
/// colour and the compact title. Back button, actions and pinning are the
/// plain [CustomAppBar]'s.
class SettingsStudioBar extends StatelessWidget {
  const SettingsStudioBar({
    super.key,
    required this.collapsed,
    required this.title,
    this.actions,
    this.pinned = true,
    this.automaticallyImplyLeading = true,
  });

  final ValueListenable<bool> collapsed;
  final Widget title;
  final List<Widget>? actions;
  final bool pinned;
  final bool automaticallyImplyLeading;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: collapsed,
      builder: (context, isCollapsed, _) => CustomAppBar(
        title: SettingsStudioCompactTitle(collapsed: collapsed, child: title),
        backgroundColor: isCollapsed ? null : settingsStudioWashTop(tokens(context)),
        pinned: pinned,
        actions: actions,
        automaticallyImplyLeading: automaticallyImplyLeading,
      ),
    );
  }
}

/// The pinned bar's title on a page with a [SettingsStudioHeader]: absent
/// while the large title is in view, faded in once it has scrolled under the
/// bar. Absent rather than transparent, so the page has one title for screen
/// readers and for finders at rest, not two.
class SettingsStudioCompactTitle extends StatelessWidget {
  const SettingsStudioCompactTitle({super.key, required this.collapsed, required this.child});

  final ValueListenable<bool> collapsed;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: collapsed,
      builder: (context, isCollapsed, _) => AnimatedSwitcher(
        duration: reduceMotion(context, tokens(context).fast),
        child: isCollapsed
            ? KeyedSubtree(key: const ValueKey(true), child: child)
            : const SizedBox.shrink(key: ValueKey(false)),
      ),
    );
  }
}

/// Flips [collapsed] from the offset of the page's own scroll view. Returns
/// false so the notification keeps bubbling to the scroll crown and others.
bool settingsStudioTrackScroll(ValueNotifier<bool> collapsed, ScrollNotification notification) {
  if (notification.depth == 0 && notification.metrics.axis == Axis.vertical) {
    collapsed.value = notification.metrics.pixels > kSettingsStudioCollapseOffset;
  }
  return false;
}
