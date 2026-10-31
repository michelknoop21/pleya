part of '../media_detail_screen.dart';

/// What a page holds of the source a title plays from (DEC-XXX "Eén titel over
/// servers heen"). The route is replaced here when the viewer picks another
/// source, so the page stays where it is.
class _UnifiedDetailSource {
  UnifiedMediaRouteContext? route;
  UnifiedTitlePlayback? title;
  bool titleRead = false;

  /// What Play starts on a series page: read ahead, so the button can say
  /// whether it resumes. Null until known.
  UnifiedPlayTarget? onDeckTarget;

  /// The control that changes the source. A node of its own, because the
  /// action row sends DOWN by hand and has to be able to name this stop.
  final FocusNode lineFocus = FocusNode(debugLabel: 'unified_source_line');

  void dispose() => lineFocus.dispose();
}

/// The page's side of one title across its sources. The page keeps showing
/// the main source; [_unifiedTitle] answers what a play does.
extension _MediaDetailUnifiedSource on _MediaDetailScreenState {
  UnifiedMediaRouteContext? get _routeContext => _unifiedSource.route ?? widget.unifiedRouteContext;

  UnifiedTitlePlayback? get _unifiedTitle {
    final state = _unifiedSource;
    if (!state.titleRead) {
      state.titleRead = true;
      state.title = widget.isOffline ? null : unifiedTitleFor(context, _routeContext);
    }
    return state.title;
  }

  /// Starts [item] with the tracks picked on this page (inert when the tech
  /// table describes another item) and refreshes the page afterwards.
  Future<void> _playWithDetailPick(MediaItem item) async {
    final title = _unifiedTitle;
    final target = title == null ? UnifiedPlayTarget(_playedItem(item)) : await title.targetFor(item);
    if (!mounted) return;
    final pick = _detailTrackPickFor(target.item);
    await navigateToVideoPlayerWithRefresh(
      context,
      metadata: target.item,
      preferredAudioTrack: pick.audio,
      preferredSubtitleTrack: pick.subtitle,
      isOffline: widget.isOffline,
      startPosition: target.carriedResume,
      unifiedTitle: title,
      onRefresh: () {
        title?.invalidate();
        unawaited(refreshAfterPlayback(playedItemId: item.id));
      },
    );
  }

  /// What a play of the page's own film starts: the chosen source, which the
  /// page need not show. Episodes listed on the page go through [_unifiedTitle].
  MediaItem _playedItem(MediaItem item) {
    if (!item.isMovie) return item;
    final title = _unifiedTitle;
    if (title != null) return title.movieTarget(item).item;
    final route = _routeContext;
    final page = route == null ? null : parseGlobalKey(route.pageSourceKey)?.ratingKey;
    return page == item.id ? route?.playItem ?? item : item;
  }

  /// Whether Play continues somewhere in [item]: its own position, or one that
  /// lives on another source of this title.
  bool _playResumes(MediaItem item) {
    if (item.isShow) {
      final target = _unifiedSource.onDeckTarget;
      if (target != null) return target.carriedResume != null || (target.item.viewOffsetMs ?? 0) > 0;
      final onDeck = _onDeckEpisode;
      return onDeck != null && (_fresh(onDeck).viewOffsetMs ?? 0) > 0;
    }
    final title = _unifiedTitle;
    if (title == null || !item.isMovie) return (_playedItem(item).viewOffsetMs ?? 0) > 0;
    final target = title.movieTarget(item);
    return target.carriedResume != null || (target.item.viewOffsetMs ?? 0) > 0;
  }

  /// The item a menu on the page acts on: the chosen source. Deleting, a
  /// metadata refresh or a match never land on the main source just because
  /// the page shows it (hoofdstuk 4.6).
  MediaItem _menuItem(MediaItem metadata) {
    final route = _routeContext;
    final page = route == null ? null : parseGlobalKey(route.pageSourceKey)?.ratingKey;
    return page == metadata.id ? route?.playItem ?? metadata : metadata;
  }

  /// A series moves on across its sources: the page's play target follows the
  /// source that is furthest along, and Play knows whether it resumes.
  Future<void> _syncUnifiedOnDeck() async {
    final title = _unifiedTitle;
    if (title == null || !_metadata.isShow) return;
    final own = _onDeckEpisode;
    final across = await title.onDeckAcross(own);
    final target = across == null ? null : await title.targetFor(across);
    if (!mounted || _onDeckEpisode?.globalKey != own?.globalKey) return;
    setStateIfMounted(() {
      _onDeckEpisode = across;
      _unifiedSource.onDeckTarget = target;
    });
  }

  /// The chosen copy was deleted, from the page's own menu or elsewhere: the
  /// page stops playing from it and stops naming it. Answers whether [event]
  /// was about that copy, which the page does not otherwise show.
  bool _dropDeletedSource(DeletionEvent event) {
    final route = _routeContext;
    if (route == null || event.isDownloadOnly) return false;
    if (event.globalKey != route.sourceKey || route.sourceKey == route.pageSourceKey) return false;
    final next = route.withoutSource(route.sourceKey);
    setStateIfMounted(() {
      final state = _unifiedSource;
      state.route = next;
      state.title = next.titleSources.length < 2 ? null : state.title?.withRoute(next);
      state.titleRead = true;
      state.onDeckTarget = null;
    });
    unawaited(_syncUnifiedOnDeck());
    return true;
  }

  /// DOWN from the action row: the source line is the next stop, when the page
  /// has one. Without it a remote never reaches "[ Wijzigen ]".
  bool _focusUnifiedSourceLine() {
    final node = _unifiedSource.lineFocus;
    if (node.context == null || !node.canRequestFocus) return false;
    node.requestFocus();
    return true;
  }

  /// Hoofdstuk 15's "[ Wijzigen ]". The page stays when only what Play starts
  /// changes: nothing reloads, nothing moves, and focus stays on the control
  /// the viewer pressed. Only the tracks follow the new source.
  Future<void> _changeUnifiedSource(BuildContext from, {bool pageFailed = false}) async {
    final change = widget.onChangeSource;
    final route = _routeContext;
    if (change == null || route == null) return;
    final next = await change(from, route, pageFailed: pageFailed);
    if (next == null || !mounted) return;
    setStateIfMounted(() {
      final state = _unifiedSource;
      state.route = next;
      state.title = state.title?.withRoute(next) ?? (widget.isOffline ? null : unifiedTitleFor(context, next));
      state.onDeckTarget = null;
    });
    unawaited(_syncUnifiedOnDeck());
  }

  /// Hoofdstuk 15's `Bron: NAS • Films 4K   [ Wijzigen ]`.
  ///
  /// Rendered only when the page was reached through a unified group that
  /// actually has more than one source — a single-source title has nothing to
  /// change to, and a line saying so would be chrome. Returns a zero-size box
  /// otherwise, which is every entry point that is not a unified activation.
  ///
  /// [card] is the iPhone look (`.src` in D-01, DEC-140): a full-width tile
  /// with the whole tile as the change target. TV and the other layouts keep
  /// the caption plus chip.
  Widget _buildUnifiedSourceLine({bool card = false}) {
    final routeContext = _routeContext;
    if (routeContext == null || !routeContext.hasAlternativeSources) return const SizedBox.shrink();
    // The card sits on the always-dark phone detail page; a Builder gives it
    // the context under that page's theme instead of the State's (app) one.
    if (card) return Builder(builder: (context) => _buildUnifiedSourceCard(context, routeContext));

    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final mono = tokens(context);
    final shown = routeContext.playItem ?? _metadata;
    final parts = [
      shown.serverName ?? routeContext.sourceKey.split(':').first,
      if ((shown.libraryTitle ?? '').trim().isNotEmpty) shown.libraryTitle!.trim(),
    ];
    final label = t.sourcePicker.sourceLabel(source: parts.join(' • '));
    // DENS1: HIG Caption 2 (23 pt), the tvOS minimum; `13 * scaleOf` was 20.
    final fontSize = isTv ? TvHig.caption2 * TvHig.of(context) : 13.0;
    final canChange = widget.onChangeSource != null;

    return Padding(
      padding: EdgeInsets.only(top: isTv ? 10 * tvScale : 12),
      child: Row(
        mainAxisSize: .min,
        children: [
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(color: mono.textMuted, fontSize: fontSize, fontWeight: .w500),
            ),
          ),
          if (canChange) ...[
            SizedBox(width: isTv ? 10 * tvScale : 12),
            AutomationNode(
              id: AutomationIds.mediaDetailSource,
              role: 'button',
              state: () => {'server': parts.first},
              focusNode: _unifiedSource.lineFocus,
              child: FocusableWrapper(
                focusNode: _unifiedSource.lineFocus,
                borderRadius: 999,
                disableScale: true,
                semanticLabel: t.sourcePicker.change,
                onNavigateUp: _playButtonFocusNode.requestFocus,
                onNavigateDown: _focusBelowSourceLine,
                onSelect: () {
                  // The picker opens a route; suppress this press's key-up so it
                  // does not land on whatever takes focus next.
                  SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
                  unawaited(_changeUnifiedSource(context));
                },
                child: Container(
                  padding: EdgeInsets.symmetric(horizontal: isTv ? 14 * tvScale : 14, vertical: isTv ? 6 * tvScale : 6),
                  decoration: BoxDecoration(
                    color: mono.text.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(999),
                  ),
                  child: Text(
                    t.sourcePicker.change,
                    style: TextStyle(color: mono.text, fontSize: fontSize, fontWeight: .w700),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildUnifiedSourceCard(BuildContext context, UnifiedMediaRouteContext routeContext) {
    final onSurface = Theme.of(context).colorScheme.onSurface;
    final shown = routeContext.playItem ?? _metadata;
    final parts = [
      shown.serverName ?? routeContext.sourceKey.split(':').first,
      if ((shown.libraryTitle ?? '').trim().isNotEmpty) shown.libraryTitle!.trim(),
    ];
    final canChange = widget.onChangeSource != null;
    final tile = Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 13),
      decoration: BoxDecoration(color: onSurface.withValues(alpha: 0.08), borderRadius: BorderRadius.circular(12)),
      child: Row(
        children: [
          Text(t.sourcePicker.source, style: TextStyle(color: onSurface.withValues(alpha: 0.70), fontSize: 15)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              parts.join(' · '),
              maxLines: 1,
              overflow: .ellipsis,
              style: TextStyle(color: onSurface, fontSize: 15),
            ),
          ),
          if (canChange)
            Text(
              t.sourcePicker.change,
              style: TextStyle(color: onSurface, fontSize: 15, fontWeight: .w700),
            ),
        ],
      ),
    );
    return Padding(
      padding: const EdgeInsets.only(top: 20),
      child: AutomationNode(
        id: AutomationIds.mediaDetailSource,
        role: 'button',
        state: () => {'server': parts.first},
        child: !canChange
            ? tile
            : FocusableWrapper(
                borderRadius: 12,
                disableScale: true,
                semanticLabel: t.sourcePicker.change,
                onSelect: () => unawaited(_changeUnifiedSource(context)),
                // FocusableWrapper only takes keys; this row is the phone's.
                child: GestureDetector(
                  behavior: .opaque,
                  onTap: () => unawaited(_changeUnifiedSource(context)),
                  child: tile,
                ),
              ),
      ),
    );
  }

  /// The height [_buildUnifiedSourceLine] actually renders, so the two hero
  /// layouts in media_detail_screen.dart can reserve room for it before
  /// laying out their Column.
  ///
  /// Measures the real text line height via [TextPainter] against the same
  /// ambient [DefaultTextStyle] `_buildUnifiedSourceLine`'s `Text` widgets
  /// resolve against (fontFamily, any theme-level `height` multiplier, text
  /// scaling) instead of guessing a line-height multiplier — a guessed
  /// constant here and the real render can only drift apart; a measurement
  /// against the same style authority can't. The chip is wrapped in a
  /// [FocusableWrapper], whose ring decoration always carries a
  /// [FocusTheme.focusBorderWidth]-wide border (transparent when unfocused,
  /// but still there) — `Container`/`AnimatedContainer` folds a decoration's
  /// border into its own effective padding, so the wrapper is
  /// `2 * FocusTheme.focusBorderWidth` taller than its child, unscaled by
  /// `tvScale` since the border itself never scales.
  double _unifiedSourceLineHeight(BuildContext context) {
    final routeContext = _routeContext;
    if (routeContext == null || !routeContext.hasAlternativeSources) return 0.0;
    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final fontSize = isTv ? TvHig.caption2 * TvHig.of(context) : 13.0;
    final topPadding = isTv ? 10 * tvScale : 12.0;
    final chipVerticalPadding = isTv ? 6 * tvScale : 6.0;
    final baseStyle = DefaultTextStyle.of(context).style;
    final textPainter = TextPainter(
      text: TextSpan(
        text: 'Mg',
        style: baseStyle.copyWith(fontSize: fontSize, fontWeight: FontWeight.w700),
      ),
      textDirection: Directionality.of(context),
      textScaler: MediaQuery.textScalerOf(context),
    )..layout();
    final textLineHeight = textPainter.height;
    final rowHeight = widget.onChangeSource != null
        ? (chipVerticalPadding * 2) + textLineHeight + (2 * FocusTheme.focusBorderWidth)
        : textLineHeight;
    return topPadding + rowHeight;
  }
}
