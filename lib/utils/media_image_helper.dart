import 'dart:math';
import 'package:flutter/widgets.dart';
import '../media/media_server_client.dart';
import '../services/device_performance.dart';
import 'platform_detector.dart';

/// Image types for different transcoding strategies
enum ImageType {
  poster, // 2:3 ratio posters
  art, // Wide background art
  /// The Home hero / billboard. [art] with one difference that matters: its
  /// cap is the TV output surface rather than a retina desktop window, because
  /// the hero is the one surface that fills a 4K panel edge to edge. Measured
  /// on Apple TV the hero renders 3538x1365 physical pixels while [art]'s
  /// 2560 cap made every backdrop arrive 1.38x too small, and a 1920-wide
  /// source 1.84x too small. Separate value rather than a bigger global cap so
  /// posters, cards and thumbs keep asking for exactly what they draw.
  heroArt,
  thumb, // 16:9 episode thumbnails
  logo, // Variable ratio clear logos
  avatar, // Square-ish user avatars
}

/// Backend-neutral image URL helper.
///
/// Builds optimally-sized image URLs that go through the right server-side
/// transcode path:
/// - **Plex**: `/photo/:/transcode?width=W&height=H&url=...&X-Plex-Token=...`
///   constructed by [MediaServerClient.thumbnailUrl] (PlexClient impl).
/// - **Jellyfin**: `/Items/{id}/Images/{type}?MaxWidth=W&MaxHeight=H&api_key=...`
///   constructed by [MediaServerClient.thumbnailUrl] (JellyfinClient impl).
///
/// Self-contained absolute URLs (Jellyfin items pre-absolutized at the
/// model layer) get sized via query-param append so they pick up the same
/// DPR scaling and cache-bucket rounding as Plex.
///
/// External URLs (EPG provider images, etc.) that the local server doesn't
/// host get proxied through Plex's photo transcoder when a Plex client is
/// available; otherwise they pass through unchanged.
class MediaImageHelper {
  static const int _widthRoundingFactor = 40;
  static const int _heightRoundingFactor = 60;

  // Full-bleed backdrops (hero/spotlight) cover large retina desktop/TV
  // panels, so cap at 1440p rather than 1080p — a 1080p backdrop upscales
  // ~1.7× on a 2560px retina Mac and reads as grainy. Phones request far less
  // than this, and the reduced tier has its own 720p cap, so only big screens
  // pay the extra bytes.
  static const int _maxTranscodedWidth = 2560;
  static const int _maxTranscodedHeight = 1440;

  /// [ImageType.heroArt]'s ceiling: the Apple TV 4K output surface. The hero
  /// card is 3538x1365 physical there, so this is the smallest cap that lets
  /// it be requested at native resolution, and it is not shared with anything
  /// else.
  static const int _maxHeroArtWidth = 3840;
  static const int _maxHeroArtHeight = 2160;

  static const int _minTranscodedWidth = 160;
  static const int _minTranscodedHeight = 240;

  /// Minimum DPR for TV to ensure sharp artwork on large screens
  static const double _tvMinDpr = 2.0;

  /// Reduced tier caps: tiles at 1.5× DPR, backdrops at ~720p. Smaller
  /// transcodes mean fewer bytes fetched AND cheaper decodes on weak 32-bit
  /// hardware; the art cap is masked by the gradient scrims drawn over it.
  static const double _reducedMaxDpr = 1.5;
  static const int _reducedMaxArtWidth = 1280;
  static const int _reducedMaxArtHeight = 720;

  /// Rounds a value up to the next multiple of [factor]. Shared between the
  /// URL dimension rounding (transcode bucket) and the mem-cache dimension
  /// rounding (decode bucket) so both snap to the same grid.
  static int _bucketUp(num value, int factor) => (value / factor).ceil() * factor;

  /// Rounds dimensions to cache-friendly values to increase cache hit rate.
  ///
  /// The caps are applied by **scaling the box**, not by clamping each axis on
  /// its own. Independent clamps silently change the requested aspect ratio,
  /// and that is not a cosmetic difference: the Home hero asks for a 2.59 box,
  /// the old code clamped 3892x1501 to 2560x1440 and shipped a request for a
  /// 1.78 one. On Plex, whose `/photo/:/transcode` takes both dimensions with
  /// `minSize=1`, the server then cropped the source to 16:9 and Flutter
  /// cropped the result again to 2.59 -- the double crop
  /// [DEC-057](../../docs/DECISIONS.md#dec-057) exists to prevent, introduced
  /// by the rounding helper rather than by any caller.
  ///
  /// Bucketing still moves the ratio a little (width snaps to 40, height to
  /// 60), which is the tolerance the caller is expected to accept; what it no
  /// longer does is reshape the box.
  ///
  /// The floor stays a per-axis clamp on purpose. It only fires on boxes small
  /// enough that [getOptimizedImageUrl] skips the transcode round-trip
  /// entirely, and preserving the ratio there would inflate small requests to
  /// satisfy a 2:3-shaped minimum that has nothing to do with them.
  static (int width, int height) roundDimensions(double width, double height, {int? maxWidth, int? maxHeight}) {
    final maxW = maxWidth ?? _maxTranscodedWidth;
    final maxH = maxHeight ?? _maxTranscodedHeight;
    var w = width;
    var h = height;
    if (w > 0 && h > 0) {
      final fit = min(maxW / w, maxH / h);
      if (fit < 1) {
        w *= fit;
        h *= fit;
      }
    }
    return (
      _bucketUp(w, _widthRoundingFactor).clamp(_minTranscodedWidth, maxW),
      _bucketUp(h, _heightRoundingFactor).clamp(_minTranscodedHeight, maxH),
    );
  }

  /// Computes an effective device pixel ratio that accounts for displays where
  /// the platform-reported DPR doesn't reflect the true physical density
  /// (common on Linux X11 with compositor scaling).
  static double effectiveDevicePixelRatio(BuildContext context) {
    final reportedDpr = MediaQuery.devicePixelRatioOf(context);
    double dpr;
    try {
      final displayWidth = View.of(context).display.size.width;
      // Scale quality with display resolution: 1920px = baseline (1.0x)
      final displayBasedDpr = (displayWidth / 1920).clamp(1.0, 3.0);
      dpr = max(reportedDpr, displayBasedDpr);
    } catch (_) {
      dpr = reportedDpr;
    }
    if (DevicePerformance.isReduced) return min(dpr, _reducedMaxDpr);
    if (PlatformDetector.isTV()) dpr = max(dpr, _tvMinDpr);
    return dpr;
  }

  /// Calculates optimal image dimensions based on image type and constraints
  static (int width, int height) calculateOptimalDimensions({
    required double maxWidth,
    required double maxHeight,
    required double devicePixelRatio,
    ImageType imageType = ImageType.poster,
  }) {
    final targetWidth = maxWidth.isFinite ? maxWidth * devicePixelRatio : 300 * devicePixelRatio;
    final targetHeight = maxHeight.isFinite ? maxHeight * devicePixelRatio : 450 * devicePixelRatio;

    switch (imageType) {
      case ImageType.art:
      case ImageType.heroArt:
        final isHero = imageType == ImageType.heroArt;
        if (DevicePerformance.isReduced) {
          // No 1.1x cover overshoot, capped at ~720p. Ratio-preserving like
          // the main path: `roundDimensions` fits the box inside the cap
          // instead of squaring off each axis.
          return roundDimensions(
            targetWidth,
            targetHeight,
            maxWidth: _reducedMaxArtWidth,
            maxHeight: _reducedMaxArtHeight,
          );
        }
        return roundDimensions(
          targetWidth * 1.1,
          targetHeight * 1.1,
          maxWidth: isHero ? _maxHeroArtWidth : null,
          maxHeight: isHero ? _maxHeroArtHeight : null,
        );

      case ImageType.logo:
        final logoWidth = targetWidth;
        final logoHeight = targetHeight;
        return roundDimensions(logoWidth, logoHeight);

      case ImageType.thumb:
        final thumbHeight = targetHeight;
        final thumbWidth = min(targetWidth, thumbHeight * (16 / 9));
        return roundDimensions(thumbWidth, thumbHeight);

      case ImageType.avatar:
        final size = min(targetWidth, targetHeight);
        return roundDimensions(size, size);

      case ImageType.poster:
        final calculatedWidth = min(targetWidth, targetHeight * (2 / 3));
        final calculatedHeight = calculatedWidth * (3 / 2);
        return roundDimensions(calculatedWidth, calculatedHeight);
    }
  }

  /// Creates an optimized image URL.
  ///
  /// Falls back to the raw [thumbPath] when the path is empty, when no
  /// client is available (offline mode), or when transcoding is suppressed
  /// for this path.
  static String getOptimizedImageUrl({
    MediaServerClient? client,
    required String? thumbPath,
    required double maxWidth,
    required double maxHeight,
    required double devicePixelRatio,
    bool enableTranscoding = true,
    ImageType imageType = ImageType.poster,
  }) {
    if (thumbPath == null || thumbPath.isEmpty) return '';
    final basePath = thumbPath;

    if (basePath.startsWith('http://') || basePath.startsWith('https://')) {
      // Self-contained Jellyfin URLs already carry their own auth
      // (`api_key=...`). Append `maxWidth/maxHeight` so we still get DPR
      // scaling and cache-bucket rounding — Jellyfin's image endpoint
      // honours those query params.
      if (basePath.contains('api_key=')) {
        if (!enableTranscoding) return basePath;
        final (width, height) = calculateOptimalDimensions(
          maxWidth: maxWidth,
          maxHeight: maxHeight,
          devicePixelRatio: devicePixelRatio,
          imageType: imageType,
        );
        final uri = Uri.parse(basePath);
        final params = Map<String, String>.from(uri.queryParameters);
        final lowerKeys = params.keys.map((k) => k.toLowerCase()).toSet();
        if (!lowerKeys.contains('maxwidth') && !lowerKeys.contains('width')) {
          params['maxWidth'] = '$width';
        }
        if (!lowerKeys.contains('maxheight') && !lowerKeys.contains('height')) {
          params['maxHeight'] = '$height';
        }
        return uri.replace(queryParameters: params).toString();
      }

      // EPG / external URL — proxy through the server's transcoder. Plex
      // implements [externalImageUrl] via `/photo/:/transcode?url=...`;
      // backends without a comparable endpoint return the URL unchanged.
      if (client == null || !enableTranscoding) return basePath;
      final (width, height) = calculateOptimalDimensions(
        maxWidth: maxWidth,
        maxHeight: maxHeight,
        devicePixelRatio: devicePixelRatio,
        imageType: imageType,
      );
      return client.externalImageUrl(basePath, width: width, height: height);
    }

    // Relative path — let the client build the sized URL using its native
    // size-hint params (`/photo/:/transcode` for Plex, `MaxWidth/MaxHeight`
    // for Jellyfin). The interface guarantees both honour width/height.
    if (client == null) {
      // Offline + relative path: the cached entry already exists under the
      // URL originally fetched, so returning '' matches pre-refactor behaviour.
      return '';
    }

    if (!enableTranscoding || !shouldTranscode(basePath)) {
      return client.thumbnailUrl(basePath);
    }

    final (width, height) = calculateOptimalDimensions(
      maxWidth: maxWidth,
      maxHeight: maxHeight,
      devicePixelRatio: devicePixelRatio,
      imageType: imageType,
    );

    // For very small targets, skip server-side resizing — the cost of the
    // transcode round-trip outweighs the savings.
    if (maxWidth < 80 || maxHeight < 120) {
      return client.thumbnailUrl(basePath);
    }
    if (width <= _minTranscodedWidth * 1.2 && height <= _minTranscodedHeight * 1.2) {
      return client.thumbnailUrl(basePath);
    }

    return client.thumbnailUrl(basePath, width: width, height: height);
  }

  /// Generates cache-friendly dimensions for memory caching.
  ///
  /// Max bounds are type-aware so large originals (e.g. failed server
  /// transcodes or external EPG images) are capped at a resolution
  /// appropriate for the display context.
  static (int memWidth, int memHeight) getMemCacheDimensions({
    required int displayWidth,
    required int displayHeight,
    double scaleFactor = 1.0,
    ImageType imageType = ImageType.poster,
  }) {
    // Bucket to match roundDimensions() so the mem-cache key and CNIP
    // maxHeight stay stable across sub-bucket resize deltas. Without this,
    // LayoutBuilder rebuilds during window resize churn the cache key on
    // every pixel and evict valid entries from Flutter's image cache.
    final bucketedWidth = _bucketUp(displayWidth * scaleFactor, _widthRoundingFactor);
    final bucketedHeight = _bucketUp(displayHeight * scaleFactor, _heightRoundingFactor);

    final (int maxW, int maxH) = switch (imageType) {
      ImageType.poster => (720, 1080),
      ImageType.thumb => (960, 540),
      // Match the reduced-tier fetch cap so oversized originals (failed
      // transcodes, external images) can't decode past the art budget.
      ImageType.art ||
      ImageType.heroArt when DevicePerformance.isReduced => (_reducedMaxArtWidth, _reducedMaxArtHeight),
      ImageType.art => (_maxTranscodedWidth, _maxTranscodedHeight),
      // The hero decodes at the size it draws, or the decode budget would
      // undo the fetch: asking the server for 3840 and then decoding into
      // 2560 is the same softness by a different route.
      ImageType.heroArt => (_maxHeroArtWidth, _maxHeroArtHeight),
      ImageType.logo => (600, 300),
      ImageType.avatar => (300, 300),
    };

    return (bucketedWidth.clamp(120, maxW), bucketedHeight.clamp(180, maxH));
  }

  /// Determines if an image path is suitable for transcoding
  static bool shouldTranscode(String? imagePath) {
    if (imagePath == null || imagePath.isEmpty) return false;

    if (imagePath.contains('/photo/:/transcode') ||
        imagePath.startsWith('http://') ||
        imagePath.startsWith('https://')) {
      return false;
    }

    return true;
  }

  /// Public Plex image proxy, used for catalogue artwork that belongs to no
  /// server.
  static const String _plexPhotoProxy = 'https://images.plex.tv/photo';

  /// Sized URL for a Plex discover poster.
  ///
  /// Watchlist artwork cannot go through [getOptimizedImageUrl] with a client.
  /// A discover title has no server, and handing an absolute URL to a Plex
  /// client would proxy it via `/photo/:/transcode`, which appends the server
  /// token. That token would then sit inside a persistent image-cache key,
  /// where it outlives the session and travels with the cache.
  ///
  /// `images.plex.tv/photo` needs no authentication at all. Measured on 16
  /// August 2026 against every artwork host the watchlist actually returns
  /// (`metadata-static.plex.tv`, `image.tmdb.org`), it answers 200 with a
  /// correctly resized image and turns a 428 KB poster into 20 KB. Requests
  /// carry no header, so the URL is the whole cache key and holds nothing
  /// private.
  ///
  /// Returns an empty string for a missing reference, and passes a relative
  /// path through untouched: only absolute catalogue URLs are proxied.
  static String catalogPosterUrl(String? url, {required int width, required int height}) {
    if (url == null || url.isEmpty) return '';
    if (!url.startsWith('http://') && !url.startsWith('https://')) return url;
    if (url.startsWith(_plexPhotoProxy)) return url;

    return Uri.parse(
      _plexPhotoProxy,
    ).replace(queryParameters: {'width': '$width', 'height': '$height', 'url': url}).toString();
  }

  /// Optimized URL for hero/background art ([ImageType.art]).
  static String heroArtUrl({
    required MediaServerClient? client,
    required String? thumbPath,
    required BuildContext context,
    required double containerWidth,
    required double containerHeight,
  }) => _typedUrl(client, thumbPath, context, containerWidth, containerHeight, ImageType.art);

  /// Optimized URL for clear-logo overlays ([ImageType.logo]).
  static String logoUrl({
    required MediaServerClient? client,
    required String? thumbPath,
    required BuildContext context,
    required double containerWidth,
    required double containerHeight,
  }) => _typedUrl(client, thumbPath, context, containerWidth, containerHeight, ImageType.logo);

  static String _typedUrl(
    MediaServerClient? client,
    String? thumbPath,
    BuildContext context,
    double containerWidth,
    double containerHeight,
    ImageType type,
  ) {
    return getOptimizedImageUrl(
      client: client,
      thumbPath: thumbPath,
      maxWidth: containerWidth,
      maxHeight: containerHeight,
      devicePixelRatio: effectiveDevicePixelRatio(context),
      imageType: type,
    );
  }
}
