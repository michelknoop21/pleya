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
  /// sharp subject needs to stay the clear focal point, not the background
  /// behind it.
  ///
  /// It ramps rather than sitting flat: at full strength from the very top the
  /// band above the sharp layer crushes to near-black and reads as a solid bar
  /// under the Dynamic Island instead of artwork continuing behind it.
  /// [_ambientWashAlpha] is where the ramp lands and what the rest of the hero
  /// keeps, so nothing below the ramp changes. The top stays dark enough for
  /// white status-bar glyphs; measured on-device before settling on 0.30.
  static const double _ambientWashAlphaTop = 0.30;
  static const double _ambientWashAlphaMid = 0.42;
  static const double _ambientWashAlpha = 0.55;

  /// The same ramp on the reduced visual-effects tier, where the blur is off
  /// (see [_buildAmbientLayer]). Without the blur the ambient layer is a
  /// recognisable second copy of the artwork, so it needs more darkness on top
  /// of the flattening colour filter to read as atmosphere.
  static const double _reducedAmbientWashAlphaTop = 0.45;
  static const double _reducedAmbientWashAlphaMid = 0.56;
  static const double _reducedAmbientWashAlpha = 0.68;

  /// Where the ramp sits, as a fraction of the hero canvas (not of the
  /// overscanned ambient box — see [_ambientWashGradient], which maps these
  /// into the larger box so they land where these numbers say).
  static const double _ambientWashMidStop = 0.18;
  static const double _ambientWashEndStop = 0.32;

  /// Flattens the ambient layer on the reduced visual-effects tier.
  ///
  /// `blurArtwork` is a no-op unless the `BLUR_ARTWORK` dart-define is set, so
  /// the only blur this layer ever had is the [ImageFiltered] that the reduced
  /// tier switches off. Without something in its place the layer draws a
  /// sharp, heavily upscaled `BoxFit.cover` crop of the very same artwork
  /// directly behind the sharp layer: a visible duplicate rather than
  /// atmosphere. Desaturating and flattening it costs one colour matrix, which
  /// the tier can afford where a gaussian blur is what it cannot.
  ///
  /// [saturation] 0 is greyscale, 1 leaves colour untouched. [contrast] scales
  /// around [_reducedContrastPivot] rather than mid-grey, so flattening also
  /// darkens instead of washing toward grey.
  @visibleForTesting
  static List<double> reducedAmbientColorMatrix({double saturation = 0.25, double contrast = 0.55}) {
    // Rec. 709 luma, the same weights the rest of the app measures with.
    const lr = 0.2126, lg = 0.7152, lb = 0.0722;
    double keep(double luma) => contrast * (luma + ((1 - luma) * saturation));
    double drop(double luma) => contrast * (luma - (luma * saturation));
    final offset = 255.0 * (1 - contrast) * _reducedContrastPivot;
    return [
      keep(lr), drop(lg), drop(lb), 0, offset, //
      drop(lr), keep(lg), drop(lb), 0, offset, //
      drop(lr), drop(lg), keep(lb), 0, offset, //
      0, 0, 0, 1, 0, //
    ];
  }

  /// Below mid-grey on purpose: contrast pivoting at 0.5 would lift the dark
  /// half of the artwork toward grey, which is brighter than the hero wants.
  static const double _reducedContrastPivot = 0.25;

  /// The wash ramp, expressed over the overscanned ambient box.
  ///
  /// The ambient layer is inset by [-_ambientOverscan] on every side so its own
  /// blur never shows a soft edge inside the hero, which makes its box taller
  /// than the canvas. Mapping the stops through that difference keeps
  /// [_ambientWashMidStop] and [_ambientWashEndStop] meaning what they say
  /// relative to the hero the viewer actually sees.
  @visibleForTesting
  static LinearGradient ambientWashGradient({
    required Color background,
    required double canvasHeight,
    bool reduced = false,
  }) {
    final boxHeight = canvasHeight + (2 * _ambientOverscan);
    final offset = boxHeight <= 0 ? 0.0 : _ambientOverscan / boxHeight;
    final scale = boxHeight <= 0 ? 1.0 : canvasHeight / boxHeight;
    double mapped(double canvasStop) => (offset + (canvasStop * scale)).clamp(0.0, 1.0);

    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: [
        background.withValues(alpha: reduced ? _reducedAmbientWashAlphaTop : _ambientWashAlphaTop),
        background.withValues(alpha: reduced ? _reducedAmbientWashAlphaMid : _ambientWashAlphaMid),
        background.withValues(alpha: reduced ? _reducedAmbientWashAlpha : _ambientWashAlpha),
      ],
      stops: [mapped(0), mapped(_ambientWashMidStop), mapped(_ambientWashEndStop)],
    );
  }

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
  /// [topBlendHeight] adds a matching fade-in at the top edge, for a full-width
  /// layer whose first row would otherwise butt straight against the ambient
  /// layer and draw a hard seam. Zero (the default, and every island) returns
  /// exactly the three-stop ramp this mask has always had.
  @visibleForTesting
  static LinearGradient verticalFadeMask({
    required double sharpHeight,
    required double fadeHeight,
    double topBlendHeight = 0,
  }) {
    final fadeStart = sharpHeight <= 0 ? 0.0 : (1 - (fadeHeight / sharpHeight)).clamp(0.0, 1.0);
    if (topBlendHeight <= 0 || sharpHeight <= 0) {
      return LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: const [Colors.white, Colors.white, Colors.transparent],
        stops: [0.0, fadeStart, 1.0],
      );
    }
    // Clamped against `fadeStart` so the stops never stop ascending on a layer
    // too short to hold both bands.
    final topStop = (topBlendHeight / sharpHeight).clamp(0.0, fadeStart);
    return LinearGradient(
      begin: Alignment.topCenter,
      end: Alignment.bottomCenter,
      colors: const [Colors.transparent, Colors.white, Colors.white, Colors.transparent],
      stops: [0.0, topStop, fadeStart, 1.0],
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
    // Not `hasSharpForeground`: a geometry can legitimately have no sharp
    // layer and still want its ambient wash drawn (a top inset that swallows
    // the island — see `homeHeroArtGeometry`). Only a collapsed canvas, or
    // having neither layer, means there is nothing to draw at all.
    if (geometry.canvasWidth <= 0 || geometry.canvasHeight <= 0) return const SizedBox.shrink();
    if (!geometry.hasSharpForeground && !geometry.useAmbientLayer) return const SizedBox.shrink();

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
              if (geometry.hasSharpForeground)
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
            if (DevicePerformance.isReduced)
              ColorFiltered(colorFilter: ColorFilter.matrix(reducedAmbientColorMatrix()), child: image)
            else
              ImageFiltered(
                imageFilter: ui.ImageFilter.blur(sigmaX: _ambientBlurSigma, sigmaY: _ambientBlurSigma),
                child: image,
              ),
            DecoratedBox(
              decoration: BoxDecoration(
                gradient: ambientWashGradient(
                  background: Theme.of(context).scaffoldBackgroundColor,
                  canvasHeight: geometry.canvasHeight,
                  reduced: DevicePerformance.isReduced,
                ),
              ),
            ),
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
          topBlendHeight: geometry.sharpTopBlendHeight,
        ).createShader(rect),
        child: frame,
      );
      // Only an island has side edges to hide. A full-width layer's edges are
      // the canvas edges, so blending them would just fade the hero out into
      // its own margins.
      if (art.kind == BillboardArtKind.square && geometry.presentation == HomeHeroSharpPresentation.island) {
        frame = ShaderMask(
          key: HomeHeroArtwork.sideFadeKey,
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => horizontalFadeMask.createShader(rect),
          child: frame,
        );
      }
    }

    // The inset sits *outside* both ShaderMasks on purpose. Inside, the mask
    // rect would span `sharpHeight + sharpTopInset` and the blend would start
    // proportionally higher up the image than the 55% it is calibrated at.
    return Align(
      alignment: Alignment.topCenter,
      child: Padding(
        padding: EdgeInsets.only(top: geometry.sharpTopInset),
        child: frame,
      ),
    );
  }
}
