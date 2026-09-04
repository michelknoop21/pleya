/// The Mijn Pleya tile language, as a primitive the nested pages can use.
///
/// Instellingen, Servers, Over and Samen Kijken are all the same shape of
/// thing as the hub: an index of destinations. Before this they were rendered
/// by `settings_section.dart`'s desktop primitives instead — a card capped at
/// `kSettingsMaxWidth`, hairline separators between rows, and a 3px bar on the
/// left of the focused row where the rest of the TV product draws a white
/// ring. One page, three focus affordances across the product, and a column
/// that stopped at 81% of the screen.
///
/// So the tile moves here and those pages use it. Two columns rather than the
/// hub's four, because a settings row carries a value as well as a title and
/// four of those on one line is unreadable at ten feet.
///
/// Traversal is the grid's own: left/right walks the flat order across group
/// boundaries, up/down moves one visual row keeping the column, and the edges
/// hand back to the caller ([onExitUp]) rather than dead-ending. That mirrors
/// the hub's rules deliberately — a viewer should not have to learn a second
/// set of them one level down.
library;

import 'package:flutter/material.dart';

import '../../automation/automation_ids.dart';
import '../../focus/focus_memory_tracker.dart';
import '../../theme/mono_tokens.dart';
import '../../utils/layout_constants.dart';
import '../../focus/focusable_wrapper.dart';
import 'tv_page_surface.dart';
import 'tv_unified_layout.dart';

/// One destination on a TV menu page.
class TvMenuItem {
  const TvMenuItem({
    required this.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.value,
    this.onSelect,
    this.onLongPress,
    this.selected = false,
    this.toggled,
  });

  /// Stable within the page. Also the focus key, so a page can restore where
  /// the remote was.
  final String key;
  final IconData icon;
  final String title;

  /// What the destination is for. Shown when there is no [value].
  final String? subtitle;

  /// The setting's current state ("OLED · Bibliotheek dichtheid 3"). Takes the
  /// subtitle's line, because on a settings index the present value is worth
  /// more than a restatement of the title.
  final String? value;

  final VoidCallback? onSelect;

  /// Held SELECT, for a tile that has a second, non-destination action behind
  /// it — renaming or forgetting a recent Samen Kijken room, the way the
  /// mobile list tile already does it. Absent on tiles that are only a way in.
  final VoidCallback? onLongPress;

  /// Drawn as the chosen one of a set. Used by the library chooser, where the
  /// active source has to be visible without opening anything.
  final bool selected;

  /// A switch's state, when this tile is one. Null on a tile that opens
  /// something.
  ///
  /// Deliberately not [selected]. A chosen library is the one of several the
  /// page is showing, and it earns the raised fill for that; a settings page
  /// where every enabled switch drew itself at the focused fill would have six
  /// tiles claiming to hold the remote. So a toggle says its state in the
  /// glyph and on the value line, and leaves the fill to mean focus.
  final bool? toggled;
}

/// A labelled block of tiles. One group is one visual row band.
class TvMenuSection {
  const TvMenuSection({this.label, required this.items});

  final String? label;
  final List<TvMenuItem> items;
}

/// Lays [sections] out as tile rows and owns the directional walk between them.
class TvMenuGrid extends StatelessWidget {
  const TvMenuGrid({
    super.key,
    required this.sections,
    required this.nodes,
    required this.columns,
    required this.automationInstance,
    this.onExitUp,
    this.onExitDown,
  });

  final List<TvMenuSection> sections;

  /// Owned by the page's State, not rebuilt per frame: a value arriving must
  /// not dispose the node the remote is standing on.
  final FocusMemoryTracker nodes;

  final int columns;

  /// The page this grid belongs to, prefixed onto every tile's automation
  /// instance (`my_pleya.section.tile[settings.about]`). Required rather than
  /// optional: the registry is global and holds offstage screens, so a grid
  /// without a page name is a grid whose tiles can be resolved as another
  /// page's.
  final String automationInstance;

  /// UP off the first row. The page hands this to the shell so the remote can
  /// reach the top navigation again.
  final VoidCallback? onExitUp;
  final VoidCallback? onExitDown;

  /// Every focusable key on the page, in reading order.
  List<String> get keys => [for (final s in sections) ...s.items.map((i) => i.key)];

  /// The rows as the eye sees them: a section of five in a two-column grid is
  /// three rows, not one. Up/down has to move by these, or a page whose last
  /// row is short sends the remote to the wrong column.
  List<List<TvMenuItem>> get _rows => [
    for (final s in sections)
      for (var i = 0; i < s.items.length; i += columns) s.items.sublist(i, (i + columns).clamp(0, s.items.length)),
  ];

  String? _flatNeighbour(String key, int delta) {
    final all = keys;
    final index = all.indexOf(key);
    if (index < 0) return null;
    final target = index + delta;
    return (target < 0 || target >= all.length) ? null : all[target];
  }

  ({int row, int column})? _positionOf(String key) {
    final rows = _rows;
    for (var r = 0; r < rows.length; r++) {
      final c = rows[r].indexWhere((i) => i.key == key);
      if (c >= 0) return (row: r, column: c);
    }
    return null;
  }

  /// One visual row up or down, keeping the column, clipped to that row's
  /// width. Returns null at the page's edges so the caller can decide.
  String? _verticalNeighbour(String key, int delta) {
    final at = _positionOf(key);
    if (at == null) return null;
    final rows = _rows;
    final target = at.row + delta;
    if (target < 0 || target >= rows.length) return null;
    final row = rows[target];
    return row[at.column.clamp(0, row.length - 1)].key;
  }

  void _focus(String? key) {
    if (key == null) return;
    final node = nodes.get(key);
    if (node.canRequestFocus) node.requestFocus();
  }

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final gap = TvMyPleyaLayout.tileGap * scale;
    final firstKey = keys.isEmpty ? null : keys.first;
    final lastKey = keys.isEmpty ? null : keys.last;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (var s = 0; s < sections.length; s++) ...[
          if (s > 0) SizedBox(height: TvMyPleyaLayout.groupGap * scale),
          if (sections[s].label != null) TvPageGroupLabel(sections[s].label!),
          for (var i = 0; i < sections[s].items.length; i += columns) ...[
            if (i > 0) SizedBox(height: gap),
            LayoutBuilder(
              builder: (context, constraints) {
                final track = (constraints.maxWidth - gap * (columns - 1)) / columns;
                final slice = sections[s].items.sublist(i, (i + columns).clamp(0, sections[s].items.length));
                return IntrinsicHeight(
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      for (var c = 0; c < slice.length; c++) ...[
                        if (c > 0) SizedBox(width: gap),
                        SizedBox(
                          width: track,
                          child: TvMenuTile(
                            item: slice[c],
                            scale: scale,
                            automationInstance: '$automationInstance.${slice[c].key}',
                            node: nodes.get(slice[c].key, debugLabel: slice[c].key),
                            onNavigateLeft: () => _focus(_flatNeighbour(slice[c].key, -1)),
                            onNavigateRight: () => _focus(_flatNeighbour(slice[c].key, 1)),
                            onNavigateUp: () {
                              final up = _verticalNeighbour(slice[c].key, -1);
                              if (up != null) return _focus(up);
                              if (slice[c].key == firstKey || _positionOf(slice[c].key)?.row == 0) onExitUp?.call();
                            },
                            onNavigateDown: () {
                              final down = _verticalNeighbour(slice[c].key, 1);
                              if (down != null) return _focus(down);
                              if (slice[c].key == lastKey || onExitDown != null) onExitDown?.call();
                            },
                          ),
                        ),
                      ],
                      // Short rows keep their empty tracks rather than letting
                      // two tiles stretch across the page.
                      if (slice.length < columns) SizedBox(width: (track + gap) * (columns - slice.length)),
                    ],
                  ),
                );
              },
            ),
          ],
        ],
      ],
    );
  }
}

/// The tile itself: the hub's surface, radius, type scale and white focus ring.
class TvMenuTile extends StatelessWidget {
  const TvMenuTile({
    super.key,
    required this.item,
    required this.scale,
    required this.node,
    required this.automationInstance,
    this.onNavigateLeft,
    this.onNavigateRight,
    this.onNavigateUp,
    this.onNavigateDown,
  });

  final TvMenuItem item;
  final double scale;
  final FocusNode node;
  final String automationInstance;
  final VoidCallback? onNavigateLeft;
  final VoidCallback? onNavigateRight;
  final VoidCallback? onNavigateUp;
  final VoidCallback? onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final radius = TvMyPleyaLayout.tileRadius * scale;
    final secondary = item.value ?? item.subtitle;

    return FocusableWrapper(
      focusNode: node,
      onSelect: item.onSelect,
      enableLongPress: item.onLongPress != null,
      onLongPress: item.onLongPress,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      borderRadius: radius,
      automationId: AutomationIds.myPleyaSectionTile,
      automationInstance: automationInstance,
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{
        'title': item.title,
        if (item.value != null) 'value': item.value,
        // Always present, for the reason `TvPageChipBar` documents: an
        // assertion that a tile is *not* the chosen one has to be able to read
        // false rather than null.
        'selected': item.selected,
        if (item.toggled != null) 'toggled': item.toggled,
      },
      // Hoofdstuk 33.8: menu tiles do not scale on focus. The ring and the
      // lighter fill already say where the remote is.
      disableScale: true,
      semanticLabel: secondary == null ? item.title : '${item.title}. $secondary',
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                constraints: BoxConstraints(minHeight: TvMyPleyaLayout.tileMinHeight * scale),
                padding: EdgeInsets.all(TvMyPleyaLayout.tilePadding * scale),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: tk.text.withValues(
                    alpha: focused || item.selected
                        ? TvMyPleyaLayout.tileFocusedFillAlpha
                        : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Icon(
                          item.icon,
                          size: TvMyPleyaLayout.tileIconSize * scale,
                          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                        ),
                        const Spacer(),
                        if (item.selected)
                          Icon(Icons.check_rounded, size: TvMyPleyaLayout.tileIconSize * scale, color: tk.text)
                        else if (item.toggled != null)
                          Icon(
                            item.toggled! ? Icons.toggle_on_rounded : Icons.toggle_off_rounded,
                            size: TvMyPleyaLayout.tileIconSize * scale,
                            color: tk.text.withValues(
                              alpha: item.toggled! ? TvMyPleyaLayout.inkPrimary : TvMyPleyaLayout.inkTertiary,
                            ),
                          ),
                      ],
                    ),
                    SizedBox(height: TvMyPleyaLayout.tileIconTitleGap * scale),
                    Text(
                      item.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        color: tk.text,
                        fontSize: TvMyPleyaLayout.tileTitleFontSize * scale,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    if (secondary != null) ...[
                      SizedBox(height: TvMyPleyaLayout.tileTitleSubtitleGap * scale),
                      Text(
                        secondary,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          color: tk.text.withValues(
                            alpha: item.value != null ? TvMyPleyaLayout.inkSecondary : TvMyPleyaLayout.inkTertiary,
                          ),
                          fontSize: TvMyPleyaLayout.tileSubtitleFontSize * scale,
                        ),
                      ),
                    ],
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
