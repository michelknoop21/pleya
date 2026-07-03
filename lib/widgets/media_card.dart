import 'dart:ui';
import '../media/ids.dart';

import 'package:flutter/material.dart';
import 'package:pleya/widgets/app_icon.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:provider/provider.dart';
import '../focus/card_focus_scope.dart';
import '../focus/input_mode_tracker.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_playlist.dart';
import '../mixins/context_menu_tap_mixin.dart';
import '../providers/download_provider.dart';
import '../providers/watch_state_store.dart';
import '../services/device_performance.dart';
import '../services/download_storage_service.dart';
import '../services/settings_service.dart';
import 'new_content_badge.dart';
import 'pressable.dart';
import 'settings_builder.dart';
import 'watched_indicator.dart';
import '../utils/content_utils.dart';
import '../utils/hero_flight.dart';
import '../utils/provider_extensions.dart';
import '../utils/formatters.dart';
import '../utils/media_navigation_helper.dart';
import '../utils/snackbar_helper.dart';
import '../theme/mono_tokens.dart';
import '../i18n/strings.g.dart';
import 'media_context_menu.dart';
import 'media_card_list_layout.dart';
import 'backend_badge.dart';
import 'optimized_media_image.dart';
import 'hover_boxart_overlay.dart';
import '../utils/platform_detector.dart';

const _failedPosterUrlCacheLimit = 512;
final _failedPosterUrls = <String>{};

bool _hasFailedPosterUrl(String? url) => url != null && _failedPosterUrls.contains(url);

void _rememberFailedPosterUrl(String? url) {
  if (url == null || url.isEmpty) return;
  _failedPosterUrls.remove(url);
  _failedPosterUrls.add(url);
  if (_failedPosterUrls.length > _failedPosterUrlCacheLimit) {
    _failedPosterUrls.remove(_failedPosterUrls.first);
  }
}

class MediaCard extends StatefulWidget {
  /// Either a [MediaItem] or a [MediaPlaylist]. Typed as [Object] because Dart
  /// has no nominal union type — runtime `is` checks select the variant.
  final Object item;
  final double? width;
  final double? height;
  final void Function(String itemId)? onRefresh;
  final VoidCallback? onRemoveFromContinueWatching;
  final VoidCallback? onListRefresh; // Callback to refresh the entire parent list
  final bool forceGridMode;
  final bool forceListMode;
  final bool isInContinueWatching;
  final bool usesContinueWatchingAction;
  final String? collectionId; // The collection ID if displaying within a collection
  final bool isOffline; // True for downloaded content without server access
  final bool mixedHubContext; // True when in a hub with mixed content (movies + episodes)
  final bool showServerName; // Show server name in list view (multi-server)
  final EpisodePosterMode? episodePosterModeOverride;
  final bool fullBleedImage;

  const MediaCard({
    super.key,
    required this.item,
    this.width,
    this.height,
    this.onRefresh,
    this.onRemoveFromContinueWatching,
    this.onListRefresh,
    this.forceGridMode = false,
    this.forceListMode = false,
    this.isInContinueWatching = false,
    bool? usesContinueWatchingAction,
    this.collectionId,
    this.isOffline = false,
    this.mixedHubContext = false,
    this.showServerName = false,
    this.episodePosterModeOverride,
    this.fullBleedImage = false,
  }) : usesContinueWatchingAction = usesContinueWatchingAction ?? isInContinueWatching;

  @override
  State<MediaCard> createState() => MediaCardState();
}

class MediaCardState extends State<MediaCard> with ContextMenuTapMixin<MediaCard> {
  /// Per-instance Hero tag flown poster → detail backdrop. Unique per card
  /// instance so the same item appearing in multiple rows never shares a tag
  /// (which would crash the Hero flight). Not used on TV (d-pad focus flow
  /// already owns the spotlight transition).
  late final Object _heroTag = UniqueKey();

  bool get _heroEligible => widget.item is MediaItem && !PlatformDetector.isTV();

  Widget _wrapPosterHero(Widget poster) => _heroEligible
      ? Hero(
          tag: _heroTag,
          flightShuttleBuilder: posterHeroFlightShuttle(posterRadius: tokens(context).radiusSm),
          child: poster,
        )
      : poster;

  /// Public method to trigger tap action (for keyboard/gamepad SELECT)
  void handleTap() {
    _handleTap(context, _effectiveItemForAction(context));
  }

  Object _effectiveItem(BuildContext context) {
    final item = widget.item;
    return item is MediaItem ? context.withFreshWatchState(item) : item;
  }

  Object _effectiveItemForAction(BuildContext context) {
    final item = widget.item;
    return item is MediaItem ? context.readFreshWatchState(item) : item;
  }

  String _buildSemanticLabel(Object item) {
    // Playlists don't expose kind, so build a simple localized label and exit early
    if (item is MediaPlaylist) {
      final count = item.leafCount;
      final countText = count != null ? ', ${t.playlists.itemCount(count: count)}' : '';
      return '${item.displayTitle}, ${t.playlists.playlist}$countText';
    }

    if (item is! MediaItem) {
      return '$item';
    }

    String baseLabel;
    switch (item.kind) {
      case MediaKind.episode:
        final episodeInfo = item.parentIndex != null && item.index != null ? 'S${item.parentIndex} E${item.index}' : '';
        baseLabel = t.accessibility.mediaCardEpisode(title: item.displayTitle, episodeInfo: episodeInfo);
      case MediaKind.season:
        final seasonInfo = item.title?.isNotEmpty == true
            ? item.title!
            : item.index != null
            ? t.common.seasonNumber(number: item.index!)
            : '';
        baseLabel = t.accessibility.mediaCardSeason(title: item.displayTitle, seasonInfo: seasonInfo);
      case MediaKind.movie:
        baseLabel = t.accessibility.mediaCardMovie(title: item.displayTitle);
      default:
        baseLabel = t.accessibility.mediaCardShow(title: item.displayTitle);
    }

    // Add watched status
    final hasActiveProgress =
        item.viewOffsetMs != null &&
        item.durationMs != null &&
        item.viewOffsetMs! > 0 &&
        item.viewOffsetMs! < item.durationMs!;

    if (hasActiveProgress) {
      final percent = ((item.viewOffsetMs! / item.durationMs!) * 100).round();
      baseLabel = '$baseLabel, ${t.accessibility.mediaCardPartiallyWatched(percent: percent)}';
    } else if (item.isWatched) {
      baseLabel = '$baseLabel, ${t.accessibility.mediaCardWatched}';
    } else {
      baseLabel = '$baseLabel, ${t.accessibility.mediaCardUnwatched}';
    }

    return baseLabel;
  }

  void _handleTap(BuildContext context, Object item) async {
    // Ignore taps while context menu is open to avoid double-activating
    if (contextMenuKey.currentState?.isContextMenuOpen == true) {
      return;
    }

    final result = await navigateToMediaItem(
      context,
      item,
      onRefresh: widget.onRefresh,
      isOffline: widget.isOffline,
      playDirectly: widget.usesContinueWatchingAction,
      heroTag: _heroEligible ? _heroTag : null,
    );

    if (!context.mounted) return;

    switch (result) {
      case MediaNavigationResult.unsupported:
        showAppSnackBar(context, t.messages.musicNotSupported);
      case MediaNavigationResult.listRefreshNeeded:
        widget.onListRefresh?.call();
      case MediaNavigationResult.navigated:
      case MediaNavigationResult.librarySelected:
        // Item refresh already handled by onRefresh callback in helper
        break;
    }
  }

  /// Get the local poster path for offline mode
  String? _getLocalPosterPath(BuildContext context, Object item) {
    if (!widget.isOffline) return null;
    if (item is! MediaItem) return null;

    if (item.serverId == null) return null;

    final downloadProvider = context.read<DownloadProvider>();
    final globalKey = item.globalKey;

    // Get artwork reference and resolve to local path using hash (includes serverId)
    final artwork = downloadProvider.getArtworkPaths(globalKey);
    return artwork?.getLocalPath(DownloadStorageService.instance, ServerId(item.serverId!));
  }

  @override
  Widget build(BuildContext context) {
    return SettingsBuilder(
      prefs: const [
        SettingsService.viewMode,
        SettingsService.libraryDensity,
        SettingsService.episodePosterMode,
        SettingsService.showEpisodeNumberOnCards,
        SettingsService.hideSpoilers,
        SettingsService.showUnwatchedCount,
      ],
      builder: _buildContent,
    );
  }

  Widget _buildContent(BuildContext context) {
    final item = _effectiveItem(context);
    final ViewMode viewMode;
    if (widget.forceListMode) {
      viewMode = ViewMode.list;
    } else if (widget.forceGridMode) {
      viewMode = ViewMode.grid;
    } else {
      viewMode = SettingsService.instance.read(SettingsService.viewMode);
    }

    final semanticLabel = _buildSemanticLabel(item);
    final localPosterPath = _getLocalPosterPath(context, item);

    final cardWidget = viewMode == ViewMode.grid
        ? _buildGridCard(context, item, localPosterPath)
        : _MediaCardList(
            item: item,
            semanticLabel: semanticLabel,
            onTap: () => _handleTap(context, item),
            onTapDown: storeTapPosition,
            onLongPress: showContextMenuFromTap,
            onSecondaryTapDown: storeTapPosition,
            onSecondaryTap: showContextMenuFromTap,
            density: SettingsService.instance.read(SettingsService.libraryDensity),
            isOffline: widget.isOffline,
            localPosterPath: localPosterPath,
            showServerName: widget.showServerName,
            episodePosterModeOverride: widget.episodePosterModeOverride,
          );

    // Netflix desktop hover-expand: grid posters on desktop grow into an
    // elevated boxart overlay with quick actions. Additive and behind a
    // settings flag; mobile/TV get the untouched card.
    final enableHover =
        viewMode == ViewMode.grid &&
        item is MediaItem &&
        !PlatformDetector.isTV() &&
        PlatformDetector.isDesktop(context) &&
        SettingsService.instance.read(SettingsService.hoverExpandCards);

    final wrappedCard = enableHover
        ? HoverBoxartOverlay(
            overlayBuilder: (ctx, close) => _buildHoverOverlayContent(ctx, item, localPosterPath, close),
            child: cardWidget,
          )
        : cardWidget;

    // MediaContextMenu as a non-widget helper — only wrap with its key for
    // programmatic context menu access; gesture callbacks are on InkWell directly.
    return MediaContextMenu(
      key: contextMenuKey,
      item: item,
      onRefresh: widget.onRefresh,
      onRemoveFromContinueWatching: widget.onRemoveFromContinueWatching,
      onListRefresh: widget.onListRefresh,
      onTap: () => _handleTap(context, item),
      isInContinueWatching: widget.isInContinueWatching,
      collectionId: widget.collectionId,
      child: wrappedCard,
    );
  }

  /// Content of the Netflix desktop hover-expand overlay: a 16:9 art crop with
  /// the title, then a row of round quick-action buttons (Play, My List, more)
  /// and the match/meta line. Reuses this card's own handlers so behaviour
  /// stays consistent with a normal tap / context menu.
  Widget _buildHoverOverlayContent(BuildContext context, Object item, String? localPosterPath, VoidCallback close) {
    final t = tokens(context);
    final title = item is MediaPlaylist ? item.title : (item as MediaItem).displayTitle;

    Widget roundButton(IconData icon, VoidCallback onTap, {bool filled = false}) {
      return InkWell(
        onTap: onTap,
        customBorder: const CircleBorder(),
        child: Container(
          width: 34,
          height: 34,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            color: filled ? Colors.white : Colors.transparent,
            border: Border.all(color: Colors.white.withValues(alpha: filled ? 1 : 0.55), width: 1.5),
          ),
          child: AppIcon(icon, fill: 1, size: 17, color: filled ? Colors.black : Colors.white),
        ),
      );
    }

    return Container(
      decoration: BoxDecoration(
        color: t.surface,
        borderRadius: BorderRadius.circular(8),
        boxShadow: const [BoxShadow(color: Color(0x99000000), blurRadius: 40, offset: Offset(0, 18))],
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          AspectRatio(
            aspectRatio: 16 / 9,
            child: Stack(
              fit: StackFit.expand,
              children: [
                _wrapPosterHero(
                  _buildPosterImage(
                    context,
                    item,
                    isOffline: widget.isOffline,
                    localPosterPath: localPosterPath,
                    mixedHubContext: widget.mixedHubContext,
                    episodePosterModeOverride: widget.episodePosterModeOverride,
                    knownWidth: 300,
                    knownHeight: 169,
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 8,
                  child: Text(
                    title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      fontWeight: FontWeight.w800,
                      fontSize: 15,
                      shadows: [Shadow(color: Colors.black, blurRadius: 8)],
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Row(
              children: [
                roundButton(Symbols.play_arrow_rounded, () {
                  close();
                  _handleTap(context, item);
                }, filled: true),
                const SizedBox(width: 8),
                roundButton(Symbols.add_rounded, () => showContextMenuFromTap()),
                const Spacer(),
                roundButton(Symbols.expand_more_rounded, () {
                  close();
                  if (item is MediaItem) _navigateToFocusedDetail(context, item, isOffline: widget.isOffline);
                }),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Grid layout — inlined from former _MediaCardGrid, _PosterOverlay, and
  /// flattened Column. Semantics removed (InkWell provides button semantics).
  ///
  /// MergeSemantics collapses the card (texts, progress, button) into ONE
  /// semantics node. Browse rails/grids show dozens of cards and the
  /// platform-driven semantics pass runs every frame on TV boxes with an
  /// accessibility service active — node count is the cost driver. The card
  /// has a single action (tap; long-press menu), so merging is safe and gives
  /// screen readers one coherent announcement per card.
  Widget _buildGridCard(BuildContext context, Object item, String? localPosterPath) {
    if (widget.fullBleedImage) {
      return MergeSemantics(
        child: LayoutBuilder(
          builder: (context, constraints) {
            final cardWidth = widget.width ?? (constraints.hasBoundedWidth ? constraints.maxWidth : null);
            final cardHeight = widget.height ?? (constraints.hasBoundedHeight ? constraints.maxHeight : null);
            if (cardHeight == null) return _buildStandardGridCard(context, item, localPosterPath);
            return _buildFullBleedGridCard(context, item, localPosterPath, width: cardWidth, height: cardHeight);
          },
        ),
      );
    }

    return MergeSemantics(child: _buildStandardGridCard(context, item, localPosterPath));
  }

  Widget _buildFullBleedGridCard(
    BuildContext context,
    Object item,
    String? localPosterPath, {
    required double? width,
    required double height,
  }) {
    return SizedBox(
      width: width,
      height: height,
      // Pressable adds the press-down scale; the InkWell below keeps owning
      // the tap (it wins the gesture arena as the deeper recognizer).
      child: Pressable(
        onTap: () => _handleTap(context, item),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          canRequestFocus: false,
          onTap: () => _handleTap(context, item),
          onTapDown: storeTapPosition,
          onLongPress: showContextMenuFromTap,
          onSecondaryTapDown: storeTapPosition,
          onSecondaryTap: showContextMenuFromTap,
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          child: CardFocusBorder(
            borderRadius: tokens(context).radiusSm,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(tokens(context).radiusSm),
              child: Stack(
                fit: StackFit.expand,
                children: [
                  _wrapPosterHero(
                    _buildPosterImage(
                      context,
                      item,
                      isOffline: widget.isOffline,
                      localPosterPath: localPosterPath,
                      mixedHubContext: widget.mixedHubContext,
                      episodePosterModeOverride: widget.episodePosterModeOverride,
                      knownWidth: width,
                      knownHeight: height,
                    ),
                  ),
                  if (item is MediaItem) WatchedIndicator(item: item),
                  if (item is MediaItem)
                    Positioned(top: 6, left: 6, child: NewContentBadge(item: item)),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildStandardGridCard(BuildContext context, Object item, String? localPosterPath) {
    // Compute actual poster dimensions from card dimensions
    final posterWidth = widget.width != null ? widget.width! - 6 : null;
    final posterHeight = widget.height;

    // The focus border hugs the poster (captions stay outside it), matching
    // the full-bleed card treatment.
    final poster = CardFocusBorder(
      borderRadius: tokens(context).radiusSm,
      child: Stack(
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(tokens(context).radiusSm),
            child: _wrapPosterHero(
              _buildPosterImage(
                context,
                item,
                isOffline: widget.isOffline,
                localPosterPath: localPosterPath,
                mixedHubContext: widget.mixedHubContext,
                episodePosterModeOverride: widget.episodePosterModeOverride,
                knownWidth: posterHeight != null ? posterWidth : null,
                knownHeight: posterHeight,
              ),
            ),
          ),
          if (item is MediaItem) WatchedIndicator(item: item),
          if (item is MediaItem)
            Positioned(top: 6, left: 6, child: NewContentBadge(item: item)),
        ],
      ),
    );

    return SizedBox(
      width: widget.width,
      // Pressable adds the press-down scale; the InkWell below keeps owning
      // the tap (it wins the gesture arena as the deeper recognizer).
      child: Pressable(
        onTap: () => _handleTap(context, item),
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          canRequestFocus: false,
          onTap: () => _handleTap(context, item),
          onTapDown: storeTapPosition,
          onLongPress: showContextMenuFromTap,
          onSecondaryTapDown: storeTapPosition,
          onSecondaryTap: showContextMenuFromTap,
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(3, 3, 3, 1),
            child: Column(
              mainAxisSize: .min,
              crossAxisAlignment: .start,
              children: [
                // Poster with overlay
                if (posterHeight != null)
                  SizedBox(width: double.infinity, height: posterHeight, child: poster)
                else
                  Expanded(child: poster),
                const SizedBox(height: 2),
                // Title (flattened — no inner Column)
                if (item is MediaItem && _hasClickableTitle(item))
                  _ClickableText(
                    text: item.displayTitle,
                    style: const TextStyle(fontWeight: .w600, fontSize: 13, height: 1.1),
                    onTap: () => _navigateToFocusedDetail(context, item, isOffline: widget.isOffline),
                  )
                else
                  Text(
                    item is MediaPlaylist ? item.title : (item as MediaItem).displayTitle,
                    maxLines: 1,
                    overflow: .ellipsis,
                    style: const TextStyle(fontWeight: .w600, fontSize: 13, height: 1.1),
                  ),
                // Subtitle
                if (item is MediaPlaylist)
                  _MediaCardHelpers.buildPlaylistMeta(context, item)
                else if (item is MediaItem)
                  _MediaCardHelpers.buildMetadataSubtitle(context, item, isOffline: widget.isOffline),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _MediaCardList extends StatelessWidget {
  /// Either a [MediaItem] or a [MediaPlaylist].
  final Object item;
  final String semanticLabel;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final void Function(TapDownDetails)? onTapDown;
  final VoidCallback? onSecondaryTap;
  final void Function(TapDownDetails)? onSecondaryTapDown;
  final int density;
  final bool isOffline;
  final String? localPosterPath;
  final bool showServerName;
  final EpisodePosterMode? episodePosterModeOverride;

  const _MediaCardList({
    required this.item,
    required this.semanticLabel,
    required this.onTap,
    required this.onLongPress,
    this.onTapDown,
    this.onSecondaryTap,
    this.onSecondaryTapDown,
    required this.density,
    this.isOffline = false,
    this.localPosterPath,
    this.showServerName = false,
    this.episodePosterModeOverride,
  });

  bool _usesWideAspectRatio() {
    if (item is! MediaItem) return false;
    final EpisodePosterMode mode =
        episodePosterModeOverride ?? SettingsService.instance.read(SettingsService.episodePosterMode);
    return (item as MediaItem).usesWideAspectRatio(mode);
  }

  double _posterWidth() =>
      MediaCardListLayout.posterWidth(density: density, usesWideAspectRatio: _usesWideAspectRatio());

  double _posterHeight() =>
      MediaCardListLayout.posterHeight(density: density, usesWideAspectRatio: _usesWideAspectRatio());

  double get _titleFontSize => 13 + LibraryDensity.factor(density) * 3; // 13–16

  double get _metadataFontSize => 10 + LibraryDensity.factor(density) * 3; // 10–13

  double get _subtitleFontSize => 11 + LibraryDensity.factor(density) * 3; // 11–14

  double get _summaryFontSize {
    // Summary uses the same sizing as metadata text
    return _metadataFontSize;
  }

  int get _summaryMaxLines => density <= 2 ? 2 : density; // 2, 2, 3, 4, 5

  String _buildMetadataLine() {
    final parts = <String>[];

    if (item is MediaPlaylist) {
      final playlist = item as MediaPlaylist;
      if (playlist.leafCount != null && playlist.leafCount! > 0) {
        parts.add(t.playlists.itemCount(count: playlist.leafCount!));
      }

      if (playlist.durationMs != null) {
        parts.add(formatDurationTextual(playlist.durationMs!));
      }

      if (playlist.smart) {
        parts.add(t.playlists.smartPlaylist);
      }
    } else if (item is MediaItem) {
      final mi = item as MediaItem;

      if (mi.kind == MediaKind.collection) {
        final count = mi.childCount ?? mi.leafCount;
        if (count != null && count > 0) {
          parts.add(t.playlists.itemCount(count: count));
        }
      } else {
        if (mi.contentRating != null && mi.contentRating!.isNotEmpty) {
          final rating = formatContentRating(mi.contentRating);
          if (rating.isNotEmpty) {
            parts.add(rating);
          }
        }

        if (mi.year != null) {
          parts.add('${mi.year}');
        }

        if (mi.editionTitle case final editionTitle?) {
          parts.add(editionTitle);
        }

        if (mi.durationMs != null) {
          parts.add(formatDurationTextual(mi.durationMs!));
        }

        if (mi.rating != null) {
          parts.add('${formatRating(mi.rating!)}★');
        }

        if (mi.studio != null && mi.studio!.isNotEmpty) {
          parts.add(mi.studio!);
        }
      }
    }

    return parts.join(' • ');
  }

  String? _buildSubtitleText() {
    if (item is MediaPlaylist) {
      return null;
    } else if (item is MediaItem) {
      final mi = item as MediaItem;

      if (mi.parentIndex != null && mi.index != null) {
        final showEp = SettingsService.instance.read(SettingsService.showEpisodeNumberOnCards);
        return showEp ? 'S${mi.parentIndex} E${mi.index}' : 'S${mi.parentIndex}';
      }

      if (mi.displaySubtitle != null) {
        return mi.displaySubtitle;
      } else if (mi.parentTitle != null) {
        return mi.parentTitle;
      }
    }

    // Year is now shown in metadata line, so don't show it here
    return null;
  }

  String? _summary() {
    final it = item;
    if (it is MediaItem) return it.summary;
    if (it is MediaPlaylist) return it.summary;
    return null;
  }

  String _displayTitle() {
    final it = item;
    if (it is MediaItem) return it.displayTitle;
    if (it is MediaPlaylist) return it.displayTitle;
    return '';
  }

  Widget _buildEpisodeSubtitle(BuildContext context, MediaItem mi) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      color: tokens(context).textMuted.withValues(alpha: 0.85),
      fontSize: _subtitleFontSize,
    );
    final episodeTitle = mi.displaySubtitle ?? mi.displayTitle;
    final showEp = SettingsService.instance.read(SettingsService.showEpisodeNumberOnCards);
    final episodeNum = (showEp && mi.index != null) ? ' E${mi.index}' : '';
    return Row(
      children: [
        _ClickableText(
          text: 'S${mi.parentIndex}',
          style: style,
          onTap: () => _navigateToFocusedDetail(context, mi, isOffline: isOffline),
        ),
        Text('$episodeNum · ', style: style),
        Expanded(
          child: Text(episodeTitle, maxLines: 1, overflow: .ellipsis, style: style),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final metadataLine = _buildMetadataLine();
    final subtitle = _buildSubtitleText();

    // List rows keep the whole-row border; inside stroke so adjacent rows
    // don't overlap.
    return CardFocusBorder(
      borderRadius: tokens(context).radiusSm,
      strokeAlign: BorderSide.strokeAlignInside,
      // Pressable adds the press-down scale; the InkWell below keeps owning
      // the tap (it wins the gesture arena as the deeper recognizer).
      child: Pressable(
        onTap: onTap,
        child: InkWell(
          mouseCursor: SystemMouseCursors.click,
          canRequestFocus: false, // Keyboard handled by FocusableMediaCard
          onTap: onTap,
          onTapDown: onTapDown,
          onLongPress: onLongPress,
          onSecondaryTapDown: onSecondaryTapDown,
          onSecondaryTap: onSecondaryTap,
          borderRadius: BorderRadius.circular(tokens(context).radiusSm),
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              crossAxisAlignment: .start,
              children: [
                SizedBox(
                  width: _posterWidth(),
                  height: _posterHeight(),
                  child: Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(tokens(context).radiusSm),
                        child: _buildPosterImage(
                          context,
                          item,
                          isOffline: isOffline,
                          localPosterPath: localPosterPath,
                          episodePosterModeOverride: episodePosterModeOverride,
                        ),
                      ),
                      if (item is MediaItem) WatchedIndicator(item: item as MediaItem),
                      if (item is MediaItem)
                        Positioned(top: 6, left: 6, child: NewContentBadge(item: item as MediaItem)),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: .start,
                    mainAxisAlignment: .start,
                    children: [
                      if (item is MediaItem && _hasClickableTitle(item as MediaItem))
                        _ClickableText(
                          text: (item as MediaItem).displayTitle,
                          style: TextStyle(fontWeight: .w600, fontSize: _titleFontSize, height: 1.2),
                          onTap: () => _navigateToFocusedDetail(context, item as MediaItem, isOffline: isOffline),
                        )
                      else
                        Text(
                          _displayTitle(),
                          maxLines: 2,
                          overflow: .ellipsis,
                          style: TextStyle(fontWeight: .w600, fontSize: _titleFontSize, height: 1.2),
                        ),
                      const SizedBox(height: 4),
                      if (metadataLine.isNotEmpty) ...[
                        Text(
                          metadataLine,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens(context).textMuted.withValues(alpha: 0.9),
                            fontSize: _metadataFontSize,
                            fontWeight: .w500,
                          ),
                        ),
                        const SizedBox(height: 2),
                      ],
                      if (item is MediaItem &&
                          (item as MediaItem).isEpisode &&
                          (item as MediaItem).parentIndex != null &&
                          (item as MediaItem).parentId != null) ...[
                        _buildEpisodeSubtitle(context, item as MediaItem),
                        const SizedBox(height: 4),
                      ] else if (subtitle != null) ...[
                        Text(
                          subtitle,
                          maxLines: 1,
                          overflow: .ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens(context).textMuted.withValues(alpha: 0.85),
                            fontSize: _subtitleFontSize,
                          ),
                        ),
                        const SizedBox(height: 4),
                      ],
                      if (!(item is MediaItem &&
                              SettingsService.instance.read(SettingsService.hideSpoilers) &&
                              (item as MediaItem).shouldHideSpoiler) &&
                          _summary() != null) ...[
                        Text(
                          _summary()!,
                          maxLines: _summaryMaxLines,
                          overflow: .ellipsis,
                          style: Theme.of(context).textTheme.bodySmall?.copyWith(
                            color: tokens(context).textMuted.withValues(alpha: 0.7),
                            fontSize: _summaryFontSize,
                            height: 1.3,
                          ),
                        ),
                      ],
                      if (showServerName && item is MediaItem && (item as MediaItem).serverName != null) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            BackendBadge(
                              backend: (item as MediaItem).backend,
                              size: _metadataFontSize + 2,
                              color: tokens(context).textMuted.withValues(alpha: 0.6),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                (item as MediaItem).serverName!,
                                maxLines: 1,
                                overflow: .ellipsis,
                                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                                  color: tokens(context).textMuted.withValues(alpha: 0.6),
                                  fontSize: _metadataFontSize,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

Widget _buildPosterLoadingPlaceholder(BuildContext context, String _) {
  return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const SizedBox.expand());
}

IconData _mediaPosterFallbackIcon(MediaItem item) {
  if (item.isShow || item.isSeason || item.isEpisode) return Symbols.tv_rounded;
  return Symbols.movie_rounded;
}

Widget _buildPosterImage(
  BuildContext context,
  Object item, {
  bool isOffline = false,
  String? localPosterPath,
  bool mixedHubContext = false,
  EpisodePosterMode? episodePosterModeOverride,
  double? knownWidth,
  double? knownHeight,
}) {
  String? posterUrl;

  if (item is MediaPlaylist) {
    posterUrl = item.displayImagePath;

    return OptimizedMediaImage.playlist(
      client: isOffline ? null : context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId)),
      imagePath: posterUrl,
      width: knownWidth ?? double.infinity,
      height: knownHeight ?? double.infinity,
      fit: BoxFit.cover,
      placeholder: _buildPosterLoadingPlaceholder,
      localFilePath: localPosterPath,
    );
  } else if (item is MediaItem) {
    final EpisodePosterMode episodePosterMode =
        episodePosterModeOverride ?? SettingsService.instance.read(SettingsService.episodePosterMode);
    final hideSpoilers = SettingsService.instance.read(SettingsService.hideSpoilers);
    final shouldBlur =
        hideSpoilers && item.shouldHideSpoiler && episodePosterMode == EpisodePosterMode.episodeThumbnail;
    final primaryPosterUrl = item.posterThumb(mode: episodePosterMode, mixedHubContext: mixedHubContext);
    final posterFallbackUrl = item.posterThumbFallback(mode: episodePosterMode, mixedHubContext: mixedHubContext);
    final useRememberedFallback = posterFallbackUrl != null && _hasFailedPosterUrl(primaryPosterUrl);
    posterUrl = useRememberedFallback ? posterFallbackUrl : primaryPosterUrl;
    final mediaClient = isOffline ? null : context.tryGetMediaClientWithFallback(serverIdOrNull(item.serverId));
    final fallbackIcon = _mediaPosterFallbackIcon(item);

    Widget image;

    // Use thumb image type for 16:9 content (episodes, or movies in mixed hubs)
    if (item.usesWideAspectRatio(episodePosterMode, mixedHubContext: mixedHubContext)) {
      image = OptimizedMediaImage.thumb(
        client: mediaClient,
        imagePath: posterUrl,
        width: knownWidth ?? double.infinity,
        height: knownHeight ?? double.infinity,
        fit: BoxFit.cover,
        placeholder: _buildPosterLoadingPlaceholder,
        fallbackIcon: fallbackIcon,
        localFilePath: localPosterPath,
        blurHash: item.posterBlurHash,
      );
    } else {
      image = OptimizedMediaImage.poster(
        client: mediaClient,
        imagePath: posterUrl,
        width: knownWidth ?? double.infinity,
        height: knownHeight ?? double.infinity,
        fit: BoxFit.cover,
        placeholder: _buildPosterLoadingPlaceholder,
        fallbackIcon: fallbackIcon,
        errorWidget: posterFallbackUrl == null || useRememberedFallback
            ? null
            : (_, _, _) {
                _rememberFailedPosterUrl(primaryPosterUrl);
                return OptimizedMediaImage.poster(
                  client: mediaClient,
                  imagePath: posterFallbackUrl,
                  width: knownWidth ?? double.infinity,
                  height: knownHeight ?? double.infinity,
                  fit: BoxFit.cover,
                  placeholder: _buildPosterLoadingPlaceholder,
                  fallbackIcon: fallbackIcon,
                  blurHash: item.posterBlurHash,
                );
              },
        localFilePath: localPosterPath,
        blurHash: item.posterBlurHash,
      );
    }

    if (shouldBlur) {
      return ClipRect(
        child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 12, sigmaY: 12), child: image),
      );
    }
    return image;
  }

  return SkeletonLoader(
    child: const Center(child: AppIcon(Symbols.movie_rounded, fill: 1, size: 40, color: Colors.white54)),
  );
}

class _MediaCardHelpers {
  static Widget buildPlaylistMeta(BuildContext context, MediaPlaylist playlist) {
    if (playlist.leafCount != null && playlist.leafCount! > 0) {
      return Text(
        t.playlists.itemCount(count: playlist.leafCount!),
        maxLines: 1,
        overflow: .ellipsis,
        style: Theme.of(
          context,
        ).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted, fontSize: 11, height: 1.1),
      );
    }
    return const SizedBox.shrink();
  }

  /// Builds metadata subtitle (for collections, episodes, movies, shows)
  static Widget buildMetadataSubtitle(BuildContext context, MediaItem mi, {bool isOffline = false}) {
    final subtitleStyle = Theme.of(
      context,
    ).textTheme.bodySmall?.copyWith(color: tokens(context).textMuted, fontSize: 11, height: 1.1);

    // For collections, show item count
    if (mi.kind == MediaKind.collection) {
      final count = mi.childCount ?? mi.leafCount;
      if (count != null && count > 0) {
        return Text(
          t.playlists.itemCount(count: count),
          maxLines: 1,
          overflow: .ellipsis,
          style: subtitleStyle,
        );
      }
    }

    // For episodes, show "S# · Episode Title" with clickable season link
    if (mi.isEpisode && mi.parentIndex != null) {
      final episodeTitle = mi.displaySubtitle ?? mi.displayTitle;
      final showEp = SettingsService.instance.read(SettingsService.showEpisodeNumberOnCards);
      final episodeSuffix = (showEp && mi.index != null) ? ' E${mi.index}' : '';
      if (mi.parentId != null) {
        return Row(
          children: [
            _ClickableText(
              text: 'S${mi.parentIndex}',
              style: subtitleStyle,
              onTap: () => _navigateToFocusedDetail(context, mi, isOffline: isOffline),
            ),
            Text('$episodeSuffix · ', style: subtitleStyle),
            Expanded(
              child: Text(episodeTitle, maxLines: 1, overflow: .ellipsis, style: subtitleStyle),
            ),
          ],
        );
      }
      return Text(
        'S${mi.parentIndex}$episodeSuffix · $episodeTitle',
        maxLines: 1,
        overflow: .ellipsis,
        style: subtitleStyle,
      );
    }

    // For other media types, show subtitle/parent/year
    if (mi.displaySubtitle != null) {
      return Text(mi.displaySubtitle!, maxLines: 1, overflow: .ellipsis, style: subtitleStyle);
    } else if (mi.parentTitle != null) {
      return Text(mi.parentTitle!, maxLines: 1, overflow: .ellipsis, style: subtitleStyle);
    } else if (mi.year != null) {
      final edition = mi.editionTitle;
      return Text(
        edition != null ? '${mi.year} · $edition' : '${mi.year}',
        maxLines: 1,
        overflow: .ellipsis,
        style: subtitleStyle,
      );
    }

    return const SizedBox.shrink();
  }
}

/// Whether this media item has a clickable title that navigates somewhere.
/// Episodes/seasons navigate to their parent show; movies navigate to their detail page.
bool _hasClickableTitle(MediaItem mi) {
  if (mi.isEpisode) return mi.grandparentId != null;
  if (mi.isSeason) return mi.parentId != null;
  if (mi.isMovie) return true;
  return false;
}

void _navigateToFocusedDetail(BuildContext context, MediaItem item, {bool isOffline = false}) {
  navigateToMediaItemDetails(context, item, isOffline: isOffline);
}

/// Text widget that shows hover underline + pointer cursor only in pointer mode.
/// In keyboard/dpad mode, renders as plain text with no interaction.
class _ClickableText extends StatefulWidget {
  final String text;
  final TextStyle? style;
  final VoidCallback onTap;

  const _ClickableText({required this.text, this.style, required this.onTap});

  @override
  State<_ClickableText> createState() => _ClickableTextState();
}

class _ClickableTextState extends State<_ClickableText> {
  bool _isHovered = false;

  @override
  Widget build(BuildContext context) {
    final isKeyboard = InputModeTracker.isKeyboardMode(context);
    final baseStyle = widget.style ?? const TextStyle();

    if (isKeyboard) {
      return Text(widget.text, maxLines: 1, overflow: .ellipsis, style: baseStyle);
    }

    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _isHovered = true),
      onExit: (_) => setState(() => _isHovered = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: Text(
          widget.text,
          maxLines: 1,
          overflow: .ellipsis,
          style: baseStyle.copyWith(
            decoration: _isHovered ? TextDecoration.underline : null,
            decorationColor: baseStyle.color,
          ),
        ),
      ),
    );
  }
}

/// Skeleton placeholder with a subtle shimmer sweep on the full effects tier;
/// static semi-transparent fill on the reduced tier.
class SkeletonLoader extends StatefulWidget {
  final Widget? child;
  final BorderRadius? borderRadius;

  const SkeletonLoader({super.key, this.child, this.borderRadius});

  @override
  State<SkeletonLoader> createState() => _SkeletonLoaderState();
}

class _SkeletonLoaderState extends State<SkeletonLoader> with SingleTickerProviderStateMixin {
  AnimationController? _controller;

  @override
  void initState() {
    super.initState();
    if (!DevicePerformance.isReduced) {
      _controller = AnimationController(vsync: this, duration: const Duration(milliseconds: 1200))..repeat();
    }
  }

  @override
  void dispose() {
    _controller?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.075);
    final radius = widget.borderRadius ?? BorderRadius.circular(tokens(context).radiusSm);
    final controller = _controller;

    if (controller == null) {
      return Container(
        decoration: BoxDecoration(color: base, borderRadius: radius),
        child: widget.child,
      );
    }

    final highlight = Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.14);
    return AnimatedBuilder(
      animation: controller,
      builder: (context, child) {
        // Sweep center travels -0.3 → 1.3 so the band fully enters and exits.
        final t = -0.3 + controller.value * 1.6;
        return Container(
          decoration: BoxDecoration(
            borderRadius: radius,
            gradient: LinearGradient(
              begin: .centerLeft,
              end: .centerRight,
              colors: [base, highlight, base],
              stops: [(t - 0.25).clamp(0.0, 1.0), t.clamp(0.0, 1.0), (t + 0.25).clamp(0.0, 1.0)],
            ),
          ),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
