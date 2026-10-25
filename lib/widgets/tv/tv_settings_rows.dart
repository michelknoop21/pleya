/// A-24 detail rows for the TV settings page: one focusable row per
/// [TvMenuItem], title on the left and the current value on the right.
///
/// The rows keep the tile's automation contract exactly
/// (`my_pleya.section.tile[<page>.<key>]`, role `grid.item`, the same state
/// fields), so a scenario that found a setting as a tile finds it as a row.
/// Only the layout and the walk differ: one column, UP and DOWN between
/// neighbours, and LEFT left to the enclosing categories layout.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../focus/focus_theme.dart';
import '../../focus/focusable_wrapper.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/tv_hig.dart';
import 'tv_menu_grid.dart';
import 'tv_settings_studio_style.dart';
import 'tv_unified_layout.dart';

/// Widest share of a row its value may take before it ellipsizes.
const double kTvSettingsValueMaxFraction = 0.6;

/// A column of [TvSettingsRow]s with its own vertical walk.
class TvSettingsRowList extends StatelessWidget {
  const TvSettingsRowList({super.key, required this.items, required this.nodes, required this.automationInstance});

  final List<TvMenuItem> items;

  /// The page's tracker, so a row keeps its node (and the page its memory of
  /// the row) across rebuilds and category switches.
  final FocusMemoryTracker nodes;

  /// The page name prefixed onto every row's automation instance.
  final String automationInstance;

  void _focus(int index) {
    if (index < 0 || index >= items.length) return;
    final node = nodes.get(items[index].key);
    if (node.canRequestFocus) node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var i = 0; i < items.length; i++) ...[
          // A hairline between rows, inset to the text.
          if (i > 0)
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 24 * TvHig.of(context)),
              child: SizedBox(height: 1, child: ColoredBox(color: tvStudioSeparator(tokens(context)))),
            ),
          TvSettingsRow(
            item: items[i],
            node: nodes.get(items[i].key, debugLabel: items[i].key),
            automationInstance: '$automationInstance.${items[i].key}',
            // The ends hold rather than wander off into another column.
            onNavigateUp: () => _focus(i - 1),
            onNavigateDown: () => _focus(i + 1),
          ),
        ],
      ],
    );
  }
}

/// One settings row. SELECT runs the item's action; for a preference that is
/// the toggle itself, so there is no separate switch to reach.
class TvSettingsRow extends StatelessWidget {
  const TvSettingsRow({
    super.key,
    required this.item,
    required this.node,
    required this.automationInstance,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final TvMenuItem item;
  final FocusNode node;
  final String automationInstance;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final radius = tk.radiusMd;
    final gap = TvMyPleyaLayout.tileFocusRingGap * pt;
    final secondary = item.value ?? item.subtitle;

    return FocusableWrapper(
      focusNode: node,
      onSelect: item.onSelect,
      enableLongPress: item.onLongPress != null,
      onLongPress: item.onLongPress,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: gap),
      automationId: AutomationIds.myPleyaSectionTile,
      automationInstance: automationInstance,
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{
        'title': item.title,
        if (item.value != null) 'value': item.value,
        'selected': item.selected,
        if (item.toggled != null) 'toggled': item.toggled,
      },
      disableScale: true,
      semanticLabel: secondary == null ? item.title : '${item.title}. $secondary',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(gap),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(horizontal: 24 * pt, vertical: 18 * pt),
                decoration: BoxDecoration(
                  color: tvStudioRowFill(tk, focused: focused),
                  borderRadius: BorderRadius.circular(radius),
                ),
                child: _RowContent(item: item, pt: pt),
              );
            },
          ),
        ),
      ),
    );
  }
}

class _RowContent extends StatelessWidget {
  const _RowContent({required this.item, required this.pt});

  final TvMenuItem item;
  final double pt;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final value = item.value;
    final subtitle = value == null ? item.subtitle : null;
    final valueStyle = TextStyle(
      color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
      fontSize: TvHig.caption1 * pt,
      height: TvHig.caption1Leading / TvHig.caption1,
      fontWeight: FontWeight.w500,
    );

    return LayoutBuilder(
      builder: (context, constraints) => Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  item.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    color: tk.text,
                    fontSize: TvHig.body * pt,
                    height: TvHig.bodyLeading / TvHig.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                // What the destination is for, where it has no value to show.
                // Two lines as on `TvMenuTile`: beside the library preview
                // one line cut most descriptions off.
                if (subtitle != null)
                  Text(
                    subtitle,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: valueStyle.copyWith(
                      color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                      fontWeight: FontWeight.w400,
                    ),
                  ),
              ],
            ),
          ),
          if (value != null) ...[
            SizedBox(width: 24 * pt),
            // Up to [kTvSettingsValueMaxFraction] of the row, so a long server
            // name cannot push the title out, while "OLED · Bibliotheek
            // dichtheid 3" still fits beside a short title.
            ConstrainedBox(
              constraints: BoxConstraints(maxWidth: constraints.maxWidth * kTvSettingsValueMaxFraction),
              child: Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.end,
                style: valueStyle,
              ),
            ),
          ],
          if (item.toggled != null) ...[
            SizedBox(width: 16 * pt),
            Icon(
              item.toggled! ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
              size: TvHig.headline * pt,
              color: item.toggled! ? tvStudioMarkerColor(tk) : tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
            ),
          ] else if (item.onSelect != null) ...[
            SizedBox(width: 12 * pt),
            Icon(
              Icons.chevron_right_rounded,
              size: TvHig.body * pt,
              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
            ),
          ],
        ],
      ),
    );
  }
}
