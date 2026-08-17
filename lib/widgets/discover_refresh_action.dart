import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';

import '../i18n/strings.g.dart';
import '../providers/discover_provider.dart';
import 'app_icon.dart';

/// Refresh glyph for the Discover header, swapped for a spinner while
/// [DiscoverProvider.isRefreshing].
///
/// A refresh with content already on screen keeps the rows in place instead of
/// flipping to a skeleton, and a server that returns the same data changes no
/// pixel — so this button is the only thing that can report the pass at all.
///
/// It subscribes to the provider itself rather than letting the header rebuild
/// the action list: [FocusableActionBar] rebuilds its focus nodes when the list
/// changes shape, and the bar is shared with tvOS, where dropping focus during
/// a press is very visible.
class DiscoverRefreshAction extends StatelessWidget {
  const DiscoverRefreshAction({super.key, required this.color, required this.onPressed});

  final Color color;

  /// Also wired as the action's D-pad handler, so it has to stay a no-op while
  /// a pass is running — this widget's rebuild can't reach that callback.
  final VoidCallback onPressed;

  /// Matches the glyph it replaces so the action bar doesn't reflow mid-refresh.
  static const double _glyphSize = 24;

  @override
  Widget build(BuildContext context) {
    final isRefreshing = context.select<DiscoverProvider, bool>((discover) => discover.isRefreshing);

    return IconButton(
      tooltip: t.common.refresh,
      onPressed: isRefreshing ? null : onPressed,
      icon: isRefreshing
          ? SizedBox.square(
              dimension: _glyphSize,
              child: Padding(
                padding: const EdgeInsets.all(2),
                child: CircularProgressIndicator(strokeWidth: 2, color: color),
              ),
            )
          : AppIcon(Symbols.refresh_rounded, size: _glyphSize, color: color),
    );
  }
}
