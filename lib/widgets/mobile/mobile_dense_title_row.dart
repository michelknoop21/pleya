/// The compact iPhone list header (Dense Library, variant 3): back, the title,
/// the count on the title's baseline, then the screen's own actions. One row
/// of 48 pt instead of a toolbar plus a separate count line.
library;

import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../automation/automation_node.dart';
import '../../theme/mono_tokens.dart';
import '../app_icon.dart';

/// Height of [MobileDenseTitleRow] when it sits in a [MobileDenseSliverAppBar].
const double mobileDenseTitleRowHeight = 48;

class MobileDenseTitleRow extends StatelessWidget {
  const MobileDenseTitleRow({
    super.key,
    required this.title,
    this.count,
    this.onBack,
    this.actions = const [],
    this.countAutomationId,
    this.automationInstance,
  });

  final String title;

  /// Muted text beside the title, already formatted. Null draws nothing.
  final String? count;

  /// Draws a back button when set.
  final VoidCallback? onBack;

  final List<Widget> actions;

  /// When set, the count is wrapped in an [AutomationNode] with this id.
  final String? countAutomationId;
  final String? automationInstance;

  @override
  Widget build(BuildContext context) {
    final countText = count;
    Widget? countWidget = countText == null
        ? null
        : Text(
            countText,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(fontSize: 13, color: tokens(context).textMuted),
          );
    final countId = countAutomationId;
    if (countWidget != null && countId != null) {
      countWidget = AutomationNode(id: countId, instance: automationInstance, role: 'region', child: countWidget);
    }
    return Padding(
      // Without a back button the title takes the 16 pt list inset.
      padding: EdgeInsets.fromLTRB(onBack == null ? 16 : 4, 0, 8, 0),
      child: Row(
        children: [
          if (onBack != null) IconButton(onPressed: onBack, icon: const AppIcon(Symbols.arrow_back_rounded, fill: 1)),
          Expanded(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Flexible(
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800),
                  ),
                ),
                if (countWidget != null) ...[const SizedBox(width: 10), Flexible(child: countWidget)],
              ],
            ),
          ),
          ...actions,
        ],
      ),
    );
  }
}

/// A [SliverAppBar] whose whole toolbar is a [MobileDenseTitleRow]. Scroll
/// behaviour (floating, pinned) stays the caller's; the status bar inset is
/// the app bar's own.
class MobileDenseSliverAppBar extends StatelessWidget {
  const MobileDenseSliverAppBar({
    super.key,
    required this.row,
    this.floating = false,
    this.pinned = false,
    this.backgroundColor,
    this.surfaceTintColor,
    this.shadowColor,
    this.scrolledUnderElevation,
  });

  final MobileDenseTitleRow row;
  final bool floating;
  final bool pinned;
  final Color? backgroundColor;
  final Color? surfaceTintColor;
  final Color? shadowColor;
  final double? scrolledUnderElevation;

  @override
  Widget build(BuildContext context) {
    return SliverAppBar(
      automaticallyImplyLeading: false,
      centerTitle: false,
      titleSpacing: 0,
      toolbarHeight: mobileDenseTitleRowHeight,
      floating: floating,
      pinned: pinned,
      backgroundColor: backgroundColor,
      surfaceTintColor: surfaceTintColor,
      shadowColor: shadowColor,
      scrolledUnderElevation: scrolledUnderElevation,
      title: row,
    );
  }
}
