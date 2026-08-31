import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../../automation/automation_node.dart';
import '../../theme/mono_tokens.dart';
import '../../widgets/focusable_filter_chip.dart';

/// One text action on the library header line: a label, the value it currently
/// holds, and the sheet it opens.
///
/// The active tab owns the state, the focus node and the callbacks; the
/// libraries screen only draws them. That split exists because the header line
/// belongs to the screen while grouping, filters and sort belong to the browse
/// tab.
@immutable
class LibraryHeaderAction {
  final String label;
  final String? value;

  /// Draws the value in the accent colour, for a filter that is narrowing the
  /// list right now.
  final bool isActive;

  final FocusNode focusNode;
  final VoidCallback onPressed;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onBack;

  /// Stable automation ID (see lib/automation/automation_ids.dart), null on
  /// call sites Pleya Verify doesn't need to address individually.
  final String? automationId;

  const LibraryHeaderAction({
    required this.label,
    required this.focusNode,
    required this.onPressed,
    this.value,
    this.isActive = false,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onBack,
    this.automationId,
  });

  /// Compares what is on screen, not the callbacks: those are closures rebuilt
  /// on every frame of the owning tab, and comparing them would make the
  /// header republish itself in a loop.
  @override
  bool operator ==(Object other) =>
      other is LibraryHeaderAction &&
      other.label == label &&
      other.value == value &&
      other.isActive == isActive &&
      other.focusNode == focusNode;

  @override
  int get hashCode => Object.hash(label, value, isActive, focusNode);
}

/// What the active library tab contributes to the screen header.
@immutable
class LibraryHeaderInfo {
  /// Item count for the subtitle, already formatted ("128 items").
  final String? countLabel;

  final List<LibraryHeaderAction> actions;

  const LibraryHeaderInfo({this.countLabel, this.actions = const []});

  static const LibraryHeaderInfo empty = LibraryHeaderInfo();

  @override
  bool operator ==(Object other) =>
      other is LibraryHeaderInfo && other.countLabel == countLabel && listEquals(other.actions, actions);

  @override
  int get hashCode => Object.hash(countLabel, Object.hashAll(actions));
}

/// Fixed heights of the library header. The screen draws the header, and the TV
/// recommended tab has to keep its hero clear of it, so both read them here.
class LibraryHeaderMetrics {
  LibraryHeaderMetrics._();

  /// Room for the two-line page heading. The default toolbar of 56 clips the
  /// metadata line under the library name.
  static const double titleHeight = 66;

  /// Height of the tab and actions line. A [PreferredSize] cannot measure its
  /// child, so this has to move together with the paddings and the label size
  /// in [LibraryHeaderBar].
  static const double barHeight = 42;

  /// Heading plus header line.
  static const double totalHeight = titleHeight + barHeight;
}

/// The library name with its metadata line, for the app bar title slot.
class LibraryHeaderTitle extends StatelessWidget {
  final String title;
  final String? subtitle;

  const LibraryHeaderTitle({super.key, required this.title, this.subtitle});

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final theme = Theme.of(context);

    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: theme.textTheme.headlineSmall?.copyWith(
            color: tk.text,
            fontWeight: FontWeight.w600,
            letterSpacing: -0.4,
          ),
        ),
        if (subtitle != null && subtitle!.isNotEmpty)
          Padding(
            padding: const EdgeInsets.only(top: 2),
            child: Text(
              subtitle!,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: theme.textTheme.bodySmall?.copyWith(color: tk.textMuted),
            ),
          ),
      ],
    );
  }
}

/// The header line under the library name: tabs on the left, the active tab's
/// actions on the right, closed off with a hairline.
class LibraryHeaderBar extends StatelessWidget {
  final List<Widget> tabs;
  final List<LibraryHeaderAction> actions;

  /// Gap between the tab labels.
  final double tabSpacing;

  /// Off for the TV backdrop, where a rule would cut across the artwork.
  final bool showDivider;

  final EdgeInsetsGeometry padding;

  /// Where LEFT from the first action goes, for actions that do not wire it
  /// themselves. The tab row is the screen's business, not the tab's.
  final VoidCallback? onActionsExitLeft;

  /// Where RIGHT from the last action goes, same reasoning.
  final VoidCallback? onActionsExitRight;

  const LibraryHeaderBar({
    super.key,
    required this.tabs,
    this.actions = const [],
    this.tabSpacing = 22,
    this.showDivider = true,
    this.padding = const EdgeInsets.only(left: 4, right: 16),
    this.onActionsExitLeft,
    this.onActionsExitRight,
  });

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);

    // The hairline is a layer under the row, not a border on it: the tabs run
    // the full height of the bar and the active one paints its rule at the same
    // baseline, so it brightens a segment of this line instead of hanging a
    // second line above it.
    return SizedBox(
      height: LibraryHeaderMetrics.barHeight,
      child: Stack(
        children: [
          if (showDivider)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: Container(height: 1, color: tk.outline.withValues(alpha: 0.6)),
            ),
          Padding(padding: padding, child: _buildRow()),
        ],
      ),
    );
  }

  Widget _buildRow() {
    // The tab side scrolls instead of overflowing: a narrow window with four
    // tabs and three actions runs out of line before the actions do, and a
    // striped overflow banner in the header is worse than a scroll.
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < tabs.length; i++) ...[if (i > 0) SizedBox(width: tabSpacing), tabs[i]],
              ],
            ),
          ),
        ),
        Row(
          // Centred, not stretched: these carry no bar of their own, so there is
          // nothing here that has to line up with the bottom edge.
          crossAxisAlignment: CrossAxisAlignment.center,
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < actions.length; i++) ...[
              if (i > 0) const SizedBox(width: 2),
              AutomationNode(
                id: actions[i].automationId,
                role: 'filter',
                focusNode: actions[i].focusNode,
                child: FocusableFilterChip(
                  variant: FilterChipVariant.text,
                  label: actions[i].label,
                  value: actions[i].value,
                  selected: actions[i].isActive,
                  focusNode: actions[i].focusNode,
                  onPressed: actions[i].onPressed,
                  onNavigateLeft: actions[i].onNavigateLeft ?? (i == 0 ? onActionsExitLeft : null),
                  onNavigateRight: actions[i].onNavigateRight ?? (i == actions.length - 1 ? onActionsExitRight : null),
                  onNavigateUp: actions[i].onNavigateUp,
                  onNavigateDown: actions[i].onNavigateDown,
                  onBack: actions[i].onBack,
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }
}
