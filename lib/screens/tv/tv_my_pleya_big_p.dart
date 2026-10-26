part of 'tv_my_pleya_screen.dart';

/// The Big P card at the top of the right column (northstar 01): the shared
/// [BigPCardFace] with "Open Big P", under one focus ring. Same section, same
/// route and same automation id as the tile it replaces.
class _BigPCard extends StatelessWidget {
  const _BigPCard({required this.tile, required this.map, required this.onOpen});

  final TvMyPleyaTile tile;
  final _HubFocusMap map;
  final VoidCallback onOpen;

  /// The iPhone card is 100 units high; the TV card is 140 points at least.
  /// Northstar 01 draws 165 with a one-line subtitle that a 23 pt line cannot
  /// hold in this column, so the card grows by the second line and the unit
  /// is a little smaller to keep Beheer on the first screen.
  static const double _unitPt = 1.4;

  @override
  Widget build(BuildContext context) {
    final scale = TvLayoutConstants.scaleOf(context);
    final pt = TvHig.of(context);
    final radius = 20 * pt;
    final key = tile.focusKey;
    void go(TraversalDirection direction) => _focus(map, map.next(key, direction));

    return FocusableWrapper(
      focusNode: map.nodes.get(key, debugLabel: key),
      onSelect: onOpen,
      onNavigateLeft: () => go(TraversalDirection.left),
      onNavigateRight: () => go(TraversalDirection.right),
      onNavigateUp: () => go(TraversalDirection.up),
      onNavigateDown: () => go(TraversalDirection.down),
      borderRadius: FocusTheme.ringRadiusAround(radius, gap: TvMyPleyaLayout.tileFocusRingGap * scale),
      automationId: AutomationIds.myPleyaTile,
      automationInstance: TvMyPleyaSection.assistant.name,
      automationRole: 'grid.item',
      automationState: () => <String, Object?>{'title': tile.title},
      disableScale: true,
      scrollOnlyWhenHidden: true,
      semanticLabel: t.tvMyPleya.semantics.tile(title: tile.title, subtitle: t.myPleya.bigPTvSubtitle),
      child: ExcludeSemantics(
        child: Padding(
          padding: EdgeInsets.all(TvMyPleyaLayout.tileFocusRingGap * scale),
          child: ClipRRect(
            borderRadius: BorderRadius.circular(radius),
            child: BigPCardFace(
              subtitle: t.myPleya.bigPTvSubtitle,
              action: t.myPleya.openBigP,
              unit: _unitPt * pt,
              minTextSize: TvHig.caption2 * pt,
              textRightReserve: 92,
            ),
          ),
        ),
      ),
    );
  }
}
