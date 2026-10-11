import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../../../automation/automation_ids.dart';
import '../../../focus/dpad_navigator.dart';
import '../../../focus/focus_theme.dart';
import '../../../focus/focusable_wrapper.dart';
import '../../../theme/mono_tokens.dart';
import '../../../utils/layout_constants.dart';
import '../../../utils/tv_hig.dart';
import '../../../widgets/tv/tv_unified_layout.dart';

/// A row of the memory screens on TV (43 M, `.tv .row`): the Mijn Pleya tile
/// surface and white focus ring, with the count and the chevron 43 M draws at
/// the right. Text in tvOS points: 25 for the title, 23 under it.
class MemoryTvTile extends StatelessWidget {
  const MemoryTvTile({
    super.key,
    required this.title,
    required this.node,
    required this.instance,
    this.icon,
    this.subtitle,
    this.value,
    this.onSelect,
    this.onNavigateUp,
    this.onNavigateDown,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.compact = false,
    this.titleLines = 1,
    this.automationId = AutomationIds.settingsMemoryAction,
    this.automationRole = 'button',
    this.state,
  });

  final String title;
  final FocusNode node;

  /// The automation instance under [automationId].
  final String instance;
  final IconData? icon;
  final String? subtitle;

  /// Right-aligned before the chevron: a count.
  final String? value;

  /// Null keeps the tile in the focus order and lets Select do nothing, so
  /// a tile that is busy for a moment does not drop the remote.
  final VoidCallback? onSelect;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;

  /// The lower row of a follow-up question (62 pt against 72).
  final bool compact;
  final int titleLines;
  final String automationId;
  final String automationRole;
  final Map<String, Object?> Function()? state;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final radius = 16 * pt;
    final gap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final select = onSelect;
    return FocusableWrapper(
      focusNode: node,
      onSelect: () {
        if (select == null) return;
        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
        select();
      },
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: gap),
      disableScale: true,
      automationId: automationId,
      automationInstance: instance,
      automationRole: automationRole,
      automationState: () => <String, Object?>{'enabled': select != null, ...?state?.call()},
      semanticLabel: [title, subtitle, value].nonNulls.join('. '),
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                constraints: BoxConstraints(minHeight: (compact ? 62 : 72) * pt),
                padding: EdgeInsets.symmetric(horizontal: 28 * pt, vertical: 8 * pt),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: tk.text.withValues(
                    alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Row(
                  children: [
                    if (icon != null) ...[
                      Icon(
                        icon,
                        size: 28 * pt,
                        color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                      ),
                      SizedBox(width: 20 * pt),
                    ],
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            title,
                            maxLines: titleLines,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tk.text.withValues(alpha: select == null ? TvMyPleyaLayout.inkSecondary : 1),
                              fontSize: TvHig.caption1 * pt,
                              height: TvHig.caption1Leading / TvHig.caption1,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                          if (subtitle != null)
                            Text(
                              subtitle!,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(
                                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                                fontSize: TvHig.caption2 * pt,
                                height: 1.3,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (value != null) ...[
                      SizedBox(width: 20 * pt),
                      Text(
                        value!,
                        style: TextStyle(
                          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                          fontSize: 24 * pt,
                        ),
                      ),
                    ],
                    SizedBox(width: 20 * pt),
                    Icon(
                      Symbols.chevron_right_rounded,
                      size: 24 * pt,
                      color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
    );
  }
}

/// A group label over tiles of 43 M (`.tv .group-label`): 26 pt.
class MemoryTvLabel extends StatelessWidget {
  const MemoryTvLabel(this.label, {super.key, this.trailing, this.first = false});

  final String label;
  final String? trailing;
  final bool first;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final tk = tokens(context);
    return Padding(
      padding: EdgeInsets.only(top: (first ? 0 : 14) * pt, bottom: 8 * pt, left: 4 * pt),
      child: Text.rich(
        TextSpan(
          text: label,
          children: [
            if (trailing != null)
              TextSpan(
                text: '   $trailing',
                style: TextStyle(
                  fontSize: TvHig.caption2 * pt,
                  fontWeight: FontWeight.w400,
                  color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                ),
              ),
          ],
        ),
        style: TextStyle(
          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
          fontSize: 26 * pt,
          fontWeight: FontWeight.w500,
        ),
      ),
    );
  }
}

/// Reading text of the TV screens: 29 pt, tvOS body.
TextStyle memoryTvBody(BuildContext context, {double alpha = 0.92}) => TextStyle(
  color: tokens(context).text.withValues(alpha: alpha),
  fontSize: TvHig.body * TvHig.of(context),
  height: 1.45,
);

/// The smallest text of the TV screens: 23 pt.
TextStyle memoryTvSmall(BuildContext context) => TextStyle(
  color: tokens(context).text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
  fontSize: TvHig.caption2 * TvHig.of(context),
  height: 1.4,
);
