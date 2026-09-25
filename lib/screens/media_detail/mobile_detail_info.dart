part of '../media_detail_screen.dart';

/// The Download capsule, synopsis, credits, the action icon row and the
/// section headings of the mobile detail page (northstar 06, DEC-131), split
/// out of `mobile_detail_view.dart` unchanged.
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
    final genres = metadata.genres;
    final studio = metadata.studio;
    final mutedStyle = theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurfaceVariant);

    Widget labelled(String label, String value) => Text.rich(
      TextSpan(
        style: mutedStyle,
        children: [
          TextSpan(
            text: '$label: ',
            style: mutedStyle?.copyWith(fontWeight: .w600),
          ),
          TextSpan(text: value),
        ],
      ),
    );

    return Column(
      crossAxisAlignment: .start,
      children: [
        // The genre line the TV detail draws under its metadata.
        if (genres != null && genres.isNotEmpty) ...[
          Text(genres.join(' · '), style: mutedStyle?.copyWith(fontWeight: .w600)),
          const SizedBox(height: 8),
        ],
        if (summary != null && summary.isNotEmpty) ...[
          CollapsibleText(text: summary, maxLines: 6, style: theme.textTheme.bodyLarge?.copyWith(height: 1.5)),
          const SizedBox(height: 12),
        ],
        if (roles != null && roles.isNotEmpty) labelled(t.discover.cast, roles.take(3).map((r) => r.tag).join(', ')),
        if (directors != null && directors.isNotEmpty) ...[
          const SizedBox(height: 4),
          labelled(t.metadataEdit.director, directors.join(', ')),
        ],
        if (studio != null && studio.isNotEmpty) ...[const SizedBox(height: 4), labelled(t.discover.studio, studio)],
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
      required void Function(BuildContext buttonContext)? onPressed,
      bool active = false,
    }) {
      final color = active ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.onSurface;
      final effectiveColor = onPressed == null ? color.withValues(alpha: 0.4) : color;
      return Expanded(
        child: Builder(
          builder: (buttonContext) => InkWell(
            onTap: onPressed == null ? null : () => onPressed(buttonContext),
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
        ),
      );
    }

    return Row(
      children: [
        if (includeWatchlist)
          action(
            icon: onWatchlist ? Icons.bookmark_added_rounded : Icons.add_rounded,
            label: onWatchlist ? t.watchlist.remove : t.watchlist.add,
            onPressed: canOfferWatchlist ? (_) => unawaited(WatchlistUiActions.toggle(context, metadata)) : null,
          ),
        action(
          icon: isNumericRating ? Icons.star_rounded : Icons.thumb_up_rounded,
          label: t.mediaMenu.rate,
          active: hasRating,
          onPressed: widget.isOffline ? null : (_) => unawaited(_showRatingDialog(context, metadata)),
        ),
        action(
          icon: metadata.isWatched ? Icons.check_circle_rounded : Icons.check_circle_outline_rounded,
          label: metadata.isWatched ? t.tooltips.markAsUnwatched : t.tooltips.markAsWatched,
          active: metadata.isWatched,
          onPressed: (_) => unawaited(_handleWatchedTogglePressed(metadata)),
        ),
        action(
          icon: Icons.send_rounded,
          label: t.common.share,
          onPressed: (buttonContext) => unawaited(_shareMobileItem(buttonContext, metadata)),
        ),
      ],
    );
  }

  /// The iOS share sheet anchored to the tapped button. share_plus needs
  /// `sharePositionOrigin` for the popover (required on iPad, and without it
  /// the sheet could fail to appear or leave the UI unresponsive); Michel saw
  /// exactly that on 24 September ("delen werkt niet"). A failure to present
  /// the sheet is shown, a dismissed sheet is not.
  Future<void> _shareMobileItem(BuildContext buttonContext, MediaItem metadata) async {
    final box = buttonContext.findRenderObject() as RenderBox?;
    final origin = box == null ? null : box.localToGlobal(Offset.zero) & box.size;
    final year = metadata.year;
    final text = year == null ? metadata.displayTitle : '${metadata.displayTitle} ($year)';
    try {
      await SharePlus.instance.share(
        ShareParams(text: text, subject: metadata.displayTitle, sharePositionOrigin: origin),
      );
    } catch (error) {
      if (!mounted) return;
      showErrorSnackBar(context, t.errors.failedToLoad(context: t.common.share));
    }
  }

  /// Section heading over the inline episodes, extras and cast blocks: the
  /// same `titleLarge` bold the tablet/desktop layout uses for its sections.
  Widget _buildMobileSectionTitle(BuildContext context, String title, {Key? key}) {
    return Text(
      key: key,
      title,
      style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: .bold),
    );
  }

  /// Full-width secondary CTA: "Downloaden", reusing
  /// [_handleDownloadButtonPressed] for the full state machine (queue,
  /// pause/resume, retry, delete) unchanged; only the label mapping below is
  /// new, matching the northstar's text button instead of an icon-only one.
  Widget _buildMobileDownloadCta(BuildContext context, MediaItem metadata, {bool glass = false}) {
    if (widget.isOffline || PlatformDetector.isAppleTV()) return const SizedBox.shrink();

    return Consumer<DownloadProvider>(
      builder: (context, downloadProvider, _) {
        final globalKey = metadata.globalKey;
        final progress = downloadProvider.getProgress(globalKey);
        final isDownloaded = downloadProvider.isDownloaded(globalKey);

        final (icon, label) = switch (progress?.status) {
          _ when downloadProvider.isQueueing(globalKey) => (Icons.schedule_rounded, t.downloads.queuedTooltip),
          DownloadStatus.queued => (Icons.schedule_rounded, t.downloads.queuedTooltip),
          DownloadStatus.downloading => (Icons.downloading_rounded, t.downloads.downloadingTooltip),
          DownloadStatus.paused => (Icons.pause_circle_outline_rounded, t.downloads.resumeDownload),
          DownloadStatus.failed => (Icons.error_outline_rounded, t.downloads.retryDownload),
          DownloadStatus.cancelled => (Icons.cancel_rounded, t.downloads.cancelledDownload),
          _ when isDownloaded => (Icons.check_circle_outline_rounded, t.downloads.downloadAction),
          _ => (Icons.download_rounded, _mobileDownloadActionLabel(metadata)),
        };

        if (glass) {
          return GlassCapsuleButton(
            icon: icon,
            label: label,
            onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
          );
        }
        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: SizedBox(
            width: double.infinity,
            height: 48,
            child: FilledButton.tonalIcon(
              onPressed: () => unawaited(_handleDownloadButtonPressed(metadata)),
              // The tonal variant's own defaults never reach this button:
              // monoTheme's `filledButtonTheme` sets `backgroundColor: c.text`
              // for every FilledButton, and a theme style outranks a variant
              // default, so this rendered pure white — the same capsule as the
              // primary CTA right above it. The mockup has a grey secondary
              // under a white primary, so name the surface explicitly.
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: tokens(context).surfaceElevated,
                foregroundColor: tokens(context).text,
              ),
              icon: Icon(icon),
              label: Text(label, style: const TextStyle(fontWeight: .w700)),
            ),
          ),
        );
      },
    );
  }

  /// "Downloaden S7:E18" for a show with an on-deck episode (comp), plain
  /// "Downloaden" otherwise.
  String _mobileDownloadActionLabel(MediaItem metadata) {
    final onDeck = _onDeckEpisode;
    if (!metadata.isShow || onDeck == null || onDeck.parentIndex == null || onDeck.index == null) {
      return t.downloads.downloadAction;
    }
    final episodeLabel = t.discover.playEpisode(
      season: onDeck.parentIndex.toString(),
      episode: onDeck.index.toString(),
    );
    return '${t.downloads.downloadAction} $episodeLabel';
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
