part of 'tv_my_pleya_screen.dart';

/// One group's tiles, laid out on the shared column grid.
///
/// Every group uses the same [TvMyPleyaLayout.tilesPerRow] track width, so a
/// group of three and a group of four line up down the page instead of each
/// stretching to fill its own row — which is what the north star shows, and
/// what keeps a conditional tile disappearing from *closing up* rather than
/// resizing its neighbours (hoofdstuk 33.8).
class _TileRow extends StatelessWidget {
  const _TileRow({
    required this.tiles,
    required this.scale,
    required this.nodes,
    required this.keys,
    required this.groups,
    required this.onFocusKey,
    required this.onOpen,
  });

  final List<TvMyPleyaTile> tiles;
  final double scale;
  final FocusMemoryTracker nodes;
  final List<String> keys;

  /// Every group on the page, in order. A group can span more than one visual
  /// row once it has over [TvMyPleyaLayout.tilesPerRow] tiles.
  final List<TvMyPleyaGroup> groups;
  final void Function(String? key) onFocusKey;
  final ValueChanged<TvMyPleyaTile> onOpen;

  @override
  Widget build(BuildContext context) {
    final gap = TvMyPleyaLayout.tileGap * scale;
    return LayoutBuilder(
      builder: (context, constraints) {
        final trackWidth =
            (constraints.maxWidth - gap * (TvMyPleyaLayout.tilesPerRow - 1)) / TvMyPleyaLayout.tilesPerRow;
        // The tiles in a row share a height, so a two-line subtitle in one of
        // them does not leave its neighbours short — a ragged row of boxes is
        // exactly what the north star's even grid is not. `IntrinsicHeight`
        // rather than a fixed height, because the height that matters is the
        // tallest tile's, and that depends on the locale. Four children at
        // most, so the second pass costs nothing worth measuring.
        return Column(
          children: [
            for (var start = 0; start < tiles.length; start += TvMyPleyaLayout.tilesPerRow) ...[
              if (start > 0) SizedBox(height: gap),
              IntrinsicHeight(
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    for (var i = start; i < (start + TvMyPleyaLayout.tilesPerRow).clamp(0, tiles.length); i++) ...[
                      if (i > start) SizedBox(width: gap),
                      SizedBox(
                        width: trackWidth,
                        child: _Tile(
                          tile: tiles[i],
                          scale: scale,
                          node: nodes.get(tiles[i].focusKey, debugLabel: tiles[i].focusKey),
                          onSelect: () => onOpen(tiles[i]),
                          onNavigateLeft: () => onFocusKey(_neighbour(tiles[i].focusKey, -1)),
                          onNavigateRight: () => onFocusKey(_neighbour(tiles[i].focusKey, 1)),
                          onNavigateUp: () => onFocusKey(_verticalNeighbour(tiles[i].focusKey, -1)),
                          onNavigateDown: () => onFocusKey(_verticalNeighbour(tiles[i].focusKey, 1)),
                        ),
                      ),
                    ],
                    if (tiles.length - start < TvMyPleyaLayout.tilesPerRow)
                      SizedBox(width: (trackWidth + gap) * (TvMyPleyaLayout.tilesPerRow - (tiles.length - start))),
                  ],
                ),
              ),
            ],
          ],
        );
      },
    );
  }

  /// Left/right walks the flat page order, so the end of one group hands over
  /// to the start of the next instead of dead-ending mid-page.
  String? _neighbour(String key, int delta) {
    final index = keys.indexOf(key);
    if (index < 0) return null;
    final target = index + delta;
    return (target < 0 || target >= keys.length) ? null : keys[target];
  }

  /// Up/down moves one visual row, keeping the column.
  ///
  /// It used to step [TvMyPleyaLayout.tilesPerRow] places through the flat
  /// order instead, which is only the same thing when every row is full and
  /// nothing precedes the grid. Neither holds: the profile header is the first
  /// entry in [keys] while being no part of the grid, and a group with three
  /// tiles is still one row. Both errors compound, and the result was
  /// reproducible on the simulator — DOWN from Servers, the second tile of a
  /// three-tile row, landed on Over, the *third* tile of the row below.
  ///
  /// A visual row is a four-tile slice of a group, so the column is the tile's
  /// position in its slice. From the top row UP lands on the profile header,
  /// whose own handler continues up to the top navigation; from the bottom row
  /// DOWN stays put rather than snapping to the last tile of the page, which
  /// is what clamping to [keys.last] used to do from any column.
  String? _verticalNeighbour(String key, int direction) {
    final rows = <List<TvMyPleyaTile>>[
      for (final group in groups)
        for (var start = 0; start < group.tiles.length; start += TvMyPleyaLayout.tilesPerRow)
          group.tiles.sublist(start, (start + TvMyPleyaLayout.tilesPerRow).clamp(0, group.tiles.length)),
    ];
    for (var rowIndex = 0; rowIndex < rows.length; rowIndex++) {
      final column = rows[rowIndex].indexWhere((tile) => tile.focusKey == key);
      if (column < 0) continue;
      final target = rowIndex + direction;
      if (target < 0) return keys.first;
      if (target >= rows.length) return null;
      final row = rows[target];
      if (row.isEmpty) return null;
      return row[column < row.length ? column : row.length - 1].focusKey;
    }
    return null;
  }
}

class _Tile extends StatelessWidget {
  const _Tile({
    required this.tile,
    required this.scale,
    required this.node,
    required this.onSelect,
    required this.onNavigateLeft,
    required this.onNavigateRight,
    required this.onNavigateUp,
    required this.onNavigateDown,
  });

  final TvMyPleyaTile tile;
  final double scale;
  final FocusNode node;
  final VoidCallback onSelect;
  final VoidCallback onNavigateLeft;
  final VoidCallback onNavigateRight;
  final VoidCallback onNavigateUp;
  final VoidCallback onNavigateDown;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final radius = TvMyPleyaLayout.tileRadius * scale;
    final pt = TvHig.of(context);
    final bigP = tile.section == TvMyPleyaSection.assistant;

    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateLeft: onNavigateLeft,
      onNavigateRight: onNavigateRight,
      onNavigateUp: onNavigateUp,
      onNavigateDown: onNavigateDown,
      // VIS-0925-A: the ring surrounds the tile plus its ring gap, so its
      // radius follows the tile, the gap and the ring width.
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: TvMyPleyaLayout.tileFocusRingGap * scale),
      // Suffixed by section name, not by index: the tile order follows what
      // the profile actually has (Aanvragen only with a Seerr server), so an
      // index would address a different section on a different fixture.
      // `logout` for the one tile that opens nothing.
      automationId: AutomationIds.myPleyaTile,
      automationInstance: tile.section?.name ?? 'logout',
      automationRole: 'grid.item',
      // The bounds a focus-ring measurement needs are the wrapper's, which is
      // what the ring is drawn around — not the inner fill, which sits a
      // `tileFocusRingGap` inside it.
      automationState: () => <String, Object?>{'title': tile.title, if (tile.count != null) 'count': tile.count},
      // Hoofdstuk 33.8: menu tiles do not scale. Twelve boxes where one grows
      // reads as an unstable wall; the ring and the lighter fill are enough.
      disableScale: true,
      semanticLabel: tile.count == null
          ? t.tvMyPleya.semantics.tile(title: tile.title, subtitle: tile.subtitle)
          : t.tvMyPleya.semantics.tileWithCount(
              title: tile.title,
              subtitle: tile.subtitle,
              count: tile.count.toString(),
            ),
      // The label above already names the tile and says what it is for.
      // Leaving the icon, the count and the two Texts in the tree as well would
      // merge a second copy into the same node, and VoiceOver would read
      // "Servers, connections and local sources, Servers, connections and
      // local sources".
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                // VIS-0925-G (DEC-139): HIG points, the `TvMenuGrid` tile. The
                // glyph sits beside the text, title in Body (29 pt) and the
                // subtitle in Caption 1 (25 pt): about 100 pt tall, where the
                // stacked tile was 151 pt around 23.6/18.9 pt text.
                padding: EdgeInsets.symmetric(horizontal: 24 * pt, vertical: 16 * pt),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: tk.text.withValues(
                    alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                  ),
                ),
                child: Row(
                  children: [
                    if (!bigP) ...[
                      Icon(
                        tile.icon,
                        size: TvHig.body * pt,
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
                            tile.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tk.text,
                              fontSize: TvHig.body * pt,
                              height: TvHig.bodyLeading / TvHig.body,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                          // Two lines, as in `TvMenuGrid`: at Caption 1 in a
                          // four-column hub one line cut four of seven
                          // subtitles off (VIS-0925 review, FIX 1).
                          Text(
                            tile.subtitle,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                              fontSize: TvHig.caption1 * pt,
                              height: TvHig.caption1Leading / TvHig.caption1,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // Mockup 38 A: Big P's portrait on the right, as tall as
                    // the title and subtitle, so the tile keeps the hub's size.
                    if (bigP) ...[
                      SizedBox(width: 12 * pt),
                      BigPPortrait(focused: focused, size: (TvHig.bodyLeading + TvHig.caption1Leading) * pt),
                    ],
                    if (tile.count != null) ...[
                      SizedBox(width: 12 * pt),
                      Text(
                        '${tile.count}',
                        style: TextStyle(
                          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                          fontSize: TvHig.body * pt,
                          fontWeight: FontWeight.w500,
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
