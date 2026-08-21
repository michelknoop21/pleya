import 'dart:ui' as ui;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../services/device_performance.dart';
import '../services/download_artwork_helpers.dart';
import '../services/image_cache_service.dart';
import '../utils/home_hero_layout.dart';
import '../utils/media_image_helper.dart';
import 'optimized_media_image.dart' show blurArtwork;

/// The home hero's artwork: a full-hero ambient wash beneath a smaller,
/// cropped-free sharp layer, or (on a wide box, or with no 16:9/square source
/// to shape an island from) a single full-bleed frame — the same layout
/// [HomeHeroArtGeometry] and [BillboardArtKind] always described, just split
/// into two layers instead of one so a narrow box never leaves a bare panel
/// under the sharp island.
///
/// Extracted from `_buildHeroItemContent` so [HomeHeroArtGeometry] can be
/// tested against real layer rects without pumping the whole discover
/// screen. Parallax, the fade-in/zoom entrance, and the blend into the
/// ambient layer (or into the scaffold background, full-bleed) all live
/// here; the scrim, title, and everything else stay in the hero item widget.
class HomeHeroArtwork extends StatelessWidget {
  const HomeHeroArtwork({
    super.key,
    required this.client,
    required this.art,
    required this.geometry,
    this.scrollController,
  });

  static const Key artworkKey = Key('home-hero-artwork');
  static const Key ambientKey = Key('home-hero-artwork-ambient');
  static const Key frameKey = Key('home-hero-artwork-frame');
  static const Key fadeKey = Key('home-hero-artwork-fade');
  static const Key sideFadeKey = Key('home-hero-artwork-side-fade');

  static const Listenable _noScroll = AlwaysStoppedAnimation(0.0);

  /// How far the ambient layer extends past the canvas on every side, so its
  /// own blur never shows a soft edge inside the visible hero.
  static const double _ambientOverscan = 32;

  static const double _ambientBlurSigma = 18;

  /// Darkening wash over the ambient layer, on top of its own blur — the
  /// island's subject needs to stay the clear focal point, not the
  /// background behind it.
  static const double _ambientWashAlpha = 0.55;

  /// The island's side blend, as a fraction of its own width from each edge.
  /// Only used on the square branch — the widescreen island is already
  /// screen-wide, so there is no side to blend.
  static const double _horizontalFadeEdgeFraction = 0.08;

  final MediaServerClient? client;
  final BillboardArt art;
  final HomeHeroArtGeometry geometry;
  final ScrollController? scrollController;

  /// Alpha mask for the sharp layer's bottom blend into the ambient layer
  /// beneath it. `BlendMode.dstIn` keeps the sharp layer wherever this
  /// gradient is white and removes it wherever it is transparent, so the
  /// colour channels here are irrelevant — only the alpha ramp matters.
  ///
  /// Pure and `@visibleForTesting` so the ramp itself (where it starts, that
  /// it always ends fully transparent) can be pinned without pumping a
  /// widget tree.
  @visibleForTesting
  static LinearGradient verticalFadeMask({required double sharpHeight, required double fadeHeight}) {
    final fadeStart = sharpHeight <= 0 ? 0.0 : (1 - (fadeHeight / sharpHeight)).clamp(0.0, 1.0);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.white, Colors.white, Colors.transparent],
      stops: [0.0, fadeStart, 1.0],
    );
  }

  /// Alpha mask for the square island's left/right blend. See
  /// [verticalFadeMask] for why only the alpha ramp matters.
  @visibleForTesting
  static const LinearGradient horizontalFadeMask = LinearGradient(
    begin: Alignment.centerLeft,
    end: Alignment.centerRight,
    colors: [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
    stops: [0.0, _horizontalFadeEdgeFraction, 1 - _horizontalFadeEdgeFraction, 1.0],
  );

  @override
  Widget build(BuildContext context) {
    if (!geometry.hasSharpForeground) return const SizedBox.shrink();

    final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: art.path,
      maxWidth: geometry.requestWidth,
      maxHeight: geometry.requestHeight,
      devicePixelRatio: dpr,
      imageType: ImageType.art,
    );
    final imageCacheKey = artworkStorageKey(imageUrl);
    final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
      displayWidth: (geometry.requestWidth * dpr).round(),
      displayHeight: (geometry.requestHeight * dpr).round(),
      imageType: ImageType.art,
    );

    return ClipRect(
      key: HomeHeroArtwork.artworkKey,
      child: AnimatedBuilder(
        animation: scrollController ?? HomeHeroArtwork._noScroll,
        builder: (context, child) {
          final scrollOffset = (scrollController?.hasClients ?? false) ? scrollController!.offset : 0.0;
          return Transform.translate(offset: Offset(0, scrollOffset * 0.3), child: child);
        },
        child: TweenAnimationBuilder<double>(
          tween: Tween(begin: 0.0, end: 1.0),
          duration: const Duration(milliseconds: 800),
          curve: Curves.easeOut,
          builder: (context, value, child) {
            // The zoom-in entrance is a crop on a frame that is already
            // exactly hero-sized, so it only runs on the full-bleed frame.
            // The island frame is smaller than its own canvas on purpose —
            // zooming it would just as visibly overshoot its own bounds.
            final scale = geometry.coversHero ? 1.0 + (0.1 * (1 - value)) : 1.0;
            return Transform.scale(
              scale: scale,
              child: Opacity(opacity: value, child: child),
            );
          },
          child: Stack(
            children: [
              if (geometry.useAmbientLayer)
                _buildAmbientLayer(context, imageUrl: imageUrl, cacheKey: imageCacheKey, memHeight: memHeight),
              _buildSharpLayer(context, imageUrl: imageUrl, cacheKey: imageCacheKey, memHeight: memHeight),
            ],
          ),
        ),
      ),
    );
  }

  /// Full-hero wash of the same source, blurred and darkened, so an island
  /// smaller than the hero never leaves a bare panel around it. Reuses the
  /// sharp layer's own `imageUrl`/`cacheKey` — same transcoder request, same
  /// cache entry, no second download for a differently-cropped variant.
  Widget _buildAmbientLayer(
    BuildContext context, {
    required String imageUrl,
    required String cacheKey,
    required int memHeight,
  }) {
    final image = blurArtwork(
      CachedNetworkImage(
        imageUrl: imageUrl,
        cacheKey: cacheKey,
        cacheManager: PlexImageCacheManager.instance,
        fit: BoxFit.cover,
        alignment: Alignment.topCenter,
        memCacheHeight: memHeight,
        placeholder: (context, url) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
        errorBuilder: (context, error, stackTrace) =>
            ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      ),
    );

    return Positioned(
      key: HomeHeroArtwork.ambientKey,
      left: -_ambientOverscan,
      top: -_ambientOverscan,
      right: -_ambientOverscan,
      bottom: -_ambientOverscan,
      child: Builder(
        builder: (context) => Stack(
          fit: StackFit.expand,
          children: [
            ImageFiltered(
              enabled: !DevicePerformance.isReduced,
              imageFilter: ui.ImageFilter.blur(sigmaX: _ambientBlurSigma, sigmaY: _ambientBlurSigma),
              child: image,
            ),
            ColoredBox(color: Theme.of(context).scaffoldBackgroundColor.withValues(alpha: _ambientWashAlpha)),
          ],
        ),
      ),
    );
  }

  /// The sharp (or blurred-fallback) foreground: full-bleed `BoxFit.cover`
  /// when [HomeHeroArtGeometry.coversHero], or a smaller, cropped-free
  /// `BoxFit.contain` island that blends into the ambient layer beneath it.
  Widget _buildSharpLayer(
    BuildContext context, {
    required String imageUrl,
    required String cacheKey,
    required int memHeight,
  }) {
    final image = CachedNetworkImage(
      imageUrl: imageUrl,
      cacheKey: cacheKey,
      cacheManager: PlexImageCacheManager.instance,
      // A full-bleed frame (`coversHero`) fills a box with a different ratio
      // than the source, so it still needs `cover`. The island frame is
      // already sized to the source's own ratio (see `homeHeroArtGeometry`),
      // so `contain` there is crop-free rather than a no-op.
      fit: geometry.coversHero ? BoxFit.cover : BoxFit.contain,
      alignment: Alignment.topCenter,
      memCacheHeight: memHeight,
      placeholder: (context, url) => ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
      errorBuilder: (context, error, stackTrace) =>
          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
    );

    final rendered = blurArtwork(
      art.shouldBlur ? ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: image) : image,
    );

    Widget frame = SizedBox(
      key: HomeHeroArtwork.frameKey,
      width: geometry.sharpWidth,
      height: geometry.sharpHeight,
      // Full-bleed frame only: a backstop so any `cover` rounding slop reads
      // as the scaffold background continuing, never a hard image edge. The
      // island frame deliberately has none — a mismatched-ratio letterbox
      // gap there must show the ambient layer through it, not a flat panel.
      child: geometry.coversHero
          ? ColoredBox(color: Theme.of(context).scaffoldBackgroundColor, child: rendered)
          : rendered,
    );

    if (geometry.useAmbientLayer) {
      frame = ShaderMask(
        key: HomeHeroArtwork.fadeKey,
        blendMode: BlendMode.dstIn,
        shaderCallback: (rect) => verticalFadeMask(
          sharpHeight: geometry.sharpHeight,
          fadeHeight: geometry.sharpFadeHeight,
        ).createShader(rect),
        child: frame,
      );
      if (art.kind == BillboardArtKind.square) {
        frame = ShaderMask(
          key: HomeHeroArtwork.sideFadeKey,
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => horizontalFadeMask.createShader(rect),
          child: frame,
        );
      }
    }

    return Align(alignment: Alignment.topCenter, child: frame);
  }
}
