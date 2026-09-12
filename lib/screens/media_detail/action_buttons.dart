part of '../media_detail_screen.dart';

extension _MediaDetailActionButtons on _MediaDetailScreenState {
  /// Resolves what "play" means for [metadata] (on-deck episode for a show,
  /// first episode for a season, the item itself otherwise) and starts
  /// playback. Shared by the TV/legacy action row and the phone primary button.
  Future<void> _handlePlayPressed(MediaItem metadata) async {
    // For TV shows, play the OnDeck episode if available
    // Otherwise, play the first episode of the first season
    if (metadata.isShow) {
      if (_onDeckEpisode != null) {
        appLogger.d('Playing on deck episode: ${_onDeckEpisode!.title}');
        final playedId = _onDeckEpisode!.id;
        await navigateToVideoPlayerWithRefresh(
          context,
          metadata: _onDeckEpisode!,
          isOffline: widget.isOffline,
          onRefresh: () => unawaited(refreshAfterPlayback(playedItemId: playedId)),
        );
      } else {
        // No on deck episode, fetch first episode of first season
        await _playFirstEpisode();
      }
    } else if (metadata.isSeason) {
      // For seasons, play the first episode
      if (_episodes.isNotEmpty) {
        final playedId = _episodes.first.id;
        await navigateToVideoPlayerWithRefresh(
          context,
          metadata: _episodes.first,
          isOffline: widget.isOffline,
          onRefresh: () => unawaited(refreshAfterPlayback(playedItemId: playedId)),
        );
      } else {
        await _playFirstEpisode();
      }
    } else {
      appLogger.d('Playing: ${metadata.title}');
      // For movies or episodes, play directly
      final playedId = metadata.id;
      await navigateToVideoPlayerWithRefresh(
        context,
        metadata: metadata,
        isOffline: widget.isOffline,
        onRefresh: () => unawaited(refreshAfterPlayback(playedItemId: playedId)),
      );
    }
  }

  Widget _buildActionButtons(MediaItem metadata) {
    final isTv = PlatformDetector.isTV();
    final tvScale = TvLayoutConstants.scaleOf(context);
    final actionSize = isTv ? _tvDetailActionSize * tvScale : 48.0;
    final playButtonLabel = _getPlayButtonLabel(metadata);
    final playIconSize = isTv ? 22 * tvScale : 20.0;
    final playTextStyle = TextStyle(fontSize: isTv ? 17 * tvScale : 16, fontWeight: .w700);
    final playButtonIcon = AppIcon(_getPlayButtonIcon(metadata), fill: 1, size: playIconSize);

    Future<void> onPlayPressed() => _handlePlayPressed(metadata);

    final primaryTrailer = _getPrimaryTrailer();

    final isKeyboardMode = InputModeTracker.isKeyboardMode(context);
    final colorScheme = Theme.of(context).colorScheme;

    // In keyboard/d-pad mode, focused buttons get a prominent style.
    // overlayColor is set to transparent to prevent the Material focus
    // overlay from dimming the background color we set.
    final focusBg = colorScheme.inverseSurface;
    final focusFg = colorScheme.onInverseSurface;
    final tonalBg = colorScheme.secondaryContainer;
    final idleBg = isTv ? tonalBg.withValues(alpha: 0.38) : tonalBg;
    final tonalFg = colorScheme.onSecondaryContainer;
    final noOverlay = WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.focused)) return Colors.transparent;
      return null; // default for other states
    });

    ButtonStyle actionButtonStyle({Color? foregroundColor, EdgeInsetsGeometry? padding, bool showFocus = false}) {
      if (!isKeyboardMode && !isTv) {
        if (padding != null) {
          return FilledButton.styleFrom(padding: padding);
        }
        return IconButton.styleFrom(
          minimumSize: const Size(48, 48),
          maximumSize: const Size(48, 48),
          foregroundColor: foregroundColor,
        );
      }

      return ButtonStyle(
        padding: padding != null ? WidgetStatePropertyAll(padding) : null,
        minimumSize: WidgetStatePropertyAll(padding == null ? Size.square(actionSize) : Size(0, actionSize)),
        maximumSize: padding == null ? WidgetStatePropertyAll(Size.square(actionSize)) : null,
        fixedSize: padding == null ? WidgetStatePropertyAll(Size.square(actionSize)) : null,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        visualDensity: VisualDensity.compact,
        overlayColor: noOverlay,
        backgroundColor: WidgetStatePropertyAll(showFocus ? focusBg : idleBg),
        foregroundColor: WidgetStatePropertyAll(showFocus ? focusFg : foregroundColor ?? tonalFg),
      );
    }

    // Plays the resolved trailer. Shared by the row's trailer button and the
    // ⋮ menu item so the trailer stays reachable when the row hides its button.
    final VoidCallback? onPlayTrailer = primaryTrailer == null
        ? null
        : () => unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer));

    final gap = isTv ? 8.0 * tvScale : 12.0;

    // Pressable adds the press-down scale; the buttons below keep owning the
    // tap (they win the gesture arena as the deeper recognizer).
    Widget playButton(FocusableActionBuildState state) {
      return Pressable(
        onTap: onPlayPressed,
        child: SizedBox(
          height: actionSize,
          child: FilledButton(
            onPressed: onPlayPressed,
            style: actionButtonStyle(
              showFocus: state.showFocus,
              padding: .symmetric(horizontal: isTv ? 17 * tvScale : 16, vertical: isTv ? 9 * tvScale : 0),
            ),
            child: playButtonLabel.isNotEmpty
                ? Row(
                    mainAxisSize: .min,
                    children: [
                      playButtonIcon,
                      SizedBox(width: isTv ? 7 * tvScale : 8),
                      Text(playButtonLabel, style: playTextStyle),
                    ],
                  )
                : playButtonIcon,
          ),
        ),
      );
    }

    Widget iconActionButton(
      FocusableActionBuildState state, {
      required Widget icon,
      required VoidCallback? onPressed,
      String? tooltip,
      Color? foregroundColor,
    }) {
      return Pressable(
        onTap: onPressed,
        child: IconButton.filledTonal(
          onPressed: onPressed,
          icon: icon,
          tooltip: tooltip,
          iconSize: isTv ? 21 * tvScale : 20,
          style: actionButtonStyle(foregroundColor: foregroundColor, showFocus: state.showFocus),
        ),
      );
    }

    final playAction = FocusableAction(
      debugLabel: 'detail_play',
      focusNode: _playButtonFocusNode,
      autofocus: isKeyboardMode,
      onPressed: onPlayPressed,
      builder: (context, state) => playButton(state),
    );

    final trailerAction = primaryTrailer == null
        ? null
        : FocusableAction(
            debugLabel: 'detail_trailer',
            onPressed: onPlayTrailer,
            builder: (context, state) => iconActionButton(
              state,
              onPressed: onPlayTrailer,
              icon: const AppIcon(Symbols.theaters_rounded, fill: 1),
              tooltip: t.tooltips.playTrailer,
            ),
          );

    final shuffleAction = (metadata.isShow || metadata.isSeason)
        ? FocusableAction(
            debugLabel: 'detail_shuffle',
            onPressed: () async {
              await _handleShufflePlayWithQueue(context, metadata);
            },
            builder: (context, state) => iconActionButton(
              state,
              onPressed: () async {
                await _handleShufflePlayWithQueue(context, metadata);
              },
              icon: const AppIcon(Symbols.shuffle_rounded, fill: 1),
              tooltip: t.tooltips.shufflePlay,
            ),
          )
        : null;

    final downloadAction = !widget.isOffline && !PlatformDetector.isAppleTV()
        ? FocusableAction(
            debugLabel: 'detail_download',
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
            builder: (context, state) =>
                _buildDownloadButton(metadata, actionButtonStyle, tvScale, showFocus: state.showFocus),
          )
        : null;

    final watchedAction = FocusableAction(
      debugLabel: 'detail_watched',
      onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
      builder: (context, state) =>
          _buildWatchedToggleButton(metadata, actionButtonStyle, tvScale, showFocus: state.showFocus),
    );

    void showMoreActions() => _contextMenuKey.currentState?.showContextMenu(context);

    final moreActionsAction = widget.isOffline
        ? null
        : FocusableAction(
            debugLabel: 'detail_more',
            onPressed: showMoreActions,
            builder: (context, state) => _buildMoreActionsButton(
              metadata,
              actionButtonStyle,
              tvScale,
              onPlayTrailer: onPlayTrailer,
              showFocus: state.showFocus,
            ),
          );

    // Watchlist, for movies and shows, online only. Watching both the provider
    // and the store is what makes the icon flip on tap: the store carries the
    // optimistic patch, the provider the list the patch is folded over.
    final watchlistProvider = context.watch<WatchlistProvider?>();
    final watchlistStore = context.watch<WatchlistStore?>();
    final isWatchlistKind = metadata.isMovie || metadata.isShow;
    final onWatchlist = WatchlistUiActions.isOnList(store: watchlistStore, provider: watchlistProvider, item: metadata);

    // Add and Remove are different words on the same button, and only a loaded
    // list tells them apart. The provider guards this, so it costs one fetch
    // per profile session rather than one per title opened.
    if (!widget.isOffline && isWatchlistKind && watchlistProvider != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(watchlistProvider.ensureLoaded());
      });
    }

    void onWatchlistPressed() => unawaited(WatchlistUiActions.toggle(context, metadata));

    final watchlistAction =
        (!widget.isOffline &&
            isWatchlistKind &&
            WatchlistUiActions.canOffer(provider: watchlistProvider, item: metadata, onList: onWatchlist))
        ? FocusableAction(
            debugLabel: 'detail_watchlist',
            onPressed: onWatchlistPressed,
            builder: (context, state) => iconActionButton(
              state,
              onPressed: onWatchlistPressed,
              icon: AppIcon(
                onWatchlist ? Symbols.bookmark_remove_rounded : Symbols.bookmark_add_rounded,
                fill: onWatchlist ? 1 : 0,
              ),
              tooltip: onWatchlist ? t.watchlist.remove : t.watchlist.add,
            ),
          )
        : null;

    // Request via Jellyseerr/Overseerr — only when a server is configured, the
    // item is a movie/show, and we're online (needs a TMDB-id lookup).
    final seerrConfigured = context.watch<SeerrProvider?>()?.isConfigured ?? false;
    final requestAction = (seerrConfigured && !widget.isOffline && (metadata.isMovie || metadata.isShow))
        ? FocusableAction(
            debugLabel: 'detail_request',
            onPressed: () => unawaited(_handleRequestPressed(metadata)),
            builder: (context, state) => iconActionButton(
              state,
              onPressed: () => unawaited(_handleRequestPressed(metadata)),
              icon: const AppIcon(Symbols.playlist_add_rounded, fill: 1),
              tooltip: t.seerr.request,
            ),
          )
        : null;

    final allActions = <FocusableAction>[
      playAction,
      ?trailerAction,
      ?shuffleAction,
      ?downloadAction,
      watchedAction,
      ?watchlistAction,
      ?requestAction,
      ?moreActionsAction,
    ];

    double playButtonWidthEstimate() {
      if (playButtonLabel.isEmpty) return 64.0;
      final textPainter = TextPainter(
        text: TextSpan(text: playButtonLabel, style: playTextStyle),
        maxLines: 1,
        textDirection: Directionality.of(context),
      )..layout();
      final textWidth = textPainter.width;
      textPainter.dispose();
      final horizontalPadding = isTv ? 34.0 * tvScale : 32.0;
      final iconGap = isTv ? 7.0 * tvScale : 8.0;
      return (horizontalPadding + playIconSize + iconGap + textWidth).clamp(64.0, double.infinity).toDouble();
    }

    final estimatedPlayWidth = playButtonWidthEstimate();
    double estimatedRowWidth(List<FocusableAction> actions) {
      if (actions.isEmpty) return 0;
      return estimatedPlayWidth + (actions.length - 1) * actionSize + (actions.length - 1) * gap;
    }

    List<FocusableAction> compactActionsFor(double maxWidth) {
      if (widget.isOffline) {
        final compact = <FocusableAction>[playAction, watchedAction];
        if (maxWidth.isFinite && estimatedRowWidth(compact) > maxWidth) return [playAction];
        return compact;
      }

      final medium = <FocusableAction>[
        playAction,
        ?downloadAction,
        watchedAction,
        ?watchlistAction,
        ?requestAction,
        ?moreActionsAction,
      ];
      if (!maxWidth.isFinite || estimatedRowWidth(medium) <= maxWidth) return medium;

      final compact = <FocusableAction>[playAction, watchedAction, ?moreActionsAction];
      if (estimatedRowWidth(compact) <= maxWidth) return compact;

      return [playAction, ?moreActionsAction];
    }

    Widget actionBar(List<FocusableAction> actions) {
      return FocusableActionBar(
        actions: actions,
        spacing: gap,
        onFocusChange: isTv ? _setTvDetailActionRowFocus : null,
        onNavigateUp: _focusAboveActionRow,
        onNavigateDown: _focusBelowActionRow,
      );
    }

    // TV screens are wide and D-pad focus should see every direct action.
    // On smaller online screens, hidden actions remain available from ⋮.
    if (isTv) return actionBar(allActions);

    return LayoutBuilder(
      builder: (context, constraints) {
        final maxWidth = constraints.maxWidth;
        if (!maxWidth.isFinite || estimatedRowWidth(allActions) <= maxWidth) {
          return actionBar(allActions);
        }
        return actionBar(compactActionsFor(maxWidth));
      },
    );
  }

  /// Resolve the item's TMDB id and open the seerr request sheet. The id
  /// lookup happens on press (not preemptively) so the detail screen stays
  /// cheap; a missing id just surfaces a non-fatal error.
  Future<void> _handleRequestPressed(MediaItem metadata) async {
    if (!(context.read<SeerrProvider?>()?.isConfigured ?? false)) return;
    final client = _getMediaClientForMetadata(context);
    if (client == null) return;
    ExternalIds ids;
    try {
      ids = await client.fetchExternalIds(metadata.id);
    } catch (_) {
      ids = const ExternalIds();
    }
    if (!mounted) return;
    final tmdb = ids.tmdb;
    if (tmdb == null) {
      showErrorSnackBar(context, t.seerr.errorGeneric);
      return;
    }
    final media = SeerrMedia(tmdbId: tmdb, mediaType: metadata.isMovie ? 'movie' : 'tv', title: metadata.displayTitle);
    final requested = await SeerrRequestSheet.show(context, media: media);
    if (requested == true && mounted) showSuccessSnackBar(context, t.seerr.requestSuccess);
  }

  Future<void> _handleWatchedTogglePressed(MediaItem metadata) async {
    try {
      final isWatched = metadata.isWatched;
      final outcome = await WatchActions.setWatched(context, metadata, watched: !isWatched, offline: widget.isOffline);
      if (!mounted) return;
      switch (outcome) {
        case WatchMarkOutcome.queuedOffline:
          showAppSnackBar(context, isWatched ? t.messages.markedAsUnwatchedOffline : t.messages.markedAsWatchedOffline);
        case WatchMarkOutcome.marked:
          _watchStateChanged = true;
          showSuccessSnackBar(context, isWatched ? t.messages.markedAsUnwatched : t.messages.markedAsWatched);
        case WatchMarkOutcome.skipped:
          break;
      }
    } catch (e) {
      if (mounted) {
        showErrorSnackBar(context, friendlyError(e));
      }
    }
  }

  Widget _buildWatchedToggleButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    bool showFocus = false,
  }) {
    return Pressable(
      onTap: () => unawaited(_handleWatchedTogglePressed(metadata)),
      child: IconButton.filledTonal(
        onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
        icon: AppIcon(metadata.isWatched ? Symbols.remove_done_rounded : Symbols.check_rounded, fill: 1),
        tooltip: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
        iconSize: PlatformDetector.isTV() ? 21 * tvScale : 20,
        style: actionButtonStyle(showFocus: showFocus),
      ),
    );
  }

  Widget _buildMoreActionsButton(
    MediaItem metadata,
    ButtonStyle Function({Color? foregroundColor, EdgeInsetsGeometry? padding, required bool showFocus})
    actionButtonStyle,
    double tvScale, {
    VoidCallback? onPlayTrailer,
    bool showFocus = false,
  }) {
    return MediaContextMenu(
      key: _contextMenuKey,
      item: metadata,
      onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
      onPlayTrailer: onPlayTrailer,
      child: Builder(
        builder: (buttonContext) {
          void openMenu() {
            final renderBox = buttonContext.findRenderObject() as RenderBox?;
            if (renderBox != null) {
              final position = renderBox.localToGlobal(renderBox.size.center(Offset.zero));
              _contextMenuKey.currentState?.showContextMenu(buttonContext, position: position);
            }
          }

          return Pressable(
            onTap: openMenu,
            child: IconButton.filledTonal(
              onPressed: openMenu,
              icon: const AppIcon(Symbols.more_vert_rounded, fill: 1),
              iconSize: PlatformDetector.isTV() ? 21 * tvScale : 20,
              style: actionButtonStyle(showFocus: showFocus),
            ),
          );
        },
      ),
    );
  }
}
