part of '../media_detail_screen.dart';

/// Synopsis, credits and the action icon row under the mobile film detail
/// (northstar 06), split out of `mobile_detail_view.dart` unchanged.
extension _MobileMediaDetailInfo on _MediaDetailScreenState {
  /// Synopsis (reuses [CollapsibleText] unchanged, DEC-109: mobile/desktop
  /// keep this in-place expand rather than the TV "Meer lezen" panel) plus
  /// the compact "Cast: … / Regie: …" text lines from mockup 06/the
  /// serie-detail comp.
  Widget _buildMobileSynopsisAndCredits(BuildContext context, MediaItem metadata) {
    final theme = Theme.of(context);
    final summary = metadata.summary;
    final roles = metadata.roles;
    final directors = metadata.directors;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    return Column(
      crossAxisAlignment: .start,
      children: [
        if (summary != null && summary.isNotEmpty) ...[
          CollapsibleText(text: summary, maxLines: 6, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
        ],
        if (roles != null && roles.isNotEmpty)
          Text.rich(
            TextSpan(
              style: mutedStyle,
              children: [
                TextSpan(
                  text: '${t.discover.cast}: ',
                  style: mutedStyle?.copyWith(fontWeight: .w600),
                ),
                TextSpan(text: roles.take(3).map((r) => r.tag).join(', ')),
              ],
            ),
          ),
        if (directors != null && directors.isNotEmpty) ...[
          const SizedBox(height: 4),
          Text.rich(
            TextSpan(
              style: mutedStyle,
              children: [
                TextSpan(
                  text: '${t.metadataEdit.director}: ',
                  style: mutedStyle?.copyWith(fontWeight: .w600),
                ),
                TextSpan(text: directors.join(', ')),
              ],
            ),
          ),
        ],
      ],
    );
  }

  /// Fixed action icon row (add to list / rate / mark watched / share).
  /// Every icon but share reuses an existing, already-tested handler:
  /// [WatchlistUiActions.toggle], [_showRatingDialog] and
  /// [_handleWatchedTogglePressed] are exactly what the pre-northstar action
  /// row and the long-press context menu already call. Share is genuinely
  /// new (no prior share capability existed anywhere in the app).
  ///
  /// With Liquid Glass on, [includeWatchlist] is false: the toggle moves to
  /// the round glass button next to Download (LG-02).
  Widget _buildMobileActionRow(BuildContext context, MediaItem metadata, {bool includeWatchlist = true}) {
    final (onWatchlist, canOfferWatchlist) = _mobileWatchlistState(context, metadata);

    final mediaClient = _getMediaClientForMetadata(context);
    final isNumericRating = mediaClient?.capabilities.numericUserRating ?? true;
    final hasRating = metadata.userRating != null && metadata.userRating! > 0;

    Widget action({
      required IconData icon,
      required String label,
      required VoidCallback? onPressed,
      bool active = false,
    }) {
      final color = active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface;
      final effectiveColor = onPressed == null ? color.withValues(alpha: 0.4) : color;
      return Expanded(
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 8),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, color: effectiveColor),
                const SizedBox(height: 4),
                Text(
                  label,
                  maxLines: 1,
                  overflow: .ellipsis,
                  textAlign: .center,
                  style: TextStyle(fontSize: 12, color: effectiveColor),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Row(
      children: [
        if (includeWatchlist)
          action(
            icon: onWatchlist ? Icons.bookmark_added_rounded : Icons.add_rounded,
            label: onWatchlist ? t.watchlist.remove : t.watchlist.add,
            onPressed: canOfferWatchlist ? () => unawaited(WatchlistUiActions.toggle(context, metadata)) : null,
          ),
        action(
          icon: isNumericRating ? Icons.star_rounded : Icons.thumb_up_rounded,
          label: t.mediaMenu.rate,
          active: hasRating,
          onPressed: widget.isOffline ? null : () => unawaited(_showRatingDialog(context, metadata)),
        ),
        action(
          icon: metadata.isWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
          label: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
          active: metadata.isWatched,
          onPressed: () => unawaited(_handleWatchedTogglePressed(metadata)),
        ),
        action(
          icon: Icons.send_rounded,
          label: t.common.share,
          onPressed: () => unawaited(SharePlus.instance.share(ShareParams(text: metadata.displayTitle))),
        ),
      ],
    );
  }

  /// Whether the film is on the kijklijst, and whether a toggle can be
  /// offered (online, a movie or show, a source that takes it). Shared by
  /// the action row and the glass watchlist button, so both show the same.
  (bool onList, bool canOffer) _mobileWatchlistState(BuildContext context, MediaItem metadata) {
    final watchlistProvider = context.watch<WatchlistProvider?>();
    final watchlistStore = context.watch<WatchlistStore?>();
    final isWatchlistKind = metadata.isMovie || metadata.isShow;
    final onWatchlist = WatchlistUiActions.isOnList(store: watchlistStore, provider: watchlistProvider, item: metadata);
    final canOffer =
        !widget.isOffline &&
        isWatchlistKind &&
        WatchlistUiActions.canOffer(provider: watchlistProvider, item: metadata, onList: onWatchlist);
    return (onWatchlist, canOffer);
  }
}
