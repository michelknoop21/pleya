part of 'tv_my_pleya_screen.dart';

/// `JE KIJKLIJST` with `Bekijk alles`, and the posters under it (northstar 01
/// and 02). The same titles and the same rule for what a poster opens as the
/// iPhone rail (`my_pleya_shared.dart`); the poster itself is the kijklijst's
/// catalogue card, so title, year and focus lift match the full kijklijst.
class _WatchlistBlock extends StatelessWidget {
  const _WatchlistBlock({
    required this.entries,
    required this.provider,
    required this.map,
    required this.seeAllNode,
    required this.onOpenAll,
  });

  final List<WatchlistEntry> entries;
  final WatchlistProvider provider;
  final _HubFocusMap map;
  final FocusNode seeAllNode;
  final VoidCallback onOpenAll;

  /// Poster width and the room between two posters, in points.
  static const double _posterPt = 153;
  static const double _posterGapPt = 31;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final inset = TvCatalogLayout.cardContentInset(scale);
    final posterWidth = _posterPt * pt;
    final cardWidth = posterWidth + inset * 2;
    final cardHeight = TvCatalogLayout.cardHeight(cardWidth, scale, titleLines: 1);
    final growth = TvCatalogGrid.focusHeadroom(cardHeight: cardHeight, focusScale: FocusTheme.fullCardFocusScale);
    final gap = (_posterGapPt * pt - inset * 2).clamp(0.0, double.infinity);
    void go(String key, TraversalDirection direction) => _focus(map, map.next(key, direction));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupLabel(
          t.settingsStudio.yourWatchlist,
          trailing: _SeeAllLink(
            node: seeAllNode,
            onSelect: onOpenAll,
            onNavigate: (direction) => go(_seeAllKey, direction),
          ),
        ),
        SizedBox(height: (kTvMyPleyaLabelGapPt * pt - inset).clamp(0.0, double.infinity)),
        if (entries.isEmpty)
          Padding(
            padding: EdgeInsets.symmetric(horizontal: TvMyPleyaLayout.tileFocusRingGap * scale, vertical: inset),
            child: Text(
              t.watchlist.empty,
              style: TextStyle(
                color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                fontSize: TvHig.caption1 * pt,
              ),
            ),
          )
        else
          // The clip is the rail's box grown by the focus lift, so a focused
          // poster is drawn whole while a poster scrolled past the end is cut
          // at the column instead of running under the right column.
          ClipRect(
            clipper: _GrownClip(growth + inset),
            child: SizedBox(
              height: cardHeight,
              child: ListView.separated(
                scrollDirection: Axis.horizontal,
                clipBehavior: Clip.none,
                itemCount: entries.length,
                separatorBuilder: (context, _) => SizedBox(width: gap),
                itemBuilder: (context, index) {
                  final entry = entries[index];
                  final key = _posterKey(entry);
                  final node = map.nodes.get(key, debugLabel: key);
                  final target = myPleyaWatchlistTarget(provider, entry);
                  return AutomationNode(
                    id: AutomationIds.myPleyaWatchlistItem,
                    instance: '$index',
                    role: 'grid.item',
                    focusNode: node,
                    state: () => <String, Object?>{'title': entry.item.displayTitle, 'playable': target != null},
                    // The catalogue card the kijklijst uses on TV, with the
                    // iPhone rail's picture and its watched mark: one rule for
                    // what a Mijn Pleya poster shows on both platforms.
                    child: TvCatalogCard(
                      width: cardWidth,
                      artwork: MyPleyaWatchlistArtwork(
                        entry: entry,
                        match: target,
                        width: posterWidth,
                        height: posterWidth / TvCatalogLayout.posterAspectRatio,
                      ),
                      topRightMarker: target?.isWatched == true ? TvCatalogWatchedBadge(scale: scale) : null,
                      title: entry.item.displayTitle,
                      titleLines: 1,
                      meta: entry.item.year == null ? '' : '${entry.item.year}',
                      semanticLabel: tvWatchlistSemanticLabel(entry),
                      focusNode: node,
                      onSelect: target == null ? onOpenAll : () => unawaited(navigateToMediaItem(context, target)),
                      onNavigateLeft: () => go(key, TraversalDirection.left),
                      onNavigateRight: () => go(key, TraversalDirection.right),
                      onNavigateUp: () => go(key, TraversalDirection.up),
                      onNavigateDown: () => go(key, TraversalDirection.down),
                    ),
                  );
                },
              ),
            ),
          ),
      ],
    );
  }
}

class _GrownClip extends CustomClipper<Rect> {
  const _GrownClip(this.by);

  final double by;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-by, -by, size.width, size.height + by);

  @override
  bool shouldReclip(_GrownClip oldClipper) => oldClipper.by != by;
}

/// `Bekijk alles ›` in the accent tint, right of the heading. It opens the
/// full kijklijst and carries the id the Kijklijst tile had
/// (`my_pleya.tile[watchlist]`).
class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.node, required this.onSelect, required this.onNavigate});

  final FocusNode node;
  final VoidCallback onSelect;
  final ValueChanged<TraversalDirection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    const shape = StadiumBorder();
    return FocusableWrapper(
      focusNode: node,
      onSelect: onSelect,
      onNavigateLeft: () => onNavigate(TraversalDirection.left),
      onNavigateRight: () => onNavigate(TraversalDirection.right),
      onNavigateUp: () => onNavigate(TraversalDirection.up),
      onNavigateDown: () => onNavigate(TraversalDirection.down),
      focusShapeBorder: shape,
      disableScale: true,
      scrollOnlyWhenHidden: true,
      automationId: AutomationIds.myPleyaTile,
      automationInstance: TvMyPleyaSection.watchlist.name,
      automationRole: 'button',
      automationState: () => <String, Object?>{'title': t.myPleya.seeAll},
      semanticLabel: t.myPleya.seeAll,
      child: Padding(
        padding: EdgeInsets.symmetric(horizontal: 14 * pt, vertical: 4 * pt),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.myPleya.seeAll,
              style: TextStyle(color: tk.accent, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w600),
            ),
            SizedBox(width: 6 * pt),
            Icon(Symbols.chevron_right_rounded, size: 26 * pt, color: tk.accent),
          ],
        ),
      ),
    );
  }
}
