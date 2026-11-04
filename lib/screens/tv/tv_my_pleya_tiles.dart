part of 'tv_my_pleya_screen.dart';

/// The `Snel naar` row (northstar A10, A15): one row, the tiles sharing its
/// width equally, so four tiles sit wider than six and a missing option
/// leaves no hole.
class _Dock extends StatelessWidget {
  const _Dock({required this.tiles, required this.map, required this.onOpen});

  final List<TvMyPleyaTile> tiles;
  final _PageFocusMap map;
  final ValueChanged<TvMyPleyaTile> onOpen;

  @override
  Widget build(BuildContext context) {
    final pt = TvHig.of(context);
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * TvLayoutConstants.scaleOf(context);
    return SizedBox(
      height: _Pt.tileHeight * pt + 2 * ringGap,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (index, tile) in tiles.indexed) ...[
            if (index > 0) SizedBox(width: (_Pt.tileGap * pt - 2 * ringGap).clamp(0.0, double.infinity)),
            Expanded(
              child: _DockTile(tile: tile, map: map, onSelect: () => onOpen(tile)),
            ),
          ],
        ],
      ),
    );
  }
}

/// A destination as a quiet card: a line icon at the top, the name at the
/// bottom. Same fill and ring as the rest of the TV hub (VIS-0925-A).
class _DockTile extends StatelessWidget {
  const _DockTile({required this.tile, required this.map, required this.onSelect});

  final TvMyPleyaTile tile;
  final _PageFocusMap map;
  final VoidCallback onSelect;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final pt = TvHig.of(context);
    final radius = _Pt.tileRadius * pt;
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final light = Theme.of(context).brightness == Brightness.light;
    final key = tile.focusKey;

    return FocusableWrapper(
      focusNode: map.nodes.get(key, debugLabel: key),
      onSelect: onSelect,
      onNavigateLeft: () => map.move(key, TraversalDirection.left),
      onNavigateRight: () => map.move(key, TraversalDirection.right),
      onNavigateUp: () => map.move(key, TraversalDirection.up),
      onNavigateDown: () => map.move(key, TraversalDirection.down),
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: ringGap),
      // Suffixed by section name, not by index: the tile order follows what
      // the profile actually has.
      automationId: AutomationIds.myPleyaTile,
      automationInstance: tile.section?.name,
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{'title': tile.title},
      // Hoofdstuk 33.8: menu tiles do not scale; the ring and the lighter fill
      // say where the remote is.
      disableScale: true,
      scrollOnlyWhenHidden: true,
      semanticLabel: tile.title,
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(ringGap),
          child: Builder(
            builder: (context) {
              final focused = Focus.of(context).hasFocus;
              return AnimatedContainer(
                duration: TvTopNavLayout.focusDuration,
                curve: Curves.easeOut,
                padding: EdgeInsets.symmetric(horizontal: _Pt.tilePadding * pt, vertical: _Pt.tilePaddingVertical * pt),
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(radius),
                  color: light
                      ? Color.alphaBlend(
                          tk.text.withValues(alpha: focused ? TvMyPleyaLayout.tileFillAlpha : 0),
                          Colors.white,
                        )
                      : tk.text.withValues(
                          alpha: focused ? TvMyPleyaLayout.tileFocusedFillAlpha : TvMyPleyaLayout.tileFillAlpha,
                        ),
                  border: Border.all(color: tk.outline),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Icon(
                      tile.icon,
                      size: _Pt.tileIcon * pt,
                      weight: 300,
                      color: tk.text.withValues(alpha: TvMyPleyaLayout.inkSecondary),
                    ),
                    Flexible(
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final style = TextStyle(
                            color: tk.text,
                            fontSize: _Pt.tileTitle * pt,
                            height: 1.2,
                            fontWeight: FontWeight.w600,
                          );
                          return Text(
                            tile.title,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: style.copyWith(
                              fontSize: _fittedTitleSize(context, tile.title, style, constraints.maxWidth, pt),
                            ),
                          );
                        },
                      ),
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

/// The dock label's size: A10's 26 pt, or less where a row of seven tiles
/// (Android TV, with Downloads) leaves a single word too little room, and
/// never under the 23 pt tvOS minimum. Two words wrap onto a second line;
/// one word cannot, so it is the longest word that decides.
double _fittedTitleSize(BuildContext context, String title, TextStyle style, double maxWidth, double pt) {
  final words = title.split(RegExp(r'\s+')).where((word) => word.isNotEmpty);
  var widest = 0.0;
  for (final word in words) {
    final painter = TextPainter(
      text: TextSpan(text: word, style: style),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
      maxLines: 1,
    )..layout();
    if (painter.width > widest) widest = painter.width;
    painter.dispose();
  }
  final base = style.fontSize!;
  if (widest <= maxWidth || widest == 0) return base;
  return (base * maxWidth / widest).clamp(TvHig.caption2 * pt, base);
}
