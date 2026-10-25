part of 'tv_my_pleya_screen.dart';

/// The two columns of northstar 01: the left one takes what is left after the
/// fixed right column, with a hairline between them that runs the height of
/// the taller one.
class _TwoColumns extends StatelessWidget {
  const _TwoColumns({required this.left, required this.right});

  final Widget left;
  final Widget right;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * TvLayoutConstants.scaleOf(context);
    return Stack(
      children: [
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: left),
            SizedBox(width: (kTvMyPleyaDividerGapLeftPt + kTvMyPleyaDividerGapRightPt) * pt),
            SizedBox(width: kTvMyPleyaRightColumnPt * pt + 2 * ringGap, child: right),
          ],
        ),
        // Positioned against the right column, so it does not need to know how
        // wide the left one came out. A Stack sizes to the Row, and top/bottom
        // stretch the line to the taller column.
        Positioned(
          top: 0,
          bottom: 0,
          right: kTvMyPleyaRightColumnPt * pt + 2 * ringGap + kTvMyPleyaDividerGapRightPt * pt,
          width: 1,
          child: ColoredBox(color: tokens(context).outline),
        ),
      ],
    );
  }
}

/// A small caps heading ("JE KIJKLIJST", "MIJN CONTENT", "PLEYA", "BEHEER").
class _GroupLabel extends StatelessWidget {
  const _GroupLabel(this.label, {this.trailing});

  final String label;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * TvLayoutConstants.scaleOf(context);
    return Padding(
      padding: EdgeInsets.symmetric(horizontal: ringGap),
      child: Row(
        children: [
          Expanded(
            child: Semantics(
              header: true,
              child: Text(
                label.toUpperCase(),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                  fontSize: TvHig.caption2 * pt,
                  fontWeight: FontWeight.w600,
                  letterSpacing: 2.2 * pt,
                ),
              ),
            ),
          ),
          ?trailing,
        ],
      ),
    );
  }
}

/// One group's tiles. A row shares the column's width between its tiles, up to
/// a tile's maximum, so three tiles sit wider than four (northstar 01) and a
/// tile that disappears closes up rather than leaving a hole (northstar 04).
class _TileGrid extends StatelessWidget {
  const _TileGrid({required this.tiles, required this.map, required this.onOpen});

  final List<TvMyPleyaTile> tiles;
  final _HubFocusMap map;
  final ValueChanged<TvMyPleyaTile> onOpen;

  /// The widest tile in a row, in points: three tiles in northstar 01.
  static const double _maxTilePt = 360;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final gap = kTvMyPleyaRowGapPt * pt;
    return LayoutBuilder(
      builder: (context, constraints) {
        final rows = _rowsOf(tiles);
        return Column(
          children: [
            for (final (index, row) in rows.indexed) ...[
              if (index > 0) SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (final (i, tile) in row.indexed) ...[
                      if (i > 0) SizedBox(width: gap),
                      SizedBox(
                        width: ((constraints.maxWidth - gap * (row.length - 1)) / row.length).clamp(0, _maxTilePt * pt),
                        child: _Tile(tile: tile, map: map, onSelect: () => onOpen(tile)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }
}

/// A destination as a quiet card: line icon, title, subtitle, chevron.
/// Uitloggen reads in the accent red. Used in both columns: in a row on the
/// left, full width under Beheer on the right.
class _Tile extends StatelessWidget {
  const _Tile({required this.tile, required this.map, required this.onSelect});

  final TvMyPleyaTile tile;
  final _HubFocusMap map;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final pt = TvHig.of(context);
    final radius = TvMyPleyaLayout.tileRadius * scale;
    final key = tile.focusKey;
    final destructive = tile.section == null;
    final ink = destructive ? tk.accent : tk.text;
    void go(TraversalDirection direction) => _focus(map, map.next(key, direction));

    return FocusableWrapper(
      focusNode: map.nodes.get(key, debugLabel: key),
      onSelect: onSelect,
      onNavigateLeft: () => go(TraversalDirection.left),
      onNavigateRight: () => go(TraversalDirection.right),
      onNavigateUp: () => go(TraversalDirection.up),
      onNavigateDown: () => go(TraversalDirection.down),
      // VIS-0925-A: the ring surrounds the tile plus its ring gap.
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: TvMyPleyaLayout.tileFocusRingGap * scale),
      // Suffixed by section name, not by index: the tile order follows what
      // the profile actually has. `logout` for the one tile that opens nothing.
      automationId: AutomationIds.myPleyaTile,
      automationInstance: tile.section?.name ?? 'logout',
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{'title': tile.title, if (tile.count != null) 'count': tile.count},
      // Hoofdstuk 33.8: menu tiles do not scale; the ring and the lighter fill
      // say where the remote is.
      disableScale: true,
      // Beheer and Bronnen are on the first screen; a fully visible tile must
      // not scroll the page and push the title out of view (northstar 03).
      scrollOnlyWhenHidden: true,
      semanticLabel: tile.count == null
          ? t.tvMyPleya.semantics.tile(title: tile.title, subtitle: tile.subtitle)
          : t.tvMyPleya.semantics.tileWithCount(title: tile.title, subtitle: tile.subtitle, count: '${tile.count}'),
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(horizontal: 12 * pt, vertical: 8 * pt),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: tk.text.withValues(
                    alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      tile.icon,
                      size: 26 * pt,
                      weight: 300,
                      color: ink.withValues(alpha: destructive ? 1 : 0.8),
                    ),
                    SizedBox(width: 10 * pt),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(
                            tile.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: ink,
                              fontSize: TvHig.caption1 * pt,
                              height: 1.2,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          Text(
                            tile.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                              fontSize: TvHig.caption2 * pt,
                              height: 1.15,
                            ),
                          ),
                        ],
                      ),
                    ),
                    if (tile.count != null) ...[
                      SizedBox(width: 10 * pt),
                      Text(
                        '${tile.count}',
                        style: TextStyle(
                          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                          fontSize: TvHig.caption1 * pt,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ],
                    SizedBox(width: 4 * pt),
                    Icon(
                      Symbols.chevron_right_rounded,
                      size: 20 * pt,
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

void _focus(_HubFocusMap map, String? key) {
  if (key == null) return;
  final node = map.nodes.get(key);
  if (node.canRequestFocus) node.requestFocus();
}
