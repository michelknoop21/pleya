part of 'tv_my_pleya_screen.dart';

/// `JE KIJKLIJST` with `Bekijk alles`, and the posters under it (northstar 01
/// and 02). The same titles and the same rule for what a poster opens as the
/// iPhone rail (`my_pleya_shared.dart`); the poster itself is the kijklijst's
/// catalogue card, so title, year and focus lift match the full kijklijst.
class _WatchlistBlock extends StatefulWidget {
  const _WatchlistBlock({
    required this.entries,
    required this.provider,
    required this.map,
    required this.seeAllNode,
    required this.onOpenAll,
    required this.onSelectedKeyChanged,
  });

  final List<WatchlistEntry> entries;
  final WatchlistProvider provider;
  final _HubFocusMap map;
  final FocusNode seeAllNode;
  final VoidCallback onOpenAll;
  final ValueChanged<String> onSelectedKeyChanged;

  /// Poster width and the room between two posters, in points.
  static const double _posterPt = 153;
  static const double _posterGapPt = 31;

  /// Lines the title reserves under each poster: two, so a focused title such
  /// as "Tears of Steel" reads whole, and every card the same height whether
  /// it needs them or not (no card grows or shifts on focus).
  static const int _titleLines = 2;

  @override
  State<_WatchlistBlock> createState() => _WatchlistBlockState();
}

class _WatchlistBlockState extends State<_WatchlistBlock> {
  final ScrollController _controller = ScrollController();

  /// Card width and card plus gap, in logical pixels, from the last build.
  double _pitch = 0;
  String? _selectedKey;
  int _updateRequest = 0;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  void didUpdateWidget(_WatchlistBlock oldWidget) {
    super.didUpdateWidget(oldWidget);
    final selected = _selectedKey;
    if (selected == null) return;
    final previousFocus = oldWidget.map.nodes.nodeFor(selected);
    final heldFocus = previousFocus?.hasFocus == true;
    final keys = widget.entries.map(_posterKey).toList();
    var index = keys.indexOf(selected);
    if (index < 0) {
      final oldIndex = oldWidget.entries.indexWhere((entry) => _posterKey(entry) == selected);
      index = keys.isEmpty ? -1 : oldIndex.clamp(0, keys.length - 1);
      _selectedKey = index < 0 ? null : keys[index];
      if (_selectedKey != null) widget.onSelectedKeyChanged(_selectedKey!);
    }
    final request = ++_updateRequest;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || request != _updateRequest) return;
      final target = widget.entries.indexWhere((entry) => _posterKey(entry) == _selectedKey);
      if (target >= 0) _reveal(target, animate: false);
      FocusManager.instance.applyFocusChangesIfNeeded();
      final currentFocus = FocusManager.instance.primaryFocus;
      final focusMoved = currentFocus != null && currentFocus is! FocusScopeNode && currentFocus != previousFocus;
      if (heldFocus && !focusMoved) _focus(widget.map, _selectedKey ?? _seeAllKey);
    });
  }

  void _reveal(int index, {bool animate = true}) {
    if (_pitch <= 0) return;
    scrollCarouselToLeading(
      _controller,
      index * _pitch,
      animate: animate,
      duration: reduceMotion(context, const Duration(milliseconds: 150)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final entries = widget.entries;
    final provider = widget.provider;
    final map = widget.map;
    final onOpenAll = widget.onOpenAll;
    final tk = tokens(context);
    final pt = TvHig.of(context);
    final scale = TvLayoutConstants.scaleOf(context);
    final inset = TvCatalogLayout.cardContentInset(scale);
    final posterWidth = _WatchlistBlock._posterPt * pt;
    final cardWidth = posterWidth + inset * 2;
    final cardHeight = TvCatalogLayout.cardHeight(cardWidth, scale, titleLines: _WatchlistBlock._titleLines);
    final growth = TvCatalogGrid.focusHeadroom(cardHeight: cardHeight, focusScale: FocusTheme.fullCardFocusScale);
    final gap = (_WatchlistBlock._posterGapPt * pt - inset * 2).clamp(0.0, double.infinity);
    _pitch = cardWidth + gap;
    void go(String key, TraversalDirection direction) => _focus(map, map.next(key, direction));

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _GroupLabel(
          t.settingsStudio.yourWatchlist,
          trailing: _SeeAllLink(
            node: widget.seeAllNode,
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
              child: LayoutBuilder(
                builder: (context, constraints) => ListView.separated(
                  controller: _controller,
                  scrollDirection: Axis.horizontal,
                  clipBehavior: Clip.none,
                  padding: EdgeInsets.only(right: carouselTrailingSpace(constraints.maxWidth, 0, cardWidth)),
                  // shortcut: this preview is capped at twelve, use virtualized focus if it becomes unbounded.
                  cacheExtent: _pitch * kMyPleyaWatchlistMax,
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
                      state: () => <String, Object?>{
                        'title': entry.item.displayTitle,
                        'playable': target != null,
                        'anchored':
                            _selectedKey == key &&
                            _controller.hasClients &&
                            (_controller.offset - index * _pitch).abs() < 0.75,
                      },
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
                        titleLines: _WatchlistBlock._titleLines,
                        meta: entry.item.year == null ? '' : '${entry.item.year}',
                        semanticLabel: tvWatchlistSemanticLabel(entry),
                        focusNode: node,
                        onFocusChange: (focused) {
                          if (focused) {
                            _updateRequest++;
                            _selectedKey = key;
                            widget.onSelectedKeyChanged(key);
                            _reveal(index);
                          }
                        },
                        onSelect: target == null
                            ? onOpenAll
                            : () => unawaited(
                                navigateToMediaItem(context, target, restoreTarget: TvFocusRestoreTarget(itemId: key)),
                              ),
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
