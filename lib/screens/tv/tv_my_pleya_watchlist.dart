part of 'tv_my_pleya_screen.dart';

/// `JE KIJKLIJST` with `Bekijk alles ›`, and the posters under it, in one
/// quiet panel to the right of Big P (northstar A10). The kijklijst appears
/// once on the page; the iPhone rail's rule decides which titles show and what
/// a poster opens (`my_pleya_shared.dart`).
///
/// Posters only, as A10 draws them: the title is the poster's own artwork and
/// its spoken label, and a line of text under each would cost the panel the
/// height the dock needs.
class _WatchlistPanel extends StatefulWidget {
  const _WatchlistPanel({required this.entries, required this.provider, required this.map, required this.onOpenAll});

  final List<WatchlistEntry> entries;
  final WatchlistProvider provider;
  final _PageFocusMap map;
  final VoidCallback onOpenAll;

  /// The panel's inner padding and the room between two posters, in points.
  static const double _paddingPt = 32;
  static const double _topPaddingPt = 24;
  static const double _labelToPostersPt = 16;
  static const double _posterGapPt = 32;
  static const double _posterRadiusPt = 10;

  @override
  State<_WatchlistPanel> createState() => _WatchlistPanelState();
}

class _WatchlistPanelState extends State<_WatchlistPanel> {
  final ScrollController _controller = ScrollController();
  final GlobalKey _railKey = GlobalKey(debugLabel: 'tvMyPleya_rail');

  /// One poster plus the gap after it, and the poster's width, from the last
  /// layout; [_show] scrolls by them.
  double _pitch = 0;

  /// One tear-off, kept, so [_RailReveal.detach] recognises the one it was
  /// given: two tear-offs of a method are equal but not guaranteed identical
  /// (review 557-M8).
  late final bool Function(int index, VoidCallback then) _showHook = _show;
  double _posterWidth = 0;

  @override
  void initState() {
    super.initState();
    widget.map.rail.attach(show: _showHook, viewport: _viewport);
  }

  @override
  void dispose() {
    widget.map.rail.detach(_showHook);
    _controller.dispose();
    super.dispose();
  }

  Rect? _viewport() {
    final rail = _railKey.currentContext?.findRenderObject();
    if (rail is! RenderBox || !rail.attached || !rail.hasSize) return null;
    // Global, like the focus nodes it is compared with: under `_AppleTvScale` an
    // offset and a size only meet after both went through the transform.
    return MatrixUtils.transformRect(rail.getTransformTo(null), Offset.zero & rail.size);
  }

  /// Scrolls poster [index] into the rail when it is not built, the least
  /// distance that shows it whole, and calls [then] after the frame that
  /// builds it (review 557-I1: a far scrolled rail had no first poster to
  /// return to).
  bool _show(int index, VoidCallback then) {
    if (!_controller.hasClients || _pitch <= 0) return false;
    final position = _controller.position;
    final left = index * _pitch;
    final right = left + _posterWidth;
    var target = position.pixels;
    if (left < target) target = left;
    if (right > target + position.viewportDimension) target = right - position.viewportDimension;
    _controller.jumpTo(target.clamp(position.minScrollExtent, position.maxScrollExtent));
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) then();
    });
    WidgetsBinding.instance.ensureVisualUpdate();
    return true;
  }

  /// Keeps the focused poster inside the panel. A poster consumes its own
  /// arrow keys and `FocusableWrapper` only scrolls vertical scrollables, so
  /// without this the ring walks out of the panel from the sixth poster on
  /// (`TvCatalogCardRail._reveal` is the same fix for Home's rails). Measured
  /// on the poster's own focus box, ring room included, against the rail.
  void _reveal(FocusNode node) {
    final rail = _railKey.currentContext?.findRenderObject();
    final box = node.context?.findRenderObject();
    if (!_controller.hasClients || rail is! RenderBox || !rail.hasSize || box is! RenderBox) return;
    // In the rail's own logical pixels, the units of [jumpTo]. Global ones carry
    // `_AppleTvScale` and overshoot by it.
    final poster = box.localToGlobal(Offset.zero, ancestor: rail) & box.size;
    final position = _controller.position;
    var delta = 0.0;
    if (poster.right > rail.size.width) delta = poster.right - rail.size.width;
    if (poster.left < 0) delta = poster.left;
    final target = (position.pixels + delta).clamp(position.minScrollExtent, position.maxScrollExtent);
    if ((target - position.pixels).abs() < 0.5) return;
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _controller.jumpTo(target);
    } else {
      unawaited(_controller.animateTo(target, duration: const Duration(milliseconds: 220), curve: Curves.easeOutCubic));
    }
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final map = widget.map;
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final ringGap = TvMyPleyaLayout.tileFocusRingGap * scale;
    final radius = _Pt.cardRadius * pt;
    final light = Theme.of(context).brightness == Brightness.light;

    return Padding(
      // The panel has no ring of its own; this lines its edges up with the
      // Big P card's, which sits inside its ring gap.
      padding: EdgeInsets.all(ringGap),
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(radius),
          color: light ? Colors.white : tk.text.withValues(alpha: TvMyPleyaLayout.tileFillAlpha),
          border: Border.all(color: tk.outline),
        ),
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            _WatchlistPanel._paddingPt * pt,
            _WatchlistPanel._topPaddingPt * pt,
            _WatchlistPanel._paddingPt * pt - ringGap,
            _WatchlistPanel._topPaddingPt * pt,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _SectionLabel(
                t.settingsStudio.yourWatchlist,
                trailing: _SeeAllLink(
                  node: map.nodes.get(_seeAllKey, debugLabel: _seeAllKey),
                  onSelect: widget.onOpenAll,
                  onNavigate: (direction) => map.move(_seeAllKey, direction),
                ),
              ),
              SizedBox(height: _WatchlistPanel._labelToPostersPt * pt),
              Expanded(
                child: entries.isEmpty
                    ? Text(
                        t.watchlist.empty,
                        style: TextStyle(
                          color: tk.text.withValues(alpha: TvMyPleyaLayout.inkTertiary),
                          fontSize: TvHig.caption1 * pt,
                        ),
                      )
                    : LayoutBuilder(builder: (context, constraints) => _rail(context, constraints.maxHeight, pt)),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _rail(BuildContext context, double height, double pt) {
    final entries = widget.entries;
    final map = widget.map;
    final provider = widget.provider;
    final posterHeight = height;
    final posterWidth = posterHeight * TvCatalogLayout.posterAspectRatio;
    final gap = _WatchlistPanel._posterGapPt * pt;
    final radius = _WatchlistPanel._posterRadiusPt * pt;
    _pitch = posterWidth + gap;
    _posterWidth = posterWidth;

    // Clipped to the panel sideways only, so a focused poster's ring is
    // drawn whole above and below while a poster scrolled past the end is cut
    // at the panel's edge.
    return ClipRect(
      clipper: const _SidewaysClip(),
      child: ListView.separated(
        key: _railKey,
        controller: _controller,
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
            child: FocusableWrapper(
              focusNode: node,
              onFocusChange: (focused) {
                if (focused) _reveal(node);
              },
              onSelect: target == null ? widget.onOpenAll : () => unawaited(navigateToMediaItem(context, target)),
              onNavigateLeft: () => map.move(key, TraversalDirection.left),
              onNavigateRight: () => map.move(key, TraversalDirection.right),
              onNavigateUp: () => map.move(key, TraversalDirection.up),
              onNavigateDown: () => map.move(key, TraversalDirection.down),
              borderRadius: radius,
              disableScale: true,
              scrollOnlyWhenHidden: true,
              semanticLabel: tvWatchlistSemanticLabel(entry),
              child: ExcludeSemantics(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(radius),
                  child: SizedBox(
                    width: posterWidth,
                    height: posterHeight,
                    child: Stack(
                      fit: StackFit.expand,
                      children: [
                        MyPleyaWatchlistArtwork(entry: entry, match: target, width: posterWidth, height: posterHeight),
                        if (target?.isWatched == true)
                          PositionedDirectional(
                            top: 8 * pt,
                            end: 8 * pt,
                            child: TvCatalogWatchedBadge(scale: TvLayoutConstants.scaleOf(context)),
                          ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _SidewaysClip extends CustomClipper<Rect> {
  const _SidewaysClip();

  /// Generous above and below: the ring and its gap, never another row.
  static const double _bleed = 40;

  @override
  Rect getClip(Size size) => Rect.fromLTRB(-_bleed, -_bleed, size.width, size.height + _bleed);

  @override
  bool shouldReclip(_SidewaysClip oldClipper) => false;
}

/// `Bekijk alles ›`, right of the heading: white on dark, the brand red on
/// light (A10, A11). It opens the full kijklijst and carries the id the
/// Kijklijst tile had (`my_pleya.tile[watchlist]`).
class _SeeAllLink extends StatelessWidget {
  const _SeeAllLink({required this.node, required this.onSelect, required this.onNavigate});

  final FocusNode node;
  final VoidCallback onSelect;
  final ValueChanged<TraversalDirection> onNavigate;

  @override
  Widget build(BuildContext context) {
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final ink = Theme.of(context).brightness == Brightness.light ? tk.accent : tk.text;
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
        padding: EdgeInsets.symmetric(horizontal: 12 * pt, vertical: 2 * pt),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              t.myPleya.seeAll,
              style: TextStyle(color: ink, fontSize: TvHig.caption1 * pt, fontWeight: FontWeight.w700),
            ),
            SizedBox(width: 4 * pt),
            Icon(Symbols.chevron_right_rounded, size: 26 * pt, color: ink),
          ],
        ),
      ),
    );
  }
}
