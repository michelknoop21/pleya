part of 'tv_catalog_card_grid.dart';

/// Scroll and row alignment of [TvCatalogCardGridState]: where the offset goes
/// when the focus moves, and when the next page is asked for.
extension _GridScroll on TvCatalogCardGridState {
  /// A slow source can insert sorted titles before the card being read. The
  /// node survives, but its row does not: leaving the offset unchanged moves
  /// that same focused title out of view (CAT-SCROLL429). Preserve its viewport
  /// row, without reordering data or stealing focus back from a control.
  void _preserveFocusedRow({required List<String> previous}) {
    if (!widget.rowAligned || !_controller.hasClients) return;
    final id = _focusedId;
    if (id == null || !(_nodes[id]?.hasFocus ?? false)) return;
    final oldIndex = previous.indexOf(id);
    final newIndex = widget.itemIds.indexOf(id);
    final grid = _grid;
    if (grid == null || oldIndex < 0 || newIndex < 0 || oldIndex == newIndex) return;
    final rowDelta = newIndex ~/ grid.columns - oldIndex ~/ grid.columns;
    if (rowDelta == 0) return;
    final measured = _measuredRow(grid.columns, itemIds: previous);
    if (measured == null) return;
    final offset = _controller.offset;
    final wasScrolling = _controller.position.isScrollingNotifier.value;
    final center = _artworkCenter;
    if (center != null) center.value = math.max(0, center.value + rowDelta);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _focusedId != id || !(_nodes[id]?.hasFocus ?? false)) return;
      if (widget.itemIds.indexOf(id) != newIndex || _grid?.columns != grid.columns) return;
      final position = _controller.position;
      if (!position.hasContentDimensions) return;
      if (wasScrolling) {
        // The old animation still targets the old row; replace it with the
        // ordinary row alignment, rather than snapping mid-gesture.
        _alignToRow(newIndex, grid, _cardHeight!);
      } else {
        position.jumpTo((offset + rowDelta * measured.pitch).clamp(position.minScrollExtent, position.maxScrollExtent));
      }
    });
  }

  /// Keeps the whole of the focused card — ring included — inside the viewport
  /// after directional traversal has had its say (CAT10, and CAT8 at the other
  /// edge).
  ///
  /// The grid does not claim UP and DOWN between its own rows: [_buildCell]
  /// binds `onNavigateUp` only on the first row and `onNavigateDown` only on
  /// the last, so every move *within* the grid falls through to Flutter's
  /// `DirectionalFocusAction` and ends in
  /// `Scrollable.ensureVisible(alignmentPolicy: keepVisibleAtStart)`. That
  /// reveals the card's **resting** box, and the resting box is not what gets
  /// drawn: [FocusableWrapper] scales the card about its centre, so the ring
  /// reaches [TvCatalogGrid.focusHeadroom] beyond the box at both ends.
  ///
  /// [TvCatalogGrid.scrollPadding] reserves exactly that headroom, which is why
  /// the first row is whole at rest — and only at rest. `keepVisibleAtStart`
  /// puts the resting box flush against the viewport, so it scrolls the
  /// reservation itself out of view and the `SingleChildScrollView` clips what
  /// was standing in it. Measured on the tvOS simulator on 7 September 2026:
  /// at rest the top edge of the ring sits at y=445 of 2160 and after DOWN then
  /// UP it is gone, with the rest of the ring 30 physical pixels higher.
  ///
  /// So rather than reveal a different box, this states the range the offset
  /// may be in for the focused row and clamps it there. The upper bound is
  /// where the ring meets the top edge, the lower bound where it meets the
  /// bottom one; a card taller than the viewport keeps the top. It runs after
  /// the frame because that is when traversal has already moved the position —
  /// correcting before it would be overwritten by it.
  void _keepFocusRingVisible(int index) {
    final grid = _grid;
    final cardHeight = _cardHeight;
    if (grid == null || cardHeight == null) return;
    if (widget.rowAligned) {
      _alignToRow(index, grid, cardHeight);
      return;
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients) return;
      final position = _controller.position;
      if (!position.hasViewportDimension || !position.hasContentDimensions) return;

      final growth = TvCatalogGrid.focusHeadroom(cardHeight: cardHeight, focusScale: widget.focusScale);
      // The row's box inside the scroll content. The top padding is that same
      // growth, so on row zero the two cancel and the bound is simply 0.
      final rowTop = growth + (index ~/ grid.columns) * (cardHeight + grid.rowGutter);

      final upper = rowTop - growth;
      final lower = rowTop + cardHeight + growth - position.viewportDimension;
      final target = (position.pixels.clamp(math.min(lower, upper), upper) as double).clamp(
        position.minScrollExtent,
        position.maxScrollExtent,
      );

      if ((target - position.pixels).abs() < 0.5) return;
      position.jumpTo(target);
    });
  }

  /// The [TvCatalogCardGrid.fitTwoRows] card width: two whole rows with room,
  /// narrowed further by the library-density setting.
  ///
  /// Under a fixed heading (every grid but the folded Films/Series page) it
  /// does not go below [minFitFraction] of the natural width: on the Apple TV
  /// canvas two rows there would mean a card of about 86 wide, where a status
  /// label is cut off and a two-word title breaks over two lines (Michel,
  /// Aanvragen, 21 October 2026). Such a page shows one whole row and part of
  /// the next instead.
  double? _fitWidth(double height, TvCatalogGrid natural) {
    final fit = tvCatalogTwoRowCardWidth(
      viewport: height,
      gutter: natural.gutter,
      bottomMargin: natural.bottomSafeMargin,
      focusScale: widget.focusScale,
      cardHeight: widget.cardHeight,
    );
    if (fit == null) return null;
    final density =
        widget.fitScale ??
        tvCatalogDensityScale(
          SettingsService.instanceOrNull?.read(SettingsService.libraryDensity) ?? LibraryDensity.defaultValue,
        );
    final width = fit * density;
    if (widget.rowAligned) return width;
    return math.max(width, natural.cardWidth * TvCatalogCardGrid.minFitFraction);
  }

  /// [TvCatalogCardGrid.rowAligned]'s half of [_keepFocusRingVisible].
  ///
  /// Always settles the position, even when it is already right: the card's
  /// own `FocusableWrapper` starts a scroll of its own on focus (centring the
  /// card), and that one runs first. Only an explicit move from here replaces
  /// it, so "nothing to do" still has to say so.
  void _alignToRow(int index, TvCatalogGrid grid, double cardHeight) {
    final id = widget.itemIds[index];
    final duration = reduceMotion(context, TvCatalogCardGrid.rowScrollDuration);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_controller.hasClients || _focusedId != id || !(_nodes[id]?.hasFocus ?? false)) return;
      if (widget.itemIds.indexOf(id) != index) return;
      final position = _controller.position;
      if (!position.hasViewportDimension || !position.hasContentDimensions) return;
      // The rows as laid out, not as budgeted: [TvCatalogLayout.cardHeight]
      // rounds the meta line up and the card does not, so the budget runs a
      // pixel long per row and an offset of `n` budgeted rows drifts off the
      // row line further down the catalogue.
      final measured = _measuredRow(grid.columns) ?? (height: cardHeight, pitch: cardHeight + grid.rowGutter);
      final row = index ~/ grid.columns;
      final lastRow = (widget.itemIds.length - 1) ~/ grid.columns;
      // A full-bleed page fills the window with whole rows, so the footer under
      // the last one would stay out of reach. It carries the notice that a
      // library did not answer, so the last row brings it into view.
      final target = grid.topInset != null && row == lastRow && widget.footer != null
          ? position.maxScrollExtent
          : tvCatalogRowAlignedOffset(
              row: row,
              pixels: position.pixels,
              viewport: position.viewportDimension,
              cardHeight: measured.height,
              gutter: measured.pitch - measured.height,
              growth: grid.firstRowOffset(cardHeight: cardHeight, focusScale: widget.focusScale),
              minScrollExtent: position.minScrollExtent,
              maxScrollExtent: position.maxScrollExtent,
            );
      if (duration == Duration.zero || (target - position.pixels).abs() < 0.5) {
        position.jumpTo(target);
      } else {
        position.animateTo(target, duration: duration, curve: Curves.easeOutCubic);
      }
    });
  }

  /// The first card's laid-out height and the distance from the first row to
  /// the second, or null while there is no second row to measure against.
  ({double height, double pitch})? _measuredRow(int columns, {List<String>? itemIds}) {
    final ids = itemIds ?? widget.itemIds;
    if (ids.length <= columns) return null;
    final first = _nodes[ids.first]?.context?.findRenderObject();
    final below = _nodes[ids[columns]]?.context?.findRenderObject();
    if (first is! RenderBox || below is! RenderBox || !first.hasSize || !below.hasSize) return null;
    // Measured inside this grid, not on the screen: the TV shell draws the
    // whole app through a root scale (DEC-028), and a global distance would
    // come back 1.85 times too long.
    final grid = context.findRenderObject();
    if (grid == null) return null;
    final pitch =
        below.localToGlobal(Offset.zero, ancestor: grid).dy - first.localToGlobal(Offset.zero, ancestor: grid).dy;
    if (pitch <= 0) return null;
    return (height: first.size.height, pitch: pitch);
  }

  /// UP or DOWN to the card in the same column of the neighbouring row, for
  /// [TvCatalogCardGrid.rowAligned]. A shorter last row takes its last card.
  void _moveToRow(int index, int columns, int direction) {
    final ids = widget.itemIds;
    if (ids.isEmpty) return;
    final target = (index + direction * columns).clamp(0, ids.length - 1);
    if (target == index) return;
    final node = _nodes[ids[target]];
    if (node != null && node.canRequestFocus) requestFocusClearingDirectionalHistory(node);
  }

  /// Asks for the next page once the focus is within
  /// [TvCatalogCardGrid.loadMoreRowThreshold] rows of the end (P11).
  ///
  /// The trigger used to be DOWN on the last row and nothing else — no scroll
  /// listener, no threshold, no background prefetch — so the viewer had to
  /// navigate into the end of the loaded set and then wait, every page, which
  /// is exactly the stall that was reported.
  ///
  /// Focus rather than scroll offset: on this platform focus *is* the cursor.
  /// And it is a threshold rather than a replacement of the DOWN trigger —
  /// that one still stands, one row further down, for the case where `hasMore`
  /// only became true after the focus had already settled at the bottom.
  void _maybeLoadMore(int index) {
    if (!widget.hasMore || widget.isLoadingMore) return;
    final grid = _grid;
    if (grid == null || grid.columns <= 0 || widget.itemIds.isEmpty) return;
    final rows = (widget.itemIds.length / grid.columns).ceil();
    final row = index ~/ grid.columns;
    if (rows - row > TvCatalogCardGrid.loadMoreRowThreshold) return;
    widget.onLoadMore();
  }
}

/// Node bookkeeping and row layout of [TvCatalogCardGridState].
extension _GridWiring on TvCatalogCardGridState {
  /// Moves the poster window to [row] once the focus has walked far enough.
  void _recenterArtwork(int row) {
    final center = _artworkCenter;
    if (center != null && tvCatalogArtworkShouldRecenter(focusedRow: row, centerRow: center.value)) {
      center.value = row;
    }
  }

  /// Drops nodes for items that are gone, and rescues focus if one of them had
  /// it (hoofdstuk 7.6: "kaart verdwijnt door filter/verwijdering →
  /// eerstvolgende buur").
  ///
  /// "Had it" means the ring was on that card at this moment, which is a
  /// narrower thing than [_focusedId]. That field is a *memory*: it is seeded
  /// from [TvCatalogCardGrid.initialFocusedId] before anything has been focused
  /// at all, and it is never cleared when the focus walks out of the grid. So
  /// the replacement is always recorded, because the next [focusGrid] has to
  /// land somewhere sensible, but the focus is only moved when the grid is
  /// holding it.
  ///
  /// CAT17 is what the wider reading cost. A sort change re-pages the catalog,
  /// so the remembered card is routinely absent from the new page one, and the
  /// rescue fired while the viewer was standing in the catalog rail, one frame
  /// after `_withLauncherFocusRestore` had put the ring back on Sortering. The
  /// ring ended on a grid card with the rail still open, and from there the
  /// remote had no way back into it.
  void _reconcileNodes({required List<String> previous}) {
    final live = widget.itemIds.toSet();
    final removed = _nodes.keys.where((id) => !live.contains(id)).toList();
    if (removed.isEmpty) return;

    final focusedId = _focusedId;
    final losesFocus = focusedId != null && removed.contains(focusedId);
    // Read before the dispose loop, while the node is still attached: after it
    // there is nothing left to ask.
    final heldTheFocus = losesFocus && (_nodes[focusedId]?.hasFocus ?? false);
    // Measured against the *old* list: the neighbour a user expects is the card
    // that was next to theirs before the update, and the new list no longer
    // contains the position to measure from.
    final oldIndex = losesFocus ? previous.indexOf(focusedId) : -1;

    for (final id in removed) {
      _nodes.remove(id)?.dispose();
    }
    if (!losesFocus) return;

    final successor = widget.successorOf?.call(focusedId);
    final replacement = successor != null && live.contains(successor)
        ? successor
        : _nearestSurvivor(previous: previous, from: oldIndex);
    _focusedId = replacement;
    if (!heldTheFocus) return;
    // After the frame that removes the card: the replacement's node may not be
    // attached yet on this one.
    //
    // The supersede check covers the frame in between. It is deliberately not
    // defended against two reconciles racing: a callback scheduled from
    // `didUpdateWidget` runs at the end of that same frame, so a later update
    // cannot get in front of it, and a test written for that race passes
    // either way. What it does catch is the focus moving inside the grid
    // between this build and the end of the frame, which `_buildCell` records
    // by writing `_focusedId`. A rescue whose own replacement is no longer the
    // answer has been overtaken and must not fire.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _focusedId != replacement) return;
      final node = replacement == null ? null : _nodes[replacement];
      if (node != null && node.canRequestFocus) {
        requestFocusClearingDirectionalHistory(node);
      } else {
        // Nothing survived — an empty result after a filter change. Focus goes
        // back up to the controls, which is the only thing left to operate.
        (widget.onEmptied ?? widget.onExitTop)?.call();
      }
    });
  }

  /// The nearest still-present item to position [from] in the old list.
  ///
  /// Walks outward, forward first: a tie means the user filtered away a card
  /// with survivors on both sides, and the one *after* it is the one they had
  /// not reached yet — the same tie-break `nextFocusAfterAvailabilityChange`
  /// uses in the source picker, for the same reason.
  String? _nearestSurvivor({required List<String> previous, required int from}) {
    if (from < 0) return widget.itemIds.firstOrNull;
    final live = widget.itemIds.toSet();
    for (var distance = 1; distance < previous.length; distance++) {
      final after = from + distance;
      if (after < previous.length && live.contains(previous[after])) return previous[after];
      final before = from - distance;
      if (before >= 0 && live.contains(previous[before])) return previous[before];
    }
    return widget.itemIds.firstOrNull;
  }

  TvCatalogGrid _resolveGrid(double width, double height, double scale) {
    final natural = TvCatalogGrid.forWidth(width, scale: scale, reservedLeading: widget.reservedLeading);
    return TvCatalogGrid.forWidth(
      width,
      scale: scale,
      reservedLeading: widget.reservedLeading,
      maxCardWidth: widget.fitTwoRows
          ? _fitWidth(height, natural)
          : widget.fitScale == null
          ? null
          : natural.cardWidth * widget.fitScale!,
    );
  }

  Widget _buildRow({required TvCatalogGrid grid, required int start, required int end, required bool isFirstRow}) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (var index = start; index < end; index++) ...[
          if (index > start) SizedBox(width: grid.gutter),
          _buildCell(grid: grid, index: index, isFirstRow: isFirstRow),
        ],
        // Keeps the last row left-aligned on the same rhythm as a full one
        // instead of stretching four cards across six columns.
        if (end - start < grid.columns)
          SizedBox(width: (grid.cardWidth + grid.gutter) * (grid.columns - (end - start)) - grid.gutter),
      ],
    );
  }
}
