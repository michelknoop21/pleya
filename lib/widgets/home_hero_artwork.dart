import 'dart:ui' as ui;

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/material.dart';

import '../media/media_item.dart';
import '../media/media_server_client.dart';
import '../services/download_artwork_helpers.dart';
import '../services/image_cache_service.dart';
import '../utils/home_hero_layout.dart';
import '../utils/media_image_helper.dart';
import 'optimized_media_image.dart' show blurArtwork;

/// The home hero's sharp (or blurred-fallback) artwork layer.
///
/// Extracted from `_buildHeroItemContent` so [HomeHeroArtGeometry] can be
/// tested against real frame/fade rects without pumping the whole discover
/// screen. Parallax, the fade-in/zoom entrance, and the bottom fade into the
/// scaffold background all live here; the scrim, title, and everything else
/// stay in the hero item widget.
class HomeHeroArtwork extends StatelessWidget {
  const HomeHeroArtwork({
    super.key,
    required this.client,
    required this.art,
    required this.geometry,
    this.scrollController,
  });

  static const Key artworkKey = Key('home-hero-artwork');
  static const Key frameKey = Key('home-hero-artwork-frame');
  static const Key fadeKey = Key('home-hero-artwork-fade');

  static const Listenable _noScroll = AlwaysStoppedAnimation(0.0);

  final MediaServerClient? client;
  final BillboardArt art;
  final HomeHeroArtGeometry geometry;
  final ScrollController? scrollController;

  @override
  Widget build(BuildContext context) {
    if (geometry.width <= 0 || geometry.height <= 0) return const SizedBox.shrink();

    return ClipRect(
      key: HomeHeroArtwork.artworkKey,
      child: Stack(
        children: [
          Align(
            alignment: Alignment.topCenter,
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
                  // The zoom-in entrance is a horizontal crop on a frame that
                  // is already exactly screen-wide, so it only runs while the
                  // frame covers the whole hero.
                  final scale = geometry.coversHero ? 1.0 + (0.1 * (1 - value)) : 1.0;
                  return Transform.scale(
                    scale: scale,
                    child: Opacity(opacity: value, child: child),
                  );
                },
                child: Builder(
                  builder: (context) {
                    final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
                    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
                      client: client,
                      thumbPath: art.path,
                      maxWidth: geometry.width,
                      maxHeight: geometry.requestHeight,
                      devicePixelRatio: dpr,
                      imageType: ImageType.art,
                    );

                    final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
                      displayWidth: (geometry.width * dpr).round(),
                      displayHeight: (geometry.requestHeight * dpr).round(),
                      imageType: ImageType.art,
                    );

                    final image = CachedNetworkImage(
                      imageUrl: imageUrl,
                      cacheKey: artworkStorageKey(imageUrl),
                      cacheManager: PlexImageCacheManager.instance,
                      // A full-bleed frame (`coversHero`) fills a box with a
                      // different ratio than the source, so it still needs
                      // `cover`. The island frame is already sized to the
                      // source's own ratio (see `homeHeroArtGeometry`), so
                      // `fitWidth` there is crop-free rather than a no-op —
                      // `cover` would still centre-crop a source that isn't
                      // exactly 16:9.
                      fit: geometry.coversHero ? BoxFit.cover : BoxFit.fitWidth,
                      alignment: Alignment.topCenter,
                      memCacheHeight: memHeight,
                      placeholder: (context, url) =>
                          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                      errorBuilder: (context, error, stackTrace) =>
                          ColoredBox(color: Theme.of(context).colorScheme.surfaceContainerHighest),
                    );

                    return SizedBox(
                      key: HomeHeroArtwork.frameKey,
                      width: geometry.width,
                      height: geometry.height,
                      // Backstop for `fitWidth`: if the source isn't exactly
                      // 16:9, `fitWidth` can letterbox inside this frame. That
                      // gap must read as the scaffold background continuing,
                      // never as a hard image edge or a black sliver.
                      child: ColoredBox(
                        color: Theme.of(context).scaffoldBackgroundColor,
                        child: blurArtwork(
                          art.shouldBlur
                              ? ImageFiltered(imageFilter: ui.ImageFilter.blur(sigmaX: 28, sigmaY: 28), child: image)
                              : image,
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
          ),
          if (geometry.fadeHeight > 0)
            Positioned(
              left: 0,
              right: 0,
              // The frame sits top-anchored inside a Stack that spans the
              // *whole* hero (StackFit.expand upstream), which is taller
              // than the frame itself here (that's what fadeHeight > 0
              // means). `bottom: 0` would anchor to the hero's bottom edge
              // instead of the frame's, leaving the fade nowhere near the
              // artwork it's meant to blend.
              top: geometry.height - geometry.fadeHeight,
              height: geometry.fadeHeight,
              child: IgnorePointer(
                child: Builder(
                  key: HomeHeroArtwork.fadeKey,
                  builder: (context) {
                    final bgColor = Theme.of(context).scaffoldBackgroundColor;
                    return DecoratedBox(
                      decoration: BoxDecoration(
                        gradient: LinearGradient(
                          begin: Alignment.topCenter,
                          end: Alignment.bottomCenter,
                          colors: [Colors.transparent, bgColor.withValues(alpha: 0.6), bgColor],
                          stops: const [0.0, 0.6, 1.0],
                        ),
                      ),
                    );
                  },
                ),
              ),
            ),
        ],
      ),
    );
  }
}
