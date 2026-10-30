part of '../media_detail_screen.dart';

enum _DetailActionKind { play, trailer, shuffle, download, watched, watchlist, request, more }

/// One action the detail page offers, without a widget attached: the row that
/// draws it decides how it looks, and the conditions under which it exists stay
/// in one place however many rows draw them.
class _DetailAction {
  const _DetailAction(this.kind, {required this.onPressed, this.icon, this.iconFilled = true, this.tooltip});

  final _DetailActionKind kind;
  final VoidCallback? onPressed;

  /// Null for the kinds whose glyph depends on more than this model knows:
  /// play, download, watched and more each have their own builder.
  final IconData? icon;
  final bool iconFilled;
  final String? tooltip;
}

class _DetailActionModel {
  const _DetailActionModel({required this.actions, required this.onPlayTrailer});

  /// In the order the rows draw them.
  final List<_DetailAction> actions;

  /// Also handed to the ⋮ menu, so the trailer stays reachable from a row that
  /// has no button for it.
  final VoidCallback? onPlayTrailer;

  _DetailAction? of(_DetailActionKind kind) => actions.where((action) => action.kind == kind).firstOrNull;
}

extension _MediaDetailActionModel on _MediaDetailScreenState {
  /// Every action [metadata] offers right now. Watches the providers it reads,
  /// so call it from a build method.
  _DetailActionModel _detailActionModel(MediaItem metadata) {
    if (widget.isOffline) context.watch<DownloadProvider>();

    final VoidCallback? onPlayPressed = !widget.isOffline || _offlinePlaybackTarget(metadata) != null
        ? () => unawaited(_handlePlayPressed(metadata))
        : null;

    final primaryTrailer = _getPrimaryTrailer();
    final VoidCallback? onPlayTrailer = primaryTrailer == null
        ? null
        : () => unawaited(navigateToVideoPlayer(context, metadata: primaryTrailer));

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

    // Request via Jellyseerr/Overseerr — only when a server is configured, the
    // item is a movie/show, and we're online (needs a TMDB-id lookup).
    final seerrConfigured = context.watch<SeerrProvider?>()?.isConfigured ?? false;

    return _DetailActionModel(
      onPlayTrailer: onPlayTrailer,
      actions: [
        _DetailAction(_DetailActionKind.play, onPressed: onPlayPressed),
        if (onPlayTrailer != null)
          _DetailAction(
            _DetailActionKind.trailer,
            onPressed: onPlayTrailer,
            icon: Symbols.theaters_rounded,
            tooltip: t.tooltips.playTrailer,
          ),
        if (!widget.isOffline && (metadata.isShow || metadata.isSeason))
          _DetailAction(
            _DetailActionKind.shuffle,
            onPressed: () async {
              await _handleShufflePlayWithQueue(context, metadata);
            },
            icon: Symbols.shuffle_rounded,
            tooltip: t.tooltips.shufflePlay,
          ),
        if (!widget.isOffline && !PlatformDetector.isAppleTV())
          _DetailAction(_DetailActionKind.download, onPressed: () => unawaited(_handleDownloadButtonPressed(metadata))),
        _DetailAction(_DetailActionKind.watched, onPressed: () => unawaited(_handleWatchedTogglePressed(metadata))),
        if (!widget.isOffline &&
            isWatchlistKind &&
            WatchlistUiActions.canOffer(provider: watchlistProvider, item: metadata, onList: onWatchlist))
          _DetailAction(
            _DetailActionKind.watchlist,
            onPressed: () => unawaited(WatchlistUiActions.toggle(context, metadata)),
            icon: onWatchlist ? Symbols.bookmark_remove_rounded : Symbols.bookmark_add_rounded,
            iconFilled: onWatchlist,
            tooltip: onWatchlist ? t.watchlist.remove : t.watchlist.add,
          ),
        if (seerrConfigured && !widget.isOffline && (metadata.isMovie || metadata.isShow))
          _DetailAction(
            _DetailActionKind.request,
            onPressed: () => unawaited(_handleRequestPressed(metadata)),
            icon: Symbols.playlist_add_rounded,
            tooltip: t.seerr.request,
          ),
        if (!widget.isOffline)
          _DetailAction(
            _DetailActionKind.more,
            onPressed: () => _contextMenuKey.currentState?.showContextMenu(context),
          ),
      ],
    );
  }
}
