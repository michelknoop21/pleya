part of '../../media_detail_screen.dart';

/// A season tab as 01 draws it: a small logo with the season's name and summary
/// above a row of wide cards, the actions and the activity under that row.
///
/// The row and the actions hold their heights whatever the text does: the
/// summary changes with every episode the focus passes over, and a row that
/// moved along with it would make the ring jump.
extension _MediaDetailTvSeason on _MediaDetailScreenState {
  String _tvDetailSeasonLabel(MediaItem? season) {
    if (season == null) return t.libraries.groupings.episodes;
    return season.title?.isNotEmpty == true ? season.title! : season.displayTitle;
  }

  /// The season's name, and what is under the ring when that is an episode: the
  /// card itself only says `A1`.
  String _tvDetailSeasonLine(MediaItem? season) {
    final name = _tvDetailSeasonLabel(season);
    final episode = _tvDetailFocusedEpisode;
    if (episode == null) return name;
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    return [
      name,
      t.discover.episodeBadge(number: episode.index ?? 0),
      if (!(hideSpoilers && episode.shouldHideSpoiler)) ?episode.title,
    ].join(' • ');
  }

  /// The rows between the tabs and the cards.
  List<Widget> _buildTvDetailSeasonRows({
    required MediaItem metadata,
    required MediaItem? season,
    required Widget? synopsis,
    required Color ink,
    required Color muted,
  }) {
    final pt = TvHig.of(context);
    return [
      SizedBox(height: (TvDetailLayout.seasonLogoTop - TvDetailLayout.tabsTop - TvDetailLayout.tabHeight) * pt),
      _buildDetailLogoOrTitle(
        context,
        metadata,
        width: TvDetailLayout.seasonLogoWidth * pt,
        height: TvDetailLayout.seasonLogoHeight * pt,
        alignment: Alignment.bottomLeft,
        titleBuilder: (context, title) => _buildDetailTitle(
          context,
          title,
          fontSize: TvHig.title2 * pt,
          fontWeight: .w800,
          shadowBlur: 12,
          color: ink,
          shadowColor: _tvDetailTitleShadowColor(context),
          alignment: Alignment.bottomLeft,
        ),
      ),
      SizedBox(height: TvDetailLayout.seasonNameGap * pt),
      SizedBox(
        height: TvDetailLayout.seasonNameHeight * pt,
        width: TvDetailLayout.synopsisWidth * pt,
        child: Text(
          _tvDetailSeasonLine(season),
          maxLines: 1,
          overflow: .ellipsis,
          style: TextStyle(color: muted, fontSize: TvHig.callout * pt, fontWeight: .w600),
        ),
      ),
      SizedBox(height: TvDetailLayout.seasonSynopsisGap * pt),
      SizedBox(
        height: TvDetailLayout.synopsisLines * TvHig.caption1Leading * pt,
        child: Align(alignment: .topLeft, child: synopsis ?? const SizedBox.shrink()),
      ),
    ];
  }

  /// UP out of the row: the read-more when there is one, the tabs otherwise.
  void _focusAboveTvDetailSeasonRow() {
    if (_tvDetailReadMoreVisible) {
      _tvDetailReadMoreFocusNode.requestFocus();
    } else {
      _focusTvDetailOpenTab();
    }
  }

  /// The actions of the open season and who else has been watching it.
  Widget _buildTvDetailSeasonFooter(MediaItem metadata) {
    final pt = TvHig.of(context);
    final width = MediaQuery.sizeOf(context).width;
    return Padding(
      padding: EdgeInsets.only(left: TvDetailLayout.leftMargin(width), right: TvDetailLayout.rightMargin * pt),
      child: Column(
        crossAxisAlignment: .start,
        mainAxisSize: .min,
        children: [
          _buildTvDetailActionRow(_tvDetailOpenSeason ?? metadata),
          _buildUnifiedSourceLine(),
          ..._buildTvDetailActivityRow(const []),
        ],
      ),
    );
  }

  /// The card that stands for the whole season, in front of its episodes.
  Widget _buildTvDetailSeasonCard(MediaItem metadata, MediaItem season, TvCatalogGridCell cell) {
    final menuKey = _tvDetailMenuKey('$_tvDetailEpisodesSectionId/${season.id}');
    return AutomationNode(
      id: AutomationIds.mediaDetailSectionItem,
      instance: '$_tvDetailEpisodesSectionId.${cell.index}',
      role: 'list.item',
      focusNode: cell.focusNode,
      child: MediaContextMenu(
        key: menuKey,
        item: season,
        onRefresh: (itemId) => unawaited(_refreshItemInPlace(itemId)),
        child: TvDetailEpisodeCard(
          cell: cell,
          imagePath: season.artPath ?? metadata.artPath ?? season.thumbPath,
          client: _getArtworkMediaClient(context),
          badge: _tvDetailSeasonLabel(season),
          semanticLabel: _tvDetailSeasonLabel(season),
          onSelect: () {
            final next = _seasonNextEpisode;
            if (next != null) _tvDetailPlayEpisode(_fresh(next));
          },
          onContextMenu: () => menuKey.currentState?.showContextMenu(context),
          onFocused: () => _tvDetailOnEpisodeFocused(null),
        ),
      ),
    );
  }
}
