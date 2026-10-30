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

  bool _hasLoadedTvDetailSupplementalSections(MediaItem metadata) {
    if (widget.isOffline || (!metadata.isMovie && !metadata.isShow)) return true;
    return _hasLoadedExtras && _hasLoadedRelatedHubs;
  }

  void _scheduleTvDetailReveal(double railHeight, {required bool focusPrimaryAction}) {
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
        if (!mounted) return;
        if (focusPrimaryAction) {
          _playButtonFocusNode.requestFocus();
        } else {
          _tvDetailRailKey.currentState?.requestFocus();
        }
      });
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
