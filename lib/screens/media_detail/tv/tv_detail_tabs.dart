part of '../../media_detail_screen.dart';

/// One tab of a series page.
class _TvDetailTab {
  const _TvDetailTab({required this.id, required this.label, required this.focusNode, this.seasonIndex});

  /// `series`, `episodes`, or the season's position: the automation instance.
  final String id;
  final String label;
  final FocusNode focusNode;
  final int? seasonIndex;
}

const String _tvDetailSeriesTabId = 'series';
const String _tvDetailEpisodesTabId = 'episodes';
const String _tvDetailSeasonsSectionId = 'seasons';
const String _tvDetailEpisodesSectionId = 'episodes';

/// The tabs above a series page: Serie plus one per season, all in this screen.
///
/// Stepping onto a tab opens it, as the old season chips did, so there is
/// nothing to confirm with Select: the white pill and the open tab only part
/// ways once the focus goes down into the page. The state under it is what the
/// phone's season tabs use, `_selectedSeasonIndex` and `_seasonEpisodePager`, so
/// paging, retry and prefetch stay one thing. A series without seasons of its
/// own (Plex's flattened shows, a single Jellyfin season) gets one Episodes tab.
extension _MediaDetailTvTabs on _MediaDetailScreenState {
  bool get _tvDetailSeasonTabActive => !_tvDetailSeriesTabActive;

  /// What the page shows right now, which only a series can make a season.
  bool get _tvDetailShowsSeasonTab => _fullOrPassedShow && _tvDetailSeasonTabActive;

  bool get _tvDetailHasSeasonTabs => !_showEpisodesDirectly && _seasons.isNotEmpty;

  MediaItem? get _tvDetailOpenSeason {
    if (!_tvDetailHasSeasonTabs) return null;
    return _fresh(_seasons[_selectedSeasonIndex.clamp(0, _seasons.length - 1)]);
  }

  List<_TvDetailTab> _tvDetailTabs() => [
    _TvDetailTab(id: _tvDetailSeriesTabId, label: t.discover.seriesTab, focusNode: _tvDetailSeriesTabFocusNode),
    if (_tvDetailHasSeasonTabs)
      for (var i = 0; i < _seasons.length && i < _seasonTabFocusNodes.length; i++)
        _TvDetailTab(
          id: '$i',
          label: _seasons[i].title?.isNotEmpty == true
              ? _seasons[i].title!
              : (_seasons[i].displaySubtitle ?? _seasons[i].displayTitle),
          focusNode: _seasonTabFocusNodes[i],
          seasonIndex: i,
        )
    // A first load that failed still needs a tab, the way back is under it, and
    // so does the next try while it runs: the focus stands on that tab.
    else if (_episodes.isNotEmpty || _episodeListPageError || _allEpisodes.isInitialLoading)
      _TvDetailTab(
        id: _tvDetailEpisodesTabId,
        label: t.libraries.groupings.episodes,
        focusNode: _tvDetailEpisodesTabFocusNode,
      ),
  ];

  bool _tvDetailTabIsActive(_TvDetailTab tab) => switch (tab.id) {
    _tvDetailSeriesTabId => _tvDetailSeriesTabActive,
    _tvDetailEpisodesTabId => _tvDetailSeasonTabActive,
    _ => _tvDetailSeasonTabActive && tab.seasonIndex == _selectedSeasonIndex,
  };

  void _tvDetailOpenTab(_TvDetailTab tab) {
    _tvDetailPageKey.currentState?.forgetFocusedSection();
    setStateIfMounted(() {
      _tvDetailSeriesTabActive = tab.id == _tvDetailSeriesTabId;
      _tvDetailFocusedEpisode = null;
    });
    final seasonIndex = tab.seasonIndex;
    if (seasonIndex == null) return;
    if (seasonIndex == _selectedSeasonIndex) {
      // Back on the same season, by way of Serie. A page that never came gets
      // its next try here.
      if (_episodes.isEmpty) unawaited(_fetchSeasonEpisodes(seasonIndex));
      return;
    }
    // The list goes with the tab: until the first page is in, nothing under this
    // tab may be an episode of the season before it, for Select and Play alike.
    setStateIfMounted(() {
      _selectedSeasonIndex = seasonIndex;
      _episodes = List.of(_selectedSeasonEpisodeState.items);
    });
    unawaited(_fetchSeasonEpisodes(seasonIndex));
  }

  void _tvDetailStepTab(List<_TvDetailTab> tabs, int index) {
    if (index < 0 || index >= tabs.length) return;
    _tvDetailOpenTab(tabs[index]);
    tabs[index].focusNode.requestFocus();
    if (tabs[index].focusNode.context != null) scrollContextToCenter(tabs[index].focusNode.context);
  }

  /// The tab that is open, for the steps that come up out of the page.
  void _focusTvDetailOpenTab() {
    final tabs = _tvDetailTabs();
    final tab = tabs.where(_tvDetailTabIsActive).firstOrNull ?? tabs.first;
    requestFocusClearingDirectionalHistory(tab.focusNode);
  }

  /// Which season [_tvDetailSeasonFocus] files the card under.
  String get _tvDetailOpenSeasonKey => _tvDetailOpenSeason?.id ?? _tvDetailEpisodesTabId;

  /// Down from the tabs: the page under the one that is open, on the card this
  /// season was left on.
  void _focusBelowTvDetailTabs() {
    if (_tvDetailSeasonTabActive) {
      final page = _tvDetailPageKey.currentState;
      final left = _tvDetailSeasonFocus[_tvDetailOpenSeasonKey];
      if (left != null && (page?.restoreFocus(sectionId: _tvDetailEpisodesSectionId, itemId: left) ?? false)) return;
      if (page?.focusFirstSection() ?? false) return;
    }
    _focusTvDetailActionRow();
  }

  /// A season poster on the Serie tab: into that season, on its first card.
  void _tvDetailOpenSeasonFromPoster(int seasonIndex) {
    SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
    final tab = _tvDetailTabs().where((tab) => tab.seasonIndex == seasonIndex).firstOrNull;
    if (tab == null) return;
    _tvDetailOpenTab(tab);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (!(_tvDetailPageKey.currentState?.focusFirstSection() ?? false)) tab.focusNode.requestFocus();
    });
  }

  /// Menu on a season the viewer walked into: back to the Serie tab, onto the
  /// poster when there is one to land on. A page opened on the season has no
  /// overview behind it, so Menu closes that one.
  bool get _tvDetailMenuLeavesSeason =>
      PlatformDetector.isTV() && _tvDetailShowsSeasonTab && !_hasInitialDetailFocusTarget;

  bool get _fullOrPassedShow => (_fullMetadata ?? _metadata).isShow;

  void _tvDetailLeaveSeasonTab() {
    final season = _tvDetailOpenSeason;
    final tabs = _tvDetailTabs();
    _tvDetailOpenTab(tabs.first);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final page = _tvDetailPageKey.currentState;
      final onPoster =
          season != null && (page?.restoreFocus(sectionId: _tvDetailSeasonsSectionId, itemId: season.id) ?? false);
      if (!onPoster) tabs.first.focusNode.requestFocus();
    });
  }

  Widget _buildTvDetailTabs() {
    final pt = TvHig.of(context);
    final tabs = _tvDetailTabs();
    final open = tabs.where(_tvDetailTabIsActive).firstOrNull;
    return AutomationNode(
      id: AutomationIds.mediaDetailTabs,
      role: 'list',
      state: () => {'child_count': tabs.length, 'open': open?.id},
      child: SizedBox(
        height: TvDetailLayout.tabHeight * pt,
        child: SingleChildScrollView(
          controller: _seasonTabsScrollController,
          scrollDirection: Axis.horizontal,
          clipBehavior: Clip.none,
          child: Row(
            children: [
              for (final (index, tab) in tabs.indexed)
                Padding(
                  padding: EdgeInsets.only(left: index == 0 ? 0 : TvDetailLayout.tabGap * pt),
                  child: AutomationNode(
                    id: AutomationIds.mediaDetailTab,
                    instance: tab.id,
                    role: 'chip',
                    focusNode: tab.focusNode,
                    state: () => {'open': _tvDetailTabIsActive(tab)},
                    child: TvDetailTabPill(
                      label: tab.label,
                      active: _tvDetailTabIsActive(tab),
                      focusNode: tab.focusNode,
                      onSelect: () {
                        SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
                        _focusBelowTvDetailTabs();
                      },
                      onNavigateUp: _focusTopNavigationFromDetail,
                      onNavigateDown: _focusBelowTvDetailTabs,
                      onNavigateLeft: () => _tvDetailStepTab(tabs, index - 1),
                      onNavigateRight: () => _tvDetailStepTab(tabs, index + 1),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
