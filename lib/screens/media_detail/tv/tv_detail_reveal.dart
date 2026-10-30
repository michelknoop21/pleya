part of '../../media_detail_screen.dart';

/// Holds the TV page back until it can open without rows jumping into place.
extension _MediaDetailTvReveal on _MediaDetailScreenState {
  bool _isTvDetailReadyToReveal(MediaItem metadata) {
    if (_isLoadingMetadata) return false;
    if (!_hasLoadedTvDetailSupplementalSections(metadata)) return false;

    if (metadata.isShow) {
      if (_isLoadingSeasons || (!_hasLoadedSeasons && _seasons.isEmpty)) return false;
      if (_showEpisodesDirectly) return _hasLoadedEpisodes && !_isLoadingEpisodes;
      if (_seasons.isEmpty) return true;
      if (_selectedSeasonIndex < 0 || _selectedSeasonIndex >= _seasons.length) return false;
      if (_seasonEpisodesFirstPageError) return true;
      return !_isLoadingSeasonEpisodes && _seasonEpisodePager.hasState(_seasons[_selectedSeasonIndex].id);
    }

    if (metadata.isSeason) {
      return _hasLoadedEpisodes && !_isLoadingEpisodes;
    }

    return true;
  }

  /// The rail page lays its height out from what its hubs hold, so it waits for
  /// them. [TvDetailPage] loads its sections on approach and can only ever open
  /// without them: waiting here would keep it shut for good.
  bool _hasLoadedTvDetailSupplementalSections(MediaItem metadata) {
    if (_tvDetailUsesPage(metadata)) return true;
    if (widget.isOffline || (!metadata.isMovie && !metadata.isShow)) return true;
    return _hasLoadedExtras && _hasLoadedRelatedHubs;
  }

  void _scheduleTvDetailReveal(double railHeight, {required VoidCallback onRevealed}) {
    final pendingRailHeight = _tvDetailPendingRailHeight;
    if (pendingRailHeight == null || railHeight > pendingRailHeight) {
      _tvDetailPendingRailHeight = railHeight;
    }
    if (_tvDetailRevealed || _tvDetailRevealScheduled) return;

    _tvDetailRevealScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setStateIfMounted(() {
        _tvDetailStableRailHeight = _tvDetailPendingRailHeight ?? railHeight;
        _tvDetailRevealScheduled = false;
        _tvDetailRevealed = true;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onRevealed();
      });
    });
  }

  /// Where the page opens: on the pill for a film, as 03 draws it on the Serie
  /// tab, and on the episode or the season a deep link came in on.
  void _focusTvDetailOpening(MediaItem metadata) {
    if (!metadata.isShow) {
      _playButtonFocusNode.requestFocus();
    } else if (_tvDetailSeriesTabActive) {
      _tvDetailSeriesTabFocusNode.requestFocus();
    } else {
      // The tab holds the focus until the target has loaded.
      _focusTvDetailOpenTab();
      _tvDetailInitialFocusPending = true;
      _tvDetailFinishInitialFocus();
    }
  }

  /// A deep-linked episode can sit pages further than what has loaded: the build
  /// that sees it arrive, or sees the paging give up, places the focus.
  void _tvDetailFinishInitialFocus() {
    if (!_tvDetailInitialFocusPending) return;
    final target = widget.initialEpisodeId;
    if (target != null && !_episodesContainInitialTarget && !_initialEpisodePagingDone) return;
    _tvDetailInitialFocusPending = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final page = _tvDetailPageKey.currentState;
      final onTarget =
          target != null && (page?.restoreFocus(sectionId: _tvDetailEpisodesSectionId, itemId: target) ?? false);
      if (!onTarget && !(page?.focusFirstSection() ?? false)) _focusTvDetailOpenTab();
    });
  }

  Widget _buildTvDetailRevealGate(Widget child, KeyEventResult Function(FocusNode, KeyEvent) handleBack) {
    final revealed = _tvDetailRevealed;
    return Focus(
      canRequestFocus: !revealed,
      onKeyEvent: revealed ? null : handleBack,
      child: ExcludeFocus(
        excluding: !revealed,
        child: IgnorePointer(
          ignoring: !revealed,
          child: AnimatedOpacity(
            opacity: revealed ? 1 : 0,
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOutCubic,
            child: child,
          ),
        ),
      ),
    );
  }
}
