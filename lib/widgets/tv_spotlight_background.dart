import 'dart:io';
import 'dart:ui' show ImageFilter;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';

import '../i18n/strings.g.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_server_client.dart';
import '../providers/watch_state_store.dart';
import '../services/device_performance.dart';
import '../services/image_cache_service.dart';
import '../utils/content_utils.dart';
import '../utils/formatters.dart';
import '../utils/layout_constants.dart';
import '../utils/media_image_helper.dart';
import 'app_icon.dart';
import 'fitting_title_text.dart';
import 'media_rating_badge.dart';
import 'optimized_media_image.dart' show blurArtwork;

class TvSpotlightBackground extends StatelessWidget {
  final MediaItem? item;
  final MediaServerClient? client;
  final bool hideSpoilers;
  final double contentBottom;
  final double? contentTop;
  final double? contentLeft;
  final VoidCallback? onPrimaryAction;
  final Widget? actions;
  final bool compact;
  final bool showPrimaryAction;
  final bool showInfo;

  /// Fades the info block (logo/title/metadata/summary/actions) in and out
  /// without touching the backdrop. Used by the TV home to hide the billboard
  /// text once the browse rail is revealed while the artwork keeps showing.
  final double infoOpacity;

  /// Melt the bottom of the backdrop into the scaffold background so a docked
  /// content rail blends in (Netflix billboard). Off by default so backdrop-only
  /// consumers (e.g. media detail) keep the lighter gradient.
  final bool deepBottomScrim;

  /// Slow one-shot "settle" zoom on the backdrop art per item. Skipped on the
  /// reduced-performance tier.
  final bool kenBurns;

  /// Browse rail is slid up over the billboard. The info block shrinks to
  /// logo + metadata (no genres/summary/actions) and the backdrop dims, so the
  /// row labels stay readable and the artwork reads as atmosphere instead of
  /// noise — while still telling you *which* title is focused.
  final bool railRevealed;
  final String? Function(String? artworkPath)? localArtworkPathResolver;

  const TvSpotlightBackground({
    super.key,
    required this.item,
    required this.client,
    this.hideSpoilers = false,
    this.contentBottom = 360,
    this.contentTop,
    this.contentLeft,
    this.onPrimaryAction,
    this.actions,
    this.compact = false,
    this.showPrimaryAction = true,
    this.showInfo = true,
    this.infoOpacity = 1.0,
    this.deepBottomScrim = false,
    this.kenBurns = false,
    this.railRevealed = false,
    this.localArtworkPathResolver,
  });

  /// How far the backdrop dims once the rail covers it (top → bottom).
  static const double _railDimAlphaTop = 0.30;
  static const double _railDimAlphaBottom = 0.70;

  /// Blur applied when only a portrait poster is available — a sharp
  /// `cover` crop of a poster on a 16:9 surface is a giant face, never a
  /// backdrop.
  static const double _posterFillBlurSigma = 40;

  double _scale(BuildContext context) => TvLayoutConstants.scaleOf(context);

  @override
  Widget build(BuildContext context) {
    final media = item;
    final bgColor = Theme.of(context).scaffoldBackgroundColor;

    return AnimatedSwitcher(
      // Reduced tier swaps instantly: the cross-fade keeps two full-screen
      // stacks (backdrop + two full-screen gradients each) blending per frame.
      duration: DevicePerformance.reducedDuration(const Duration(milliseconds: 280)),
      switchInCurve: Curves.easeOutCubic,
      switchOutCurve: Curves.easeOutCubic,
      child: SizedBox.expand(
        key: ValueKey(media?.globalKey ?? 'empty_spotlight'),
        child: Stack(
          fit: StackFit.expand,
          children: [
            if (media != null) _animatedArtwork(media, _buildArtwork(context, media)) else ColoredBox(color: bgColor),
            _buildHorizontalScrim(bgColor, isLight: Theme.of(context).brightness == Brightness.light),
            // Rail-reveal dim: matches the rail's own slide duration so the
            // artwork recedes exactly as the rows arrive.
            IgnorePointer(
              child: AnimatedContainer(
                duration: DevicePerformance.reducedDuration(const Duration(milliseconds: 280)),
                curve: Curves.easeOut,
                // Light on top, heavy at the bottom: the artwork keeps living
                // behind the billboard info while the rows stay readable.
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      bgColor.withValues(alpha: railRevealed ? _railDimAlphaTop : 0.0),
                      bgColor.withValues(alpha: railRevealed ? _railDimAlphaBottom : 0.0),
                    ],
                  ),
                ),
              ),
            ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: deepBottomScrim
                    ? LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          bgColor.withValues(alpha: 0.90),
                          bgColor,
                        ],
                        stops: const [0.0, 0.30, 0.78, 1.0],
                      )
                    : LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.black.withValues(alpha: 0.45),
                          Colors.transparent,
                          bgColor.withValues(alpha: 0.96),
                        ],
                        stops: const [0.0, 0.38, 1.0],
                      ),
              ),
            ),
            if (media != null && showInfo)
              // While browsing the info pins top-left (Netflix) so it never
              // hides behind the revealed rail; at rest it sits above it.
              Positioned(
                left: contentLeft ?? TvLayoutConstants.horizontalInset,
                right: MediaQuery.sizeOf(context).width * 0.34,
                top: railRevealed ? (contentTop ?? 0) : contentTop,
                bottom: railRevealed ? null : contentBottom,
                child: AnimatedOpacity(
                  opacity: infoOpacity,
                  duration: const Duration(milliseconds: 280),
                  curve: Curves.easeOut,
                  // ExcludeFocus (not just IgnorePointer): when faded out the
                  // Play/More-info buttons must also leave the D-pad focus tree,
                  // or traversal could land on invisible controls.
                  child: ExcludeFocus(
                    excluding: infoOpacity == 0,
                    child: IgnorePointer(
                      ignoring: infoOpacity == 0,
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final anchor = railRevealed ? Alignment.topLeft : Alignment.bottomLeft;
                          if (!constraints.hasBoundedHeight ||
                              constraints.maxHeight <= 0 ||
                              constraints.maxWidth <= 0) {
                            return Align(alignment: anchor, child: _buildInfo(context, media));
                          }

                          return Align(
                            alignment: anchor,
                            child: FittedBox(
                              fit: BoxFit.scaleDown,
                              alignment: anchor,
                              child: SizedBox(width: constraints.maxWidth, child: _buildInfo(context, media)),
                            ),
                          );
                        },
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  /// Wraps the backdrop in a slow one-shot settle-zoom. Keyed per item by the
  /// enclosing AnimatedSwitcher, so each swap restarts from 1.0. No-op on the
  /// reduced tier or when [kenBurns] is off.
  Widget _animatedArtwork(MediaItem media, Widget child) {
    if (!kenBurns || DevicePerformance.isReduced) return child;
    return ClipRect(
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 1.0, end: 1.06),
        duration: const Duration(seconds: 10),
        curve: Curves.easeOut,
        child: RepaintBoundary(child: child),
        builder: (context, scale, inner) => Transform.scale(scale: scale, child: inner),
      ),
    );
  }

  Widget _buildArtwork(BuildContext context, MediaItem media) {
    final size = MediaQuery.sizeOf(context);
    final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
    final containerAspect = size.width / size.height;
    // Landscape art only. thumbPath is a portrait poster and is handled
    // separately below — cover-cropping it to 16:9 yields a giant face.
    final artCandidates = <String?>[
      media.heroArt(containerAspectRatio: containerAspect) ??
          media.grandparentArtPath ??
          media.artPath ??
          media.backgroundSquarePath,
      media.grandparentArtPath,
      media.artPath,
      media.backgroundSquarePath,
    ];
    final posterFill = artCandidates.every((path) => path == null || path.isEmpty);
    if (posterFill) artCandidates.add(media.thumbPath);
    for (final candidate in artCandidates) {
      final localPath = localArtworkPathResolver?.call(candidate);
      if (localPath != null && File(localPath).existsSync()) {
        return _posterFill(
          posterFill,
          blurArtwork(
            Image.file(
              File(localPath),
              fit: BoxFit.cover,
              // Top-anchor so tall backdrops don't clip faces/titles off the top.
              alignment: Alignment.topCenter,
              errorBuilder: (context, error, stackTrace) =>
                  ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
            ),
          ),
        );
      }
    }

    final artPath = artCandidates.firstWhere((path) => path != null && path.isNotEmpty, orElse: () => null);

    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: artPath,
      maxWidth: size.width,
      maxHeight: size.height,
      devicePixelRatio: dpr,
      imageType: ImageType.art,
    );

    if (imageUrl.isEmpty) {
      return ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest);
    }

    final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
      displayWidth: (size.width * dpr).round(),
      displayHeight: (size.height * dpr).round(),
      imageType: ImageType.art,
    );

    return _posterFill(
      posterFill,
      blurArtwork(
        CachedNetworkImage(
          imageUrl: imageUrl,
          cacheManager: PlexImageCacheManager.instance,
          fit: BoxFit.cover,
          // Top-anchor so tall backdrops don't clip faces/titles off the top.
          alignment: Alignment.topCenter,
          memCacheHeight: memHeight,
          // Explicit fades: the package defaults (500ms in / 1000ms out) double
          // up with the AnimatedSwitcher cross-fade above on every swap.
          fadeInDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
          fadeOutDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
          placeholder: (context, url) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
          errorBuilder: (context, error, stackTrace) =>
              ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
        ),
      ),
    );
  }

  /// Only a portrait poster available: blur it into an atmospheric fill
  /// instead of showing a hugely magnified crop. `blurArtwork` is the
  /// screenshot-obfuscation switch, not a design tool — hence the explicit
  /// filter here.
  Widget _posterFill(bool enabled, Widget child) {
    if (!enabled || DevicePerformance.isReduced) return child;
    return ImageFiltered(
      imageFilter: ImageFilter.blur(sigmaX: _posterFillBlurSigma, sigmaY: _posterFillBlurSigma),
      child: child,
    );
  }

  /// Left-to-right wash that carries the billboard text and the nav rail.
  ///
  /// The text is theme-coloured, so in light mode it is near-black over the
  /// artwork — a 0.86 white wash still leaves a bright backdrop showing
  /// through and the description drowns in it. Light mode therefore washes
  /// harder and further before releasing the artwork; dark mode keeps its
  /// original, already-legible ramp.
  Widget _buildHorizontalScrim(Color bgColor, {required bool isLight}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.centerLeft,
          end: Alignment.centerRight,
          colors: isLight
              ? [bgColor.withValues(alpha: 0.96), bgColor.withValues(alpha: 0.62), Colors.transparent]
              : [bgColor.withValues(alpha: 0.86), bgColor.withValues(alpha: 0.32), Colors.transparent],
          stops: isLight ? const [0.0, 0.62, 1.0] : const [0.0, 0.56, 1.0],
        ),
      ),
    );
  }

  Widget _buildInfo(BuildContext context, MediaItem media) {
    final scale = _scale(context);
    final colorScheme = Theme.of(context).colorScheme;
    // Dimmed text reads as "secondary" on a dark surface, but as "washed out"
    // on a light one: black at 66% over bright artwork loses far more contrast
    // than white at 66% over a dark backdrop. Light mode keeps more ink.
    final isLight = Theme.of(context).brightness == Brightness.light;
    final genreAlpha = isLight ? 0.82 : 0.66;
    final summaryAlpha = isLight ? 0.94 : 0.78;
    final spoilerAlpha = isLight ? 0.90 : 0.72;
    final shouldHideSpoiler = hideSpoilers && media.shouldHideSpoiler;
    final summary = shouldHideSpoiler ? null : media.summary;
    final title = media.grandparentTitle ?? media.displayTitle;

    return Column(
      crossAxisAlignment: .start,
      mainAxisSize: .min,
      children: [
        _buildLogoOrTitle(context, media, title),
        SizedBox(height: _sectionGap(scale)),
        _buildMetadataLine(context, media),
        if (!railRevealed && !compact && (media.genres?.isNotEmpty ?? false)) ...[
          SizedBox(height: 6 * scale),
          Text(
            media.genres!.take(3).join('  •  '),
            maxLines: 1,
            overflow: .ellipsis,
            style: TextStyle(
              color: colorScheme.onSurface.withValues(alpha: genreAlpha),
              fontSize: _metadataFontSize(scale),
              fontWeight: .w500,
              letterSpacing: 0.1,
            ),
          ),
        ],
        if (railRevealed) ...[
          // Logo + metadata only: enough to identify the focused row item
          // without competing with the posters right below it.
        ] else if (summary != null && summary.isNotEmpty) ...[
          SizedBox(height: _sectionGap(scale)),
          Text(
            summary,
            maxLines: 3,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: summaryAlpha),
              fontSize: _summaryFontSize(scale),
              height: compact ? 1.34 : 1.45,
            ),
          ),
        ] else if (shouldHideSpoiler && media.isEpisode) ...[
          SizedBox(height: _sectionGap(scale)),
          Text(
            media.title ?? '',
            maxLines: 2,
            overflow: .ellipsis,
            style: Theme.of(context).textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurface.withValues(alpha: spoilerAlpha),
              fontSize: _summaryFontSize(scale),
              height: compact ? 1.34 : 1.45,
            ),
          ),
        ],
        if (!railRevealed && (showPrimaryAction || actions != null)) ...[
          SizedBox(height: (compact ? 18 : 26) * scale),
          actions ?? _buildPrimaryAction(context, media),
        ],
      ],
    );
  }

  Widget _buildLogoOrTitle(BuildContext context, MediaItem media, String title) {
    final scale = _scale(context);
    final logoPath = media.clearLogoPath;
    final logoWidth = _logoWidth(scale);
    final logoHeight = _logoHeight(scale);
    if (logoPath == null || logoPath.isEmpty) {
      return SizedBox(width: logoWidth, height: logoHeight, child: _buildTitle(context, title));
    }

    final localLogoPath = localArtworkPathResolver?.call(logoPath);
    if (localLogoPath != null && File(localLogoPath).existsSync()) {
      return SizedBox(
        width: logoWidth,
        height: logoHeight,
        child: blurArtwork(
          Image.file(
            File(localLogoPath),
            fit: BoxFit.contain,
            alignment: .centerLeft,
            errorBuilder: (context, error, stackTrace) => _buildTitle(context, title),
          ),
          sigma: 10,
          clip: false,
        ),
      );
    }

    final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: logoPath,
      maxWidth: logoWidth,
      maxHeight: logoHeight,
      devicePixelRatio: dpr,
      imageType: ImageType.logo,
    );
    if (imageUrl.isEmpty) return _buildTitle(context, title);

    return SizedBox(
      width: logoWidth,
      height: logoHeight,
      child: blurArtwork(
        CachedNetworkImage(
          imageUrl: imageUrl,
          cacheManager: PlexImageCacheManager.instance,
          fit: BoxFit.contain,
          alignment: .centerLeft,
          memCacheWidth: (logoWidth * dpr).clamp(200, 1000).round(),
          fadeInDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
          fadeOutDuration: DevicePerformance.reducedDuration(const Duration(milliseconds: 200)),
          placeholder: (context, url) => const SizedBox.shrink(),
          errorBuilder: (context, error, stackTrace) => _buildTitle(context, title),
        ),
        sigma: 10,
        clip: false,
      ),
    );
  }

  Widget _buildTitle(BuildContext context, String title) {
    final scale = _scale(context);
    final colorScheme = Theme.of(context).colorScheme;
    return FittingTitleText(
      title,
      style: Theme.of(context).textTheme.displaySmall?.copyWith(
        color: colorScheme.onSurface,
        fontSize: _titleFontSize(scale),
        fontWeight: .w800,
        shadows: [Shadow(color: colorScheme.surface.withValues(alpha: 0.8), blurRadius: 12)],
      ),
    );
  }

  Widget _buildMetadataLine(BuildContext context, MediaItem media) {
    final scale = _scale(context);
    final colorScheme = Theme.of(context).colorScheme;
    final episodeLabel = formatSeasonEpisodeLabel(media.parentIndex, media.index);
    final textStyle = TextStyle(
      color: colorScheme.onSurface,
      fontSize: _metadataFontSize(scale),
      fontWeight: .w700,
      letterSpacing: 0.1,
    );
    final children = <Widget>[];

    void addSeparator() {
      if (children.isNotEmpty) children.add(Text('  •  ', maxLines: 1, style: textStyle));
    }

    void addTextPart(String text) {
      addSeparator();
      children.add(Text(text, maxLines: 1, style: textStyle));
    }

    void addWidgetPart(Widget widget) {
      addSeparator();
      children.add(widget);
    }

    if (media.isEpisode && episodeLabel != null) addTextPart(episodeLabel);
    if (media.isMovie) {
      addTextPart(t.discover.movie);
    } else if (media.isShow) {
      addTextPart(t.discover.tvShow);
    }
    final ratingBadge = MediaRatingBadge.inlineForMedia(
      item: media,
      foregroundColor: textStyle.color,
      iconSize: textStyle.fontSize,
      spacing: 4 * scale,
      textStyle: textStyle,
    );
    if (ratingBadge != null) {
      addWidgetPart(ratingBadge);
    }
    if (media.contentRating != null) addTextPart(formatContentRating(media.contentRating!));
    if (media.durationMs != null) addTextPart(formatDurationTextual(media.durationMs!));
    if (media.isEpisode && media.originallyAvailableAt != null) {
      addTextPart(formatFullDate(media.originallyAvailableAt!));
    } else if (media.year != null) {
      addTextPart(media.year.toString());
    }
    if (media.isWatched && !media.hasActiveProgress) {
      addWidgetPart(
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.check_circle_rounded, fill: 1, size: textStyle.fontSize, color: textStyle.color),
            SizedBox(width: 4 * scale),
            Text(t.discover.watched, maxLines: 1, style: textStyle),
          ],
        ),
      );
    }

    if (children.isEmpty) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const NeverScrollableScrollPhysics(),
      child: Row(mainAxisSize: MainAxisSize.min, children: children),
    );
  }

  double _sectionGap(double scale) => (compact ? 10 : 16) * scale;

  double _logoWidth(double scale) =>
      ((compact || railRevealed) ? TvLayoutConstants.compactHeroLogoWidth : TvLayoutConstants.heroLogoWidth) * scale;

  double _logoHeight(double scale) =>
      ((compact || railRevealed) ? TvLayoutConstants.compactHeroLogoHeight : TvLayoutConstants.heroLogoHeight) * scale;

  double _titleFontSize(double scale) => (compact ? 44 : 66) * scale;

  double _metadataFontSize(double scale) => (compact ? 16 : 20) * scale;

  double _summaryFontSize(double scale) => (compact ? 18 : 22) * scale;

  Widget _buildPrimaryAction(BuildContext context, MediaItem media) {
    final scale = _scale(context);
    media = context.withFreshWatchState(media);
    final hasProgress = media.hasActiveProgress;
    final minutesLeft = hasProgress && media.durationMs != null && media.viewOffsetMs != null
        ? ((media.durationMs! - media.viewOffsetMs!) / 60_000).round()
        : 0;

    return GestureDetector(
      onTap: onPrimaryAction,
      child: Container(
        padding: .symmetric(horizontal: (compact ? 24 : 30) * scale, vertical: (compact ? 12 : 15) * scale),
        decoration: BoxDecoration(color: Colors.white, borderRadius: BorderRadius.circular(32 * scale)),
        child: Row(
          mainAxisSize: .min,
          children: [
            AppIcon(Symbols.play_arrow_rounded, fill: 1, size: (compact ? 24 : 28) * scale, color: Colors.black),
            SizedBox(width: (compact ? 10 : 12) * scale),
            Text(
              hasProgress ? t.discover.minutesLeft(minutes: minutesLeft) : t.common.play,
              style: TextStyle(color: Colors.black, fontSize: (compact ? 16 : 18) * scale, fontWeight: .w800),
            ),
          ],
        ),
      ),
    );
  }
}
