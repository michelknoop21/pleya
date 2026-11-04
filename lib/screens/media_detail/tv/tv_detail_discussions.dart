part of '../../media_detail_screen.dart';

/// Discussies (04, 05, 07, 08): what people on Trakt say about this title.
extension _MediaDetailTvDiscussions on _MediaDetailScreenState {
  /// Instellingen ▸ Geavanceerd ▸ Privacy. Off, the page never asks Trakt.
  bool get _tvDetailDiscussionsWanted => SettingsService.instance.read(SettingsService.showTraktDiscussions);

  /// Trakt hears of a title once the viewer goes down the page, and not because
  /// a page opened: a title id and an IP address leave the device for this. The
  /// other rows need no such care, and a page that opens short asks for them at
  /// once. A page with nothing under its hero gives the viewer nowhere to go, so
  /// that one asks when it is sure of that.
  bool _tvDetailDiscussionsDue(MediaItem metadata) {
    if (!_tvDetailDiscussionsWanted || _tvDetailDiscussionsRequested) return false;
    final page = _tvDetailPageKey.currentState;
    if (page == null) return false;
    return page.hasLeftHero || (page.hasNoSections && !_isLoadingSeasons && !_tvDetailHasPendingRows(metadata));
  }

  TraktCommentsClient _tvDetailCommentsClient(MediaServerClient? server) {
    if (kPleyaVerify && server is PleyaServerClient) return TraktCommentsClient.forVerify(server.verifyTraktBase);
    return TraktCommentsClient.shared;
  }

  /// One go per page. Fails to nothing: without a key, without an id, on an error
  /// and on a children's profile there is simply no section.
  Future<void> _loadTvDetailDiscussions(MediaItem metadata) async {
    // The children's shield asks the profile now and fails closed: a provider
    // that is missing or a check that throws counts as a child.
    final account = context.read<TraktAccountProvider?>();
    final server = context.tryGetMediaClientForServer(serverIdOrNull(_metadata.serverId));
    if (account == null || server == null || await account.checkKidsProfile()) return;

    final comments = _tvDetailCommentsClient(server);
    if (!comments.isConfigured) return;
    try {
      final ids = await server.fetchExternalIds(metadata.id);
      final found = metadata.isMovie
          ? await comments.movieComments(ids)
          : await comments.showComments(
              ids,
              seasons: [
                for (final season in _seasons)
                  if ((season.index ?? 0) > 0) season.index!,
              ],
            );
      if (found != null && found.isNotEmpty) setStateIfMounted(() => _tvDetailDiscussions = found);
    } catch (e) {
      appLogger.d('Discussions for the detail page failed', error: e);
    }
  }

  String? _tvDetailDiscussionContext(MediaItem metadata, TraktComment comment) {
    if (metadata.isMovie) return null;
    final title = metadata.displayTitle;
    final season = comment.season;
    return season == null ? title : '${t.discover.seasonBadge(number: season)} • $title';
  }

  TvDetailSection _tvDetailDiscussionsSection(MediaItem metadata, List<TraktComment> comments) {
    final pt = TvHig.of(context);
    const id = 'discussions';
    return TvDetailSection(
      id: id,
      title: t.discover.discussions,
      itemIds: [for (final comment in comments) '${comment.season ?? 0}-${comment.id}'],
      cardWidth: TvDetailLayout.wideCardWidth * pt,
      cardHeight: TvDetailLayout.reviewCardHeight * pt,
      itemBuilder: (context, cell) {
        final comment = comments[cell.index];
        return AutomationNode(
          id: AutomationIds.mediaDetailSectionItem,
          instance: '$id.${cell.index}',
          role: 'list.item',
          focusNode: cell.focusNode,
          child: TvDetailDiscussionCard(
            cell: cell,
            comment: comment,
            titleContext: _tvDetailDiscussionContext(metadata, comment),
            onSelect: () {
              SelectKeyUpSuppressor.suppressSelectUntilKeyUp();
              _openTvDetailSynopsisPanel(comment.text, title: comment.author);
            },
          ),
        );
      },
    );
  }
}
