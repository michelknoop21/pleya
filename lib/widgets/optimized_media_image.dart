import 'dart:convert';
import 'dart:io';
import 'dart:ui';
import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:crypto/crypto.dart';
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:pleya/widgets/app_icon.dart';
import '../media/media_server_client.dart';
import 'package:provider/provider.dart';
import '../providers/local_library_provider.dart';
import '../services/device_performance.dart';
import '../services/download_artwork_helpers.dart';
import '../services/image_cache_service.dart';
import '../utils/app_logger.dart';
import '../utils/blurhash.dart';
import '../utils/media_image_helper.dart';
import '../utils/obfuscation_utils.dart';
import '../utils/platform_detector.dart';

/// Tracks recent image load failures to log a periodic summary instead of
/// spamming per-image. Resets after [_logInterval] so recurring issues
/// remain visible.
int _imageFailureCount = 0;
DateTime _lastFailureLog = DateTime.now();
const _logInterval = Duration(seconds: 10);

/// Image revisions the server answered 404 for. CachedNetworkImage keeps no
/// failures, so a missing asset was fetched again on every rebuild and every
/// detail open. A new content key or an app restart asks again. Keep the URL
/// too, so custom cache keys cannot suppress another authenticated source.
// ponytail: unbounded growth capped by clearing at 256 entries; an LRU only if
// a session ever collects that many distinct missing images.
final Set<(String, String)> _missingImageUrls = {};

/// Remembers [url] when [error] is a 404 and logs which asset it was, once.
/// Returns whether the URL is now known missing.
@visibleForTesting
bool rememberMissingImage(String url, Object error, {String? cacheKey}) {
  if (error is! HttpExceptionWithStatus || error.statusCode != 404) return false;
  if (_missingImageUrls.length >= 256) _missingImageUrls.clear();
  if (_missingImageUrls.add((url, cacheKey ?? OptimizedMediaImage.artworkCacheKey(url)))) {
    final uri = Uri.tryParse(url);
    // Plex /photo/:/transcode carries the real asset in `url=`; drop its
    // query and authority (which can contain credentials); log only a path.
    final nested = Uri.tryParse(uri?.queryParameters['url'] ?? '');
    final source = nested?.path.isNotEmpty == true ? nested!.path : uri?.path ?? '';
    appLogger.w('Image missing on the server (404); not requesting it again this session', error: {'source': source});
  }
  return true;
}

@visibleForTesting
bool isKnownMissingImage(String url, {String? cacheKey}) =>
    _missingImageUrls.contains((url, cacheKey ?? OptimizedMediaImage.artworkCacheKey(url)));

Widget blurArtwork(Widget child, {double sigma = 30, bool clip = true}) {
  if (!kBlurArtwork) return child;
  final filtered = ImageFiltered(
    imageFilter: ImageFilter.blur(sigmaX: sigma, sigmaY: sigma),
    child: child,
  );
  return clip ? ClipRect(child: filtered) : filtered;
}

class OptimizedMediaImage extends StatelessWidget {
  final MediaServerClient? client;
  final String? imagePath;
  final double? width;
  final double? height;
  final BoxFit fit;
  final FilterQuality filterQuality;
  final Widget Function(BuildContext, String)? placeholder;
  final Widget Function(BuildContext, String, dynamic)? errorWidget;
  final Duration fadeInDuration;
  final bool enableTranscoding;
  final String? cacheKey;

  /// [AlignmentGeometry], not [Alignment]: artwork that hugs the edge its
  /// text column starts on has to follow the ambient directionality
  /// (hoofdstuk 25, "RTL"). Every sink below is an [Image], which takes the
  /// geometry and resolves it itself.
  final AlignmentGeometry alignment;
  final IconData? fallbackIcon;
  final ImageType imageType;
  final String? localFilePath;

  /// Backend-provided BlurHash (Jellyfin only) rendered as the loading
  /// placeholder instead of a flat surface tile. Ignored when null.
  final String? blurHash;

  /// The box the *server* is asked for, when it must differ from the box the
  /// image is drawn in. Null means the two are the same, which is right for
  /// every tile and poster.
  ///
  /// It exists for cover-fitted artwork whose source ratio is not the box
  /// ratio. Plex's `/photo/:/transcode` fills the requested box with
  /// `minSize=1` and crops the overshoot from the centre before this widget
  /// sees a pixel, so a request in the box's ratio hands the crop to the server
  /// and makes [alignment] dead; Jellyfin fits inside the same numbers and
  /// crops nothing, so the same request lands as two different pictures on two
  /// backends. Asking for the source's own ratio, at least as large as the box,
  /// makes the server-side crop a no-op everywhere and leaves exactly one
  /// owner of the crop: [fit] and [alignment] here. HERO1 in
  /// `docs/tvos-fysieke-correctieronde.md` is the defect this closes.
  final Size? requestSize;

  const OptimizedMediaImage._({
    super.key,
    this.client,
    required this.imagePath,
    this.width,
    this.height,
    this.fit = BoxFit.cover,
    this.filterQuality = FilterQuality.medium,
    this.placeholder,
    this.errorWidget,
    this.fadeInDuration = const Duration(milliseconds: 300),
    this.enableTranscoding = true,
    this.cacheKey,
    this.alignment = Alignment.center,
    this.fallbackIcon,
    this.imageType = ImageType.poster,
    this.localFilePath,
    this.blurHash,
    this.requestSize,
  });

  /// Generic constructor for optimized images.
  const factory OptimizedMediaImage({
    Key? key,
    MediaServerClient? client,
    required String? imagePath,
    double? width,
    double? height,
    BoxFit fit,
    FilterQuality filterQuality,
    Widget Function(BuildContext, String)? placeholder,
    Widget Function(BuildContext, String, dynamic)? errorWidget,
    Duration fadeInDuration,
    bool enableTranscoding,
    String? cacheKey,
    AlignmentGeometry alignment,
    IconData? fallbackIcon,
    ImageType imageType,
    String? localFilePath,
    String? blurHash,
    Size? requestSize,
  }) = OptimizedMediaImage._;

  /// Named constructor for poster images with default fallback icon.
  const OptimizedMediaImage.poster({
    Key? key,
    MediaServerClient? client,
    required String? imagePath,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    FilterQuality filterQuality = FilterQuality.medium,
    Widget Function(BuildContext, String)? placeholder,
    Widget Function(BuildContext, String, dynamic)? errorWidget,
    Duration fadeInDuration = const Duration(milliseconds: 300),
    bool enableTranscoding = true,
    String? cacheKey,
    AlignmentGeometry alignment = Alignment.center,
    IconData? fallbackIcon,
    String? localFilePath,
    String? blurHash,
  }) : this._(
         key: key,
         client: client,
         imagePath: imagePath,
         width: width,
         height: height,
         fit: fit,
         filterQuality: filterQuality,
         placeholder: placeholder,
         errorWidget: errorWidget,
         fadeInDuration: fadeInDuration,
         enableTranscoding: enableTranscoding,
         cacheKey: cacheKey,
         alignment: alignment,
         fallbackIcon: fallbackIcon ?? Symbols.movie_rounded,
         imageType: ImageType.poster,
         localFilePath: localFilePath,
         blurHash: blurHash,
       );

  /// Named constructor for episode thumbnails.
  const OptimizedMediaImage.thumb({
    Key? key,
    MediaServerClient? client,
    required String? imagePath,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    FilterQuality filterQuality = FilterQuality.medium,
    Widget Function(BuildContext, String)? placeholder,
    Widget Function(BuildContext, String, dynamic)? errorWidget,
    Duration fadeInDuration = const Duration(milliseconds: 300),
    bool enableTranscoding = true,
    String? cacheKey,
    AlignmentGeometry alignment = Alignment.center,
    IconData? fallbackIcon,
    String? localFilePath,
    String? blurHash,
  }) : this._(
         key: key,
         client: client,
         imagePath: imagePath,
         width: width,
         height: height,
         fit: fit,
         filterQuality: filterQuality,
         placeholder: placeholder,
         errorWidget: errorWidget,
         fadeInDuration: fadeInDuration,
         enableTranscoding: enableTranscoding,
         cacheKey: cacheKey,
         alignment: alignment,
         fallbackIcon: fallbackIcon ?? Symbols.video_library_rounded,
         imageType: ImageType.thumb,
         localFilePath: localFilePath,
         blurHash: blurHash,
       );

  /// Named constructor for playlist images.
  const OptimizedMediaImage.playlist({
    Key? key,
    MediaServerClient? client,
    required String? imagePath,
    double? width,
    double? height,
    BoxFit fit = BoxFit.cover,
    FilterQuality filterQuality = FilterQuality.medium,
    Widget Function(BuildContext, String)? placeholder,
    Widget Function(BuildContext, String, dynamic)? errorWidget,
    Duration fadeInDuration = const Duration(milliseconds: 300),
    bool enableTranscoding = true,
    String? cacheKey,
    AlignmentGeometry alignment = Alignment.center,
    String? localFilePath,
  }) : this._(
         key: key,
         client: client,
         imagePath: imagePath,
         width: width,
         height: height,
         fit: fit,
         filterQuality: filterQuality,
         placeholder: placeholder,
         errorWidget: errorWidget,
         fadeInDuration: fadeInDuration,
         enableTranscoding: enableTranscoding,
         cacheKey: cacheKey,
         alignment: alignment,
         fallbackIcon: Symbols.playlist_play_rounded,
         imageType: ImageType.poster,
         localFilePath: localFilePath,
       );

  /// Stands in for the decoded image in golden tests.
  ///
  /// Every path below ends in a network or file image, so a widget test can
  /// only ever render the placeholder — which is why the first Films/Series
  /// goldens were a grid of identical grey tiles. Those pictures could prove
  /// the rhythm and the type, and could not prove the one thing the phase's
  /// art direction is actually about: that Pleya's dark chrome presents bright,
  /// warm and colourful artwork without flattening it.
  ///
  /// The seam is here rather than on the card because it is the *image* that
  /// cannot be rendered offline, and because putting it on the card would leave
  /// every other artwork surface untestable for the same reason.
  ///
  /// Null in production, and nothing in `lib/` ever assigns it.
  @visibleForTesting
  static Widget Function(BuildContext context, String? imagePath)? debugImageBuilder;

  /// Reports the artwork URL this widget resolved, straight after
  /// [MediaImageHelper.getOptimizedImageUrl] and before any provider or
  /// network work.
  ///
  /// A separate seam from [debugImageBuilder], and it has to be: that one
  /// returns from the *first line* of [build], so a test that installs it never
  /// reaches the sizing pipeline at all. Every discovery widget test goes
  /// through `test/test_helpers/tv_discovery_artwork.dart`, which installs
  /// exactly that — which is why "does a focus transition churn through a
  /// bucket of URLs" (P4) was not assertable at the widget level before.
  ///
  /// Assert the number of **distinct** URLs, never the number of calls: a
  /// widget that rebuilds five times and resolves the same stable URL five
  /// times is correct, and counting calls would make the guard fail on
  /// unrelated rebuild changes.
  ///
  /// Null in production; nothing in `lib/` ever assigns it. A test that sets it
  /// clears it in `tearDown` — this is process-global state.
  @visibleForTesting
  static void Function(String url)? debugResolvedUrlObserver;

  @visibleForTesting
  static void debugResetMissingImages() => _missingImageUrls.clear();

  /// The disk cache key for [imageUrl].
  ///
  /// Public because anything that *warms* the cache has to produce a key that
  /// is byte-identical to the one the widget reads with, or the warmed entry is
  /// a second copy nothing ever finds — see `UnifiedArtworkPrefetcher`. One
  /// definition, used by both.
  static String artworkCacheKey(String imageUrl) =>
      'plex_optimized_${sha1.convert(utf8.encode(artworkStorageKey(imageUrl)))}';

  /// Whether both width and height are explicitly set to finite positive values,
  /// meaning we can skip the LayoutBuilder.
  bool get _hasKnownDimensions =>
      width != null && width!.isFinite && width! > 0 && height != null && height!.isFinite && height! > 0;

  @override
  Widget build(BuildContext context) {
    final debugBuilder = debugImageBuilder;
    if (debugBuilder != null) return debugBuilder(context, imagePath);

    final storedPath = context.select<LocalLibraryProvider?, String?>(
      (p) => p?.posterPath(client?.serverId, imagePath),
    );
    final effectiveLocalPath = localFilePath ?? storedPath;
    final localFile = effectiveLocalPath != null ? File(effectiveLocalPath) : null;
    final hasLocal = localFile != null && localFile.existsSync();

    // No local file and no network path → fallback
    if (!hasLocal && (imagePath == null || imagePath!.isEmpty)) {
      return _buildFallback(context);
    }

    // Fast path: skip LayoutBuilder when both dimensions are explicitly known
    if (_hasKnownDimensions) {
      return blurArtwork(
        hasLocal
            ? _buildRegisteredLocalFileImage(
                context,
                localFile,
                width!,
                height!,
                permanent: storedPath != null && localFilePath == null,
              )
            : _buildCachedImage(context, width!, height!),
      );
    }

    return blurArtwork(
      LayoutBuilder(
        builder: (context, constraints) {
          final effectiveWidth = _resolvedDimension(width, constraints.maxWidth, 300.0);
          final effectiveHeight = _resolvedDimension(height, constraints.maxHeight, 450.0);
          return hasLocal
              ? _buildRegisteredLocalFileImage(
                  context,
                  localFile,
                  effectiveWidth,
                  effectiveHeight,
                  permanent: storedPath != null && localFilePath == null,
                )
              : _buildCachedImage(context, effectiveWidth, effectiveHeight);
        },
      ),
    );
  }

  Widget _buildRegisteredLocalFileImage(
    BuildContext context,
    File file,
    double width,
    double height, {
    required bool permanent,
  }) {
    final child = _buildLocalFileImage(context, file, width, height);
    if (!permanent || client == null || imagePath == null) return child;
    final url = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: imagePath,
      maxWidth: requestSize?.width ?? width,
      maxHeight: requestSize?.height ?? height,
      devicePixelRatio: MediaImageHelper.effectiveDevicePixelRatio(context),
      enableTranscoding: enableTranscoding,
      imageType: imageType,
    );
    return _VisibleArtworkRegistration(
      owner: context.read<LocalLibraryProvider?>(),
      epoch: context.select<LocalLibraryProvider?, int>((owner) => owner?.artworkRegistrationEpoch ?? 0),
      request: VisibleArtworkRequest(
        client: client!,
        path: imagePath!,
        url: url,
        baseKey: cacheKey ?? _generateCacheKey(url),
        permanent: true,
      ),
      child: child,
    );
  }

  Widget _buildLocalFileImage(BuildContext context, File file, double effectiveWidth, double effectiveHeight) {
    final dpr = MediaImageHelper.effectiveDevicePixelRatio(context);
    final scaledWidth = effectiveWidth * dpr;
    final scaledHeight = effectiveHeight * dpr;
    final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
      displayWidth: scaledWidth.isFinite && scaledWidth > 0 ? scaledWidth.round() : 0,
      displayHeight: scaledHeight.isFinite && scaledHeight > 0 ? scaledHeight.round() : 0,
      imageType: imageType,
    );

    return Image.file(
      file,
      width: width,
      height: height,
      // Only cacheHeight: leaving cacheWidth null preserves decode aspect
      // ratio, mirroring the network branch's ResizeImage wrapper.
      cacheHeight: memHeight > 0 ? memHeight : null,
      fit: fit,
      filterQuality: filterQuality,
      alignment: alignment,
      errorBuilder: (context, error, stackTrace) {
        if (errorWidget != null) {
          return errorWidget!(context, file.path, error);
        }
        return _buildErrorWidget(context, error);
      },
    );
  }

  static double _resolvedDimension(double? explicit, double constraintMax, double fallback) {
    // Pick the explicit size when it's a finite positive number, otherwise
    // fall back to the constraint or a sensible default so we don't end up
    // with NaN/Infinity when rounding to ints for caching.
    if (explicit == null || explicit.isNaN || explicit.isInfinite || explicit <= 0) {
      if (constraintMax.isFinite && constraintMax > 0) {
        return constraintMax;
      }
      return fallback;
    }
    return explicit;
  }

  Widget _buildCachedImage(BuildContext context, double effectiveWidth, double effectiveHeight) {
    final devicePixelRatio = MediaImageHelper.effectiveDevicePixelRatio(context);
    // The request box and the decode box follow [requestSize] when it is set;
    // the drawn box below stays `width`/`height`. See the field for why.
    final requestWidth = requestSize?.width ?? effectiveWidth;
    final requestHeight = requestSize?.height ?? effectiveHeight;

    final imageUrl = MediaImageHelper.getOptimizedImageUrl(
      client: client,
      thumbPath: imagePath,
      maxWidth: requestWidth,
      maxHeight: requestHeight,
      devicePixelRatio: devicePixelRatio,
      enableTranscoding: enableTranscoding,
      imageType: imageType,
    );

    if (imageUrl.isEmpty) {
      return _buildFallback(context);
    }
    final scaledWidth = requestWidth * devicePixelRatio;
    final scaledHeight = requestHeight * devicePixelRatio;
    final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
      displayWidth: scaledWidth.isFinite && scaledWidth > 0 ? scaledWidth.round() : 0,
      displayHeight: scaledHeight.isFinite && scaledHeight > 0 ? scaledHeight.round() : 0,
      imageType: imageType,
    );

    final baseCacheKey = cacheKey ?? _generateCacheKey(imageUrl);
    final effectiveCacheKey = context.select<LocalLibraryProvider?, String>(
      (owner) => client == null
          ? baseCacheKey
          : owner?.artworkCacheKey(client!.serverId, imageUrl, baseCacheKey) ?? baseCacheKey,
    );

    final Widget image;
    if (isKnownMissingImage(imageUrl, cacheKey: effectiveCacheKey)) {
      image = errorWidget?.call(context, imageUrl, 'HTTP 404') ?? _buildErrorWidget(context, null);
    } else {
      debugResolvedUrlObserver?.call(imageUrl);
      final provider = CachedNetworkImageProvider(
        imageUrl,
        cacheKey: effectiveCacheKey,
        cacheManager: context.read<LocalLibraryProvider?>()?.artworkCache ?? PlexImageCacheManager.instance,
        headers: const {'User-Agent': 'Pleya'},
      );

      image = Image(
        image: ResizeImage.resizeIfNeeded(null, memHeight > 0 ? memHeight : null, provider),
        width: width,
        height: height,
        fit: fit,
        filterQuality: filterQuality,
        alignment: alignment,
        errorBuilder: (context, error, stackTrace) {
          rememberMissingImage(imageUrl, error, cacheKey: effectiveCacheKey);
          _imageFailureCount++;
          final now = DateTime.now();
          if (now.difference(_lastFailureLog) >= _logInterval) {
            appLogger.w('Image load failed ($_imageFailureCount since last log): $error');
            _imageFailureCount = 0;
            _lastFailureLog = now;
          }
          if (errorWidget != null) {
            return errorWidget!(context, imageUrl, error);
          }
          return _buildErrorWidget(context, error);
        },
        frameBuilder: (context, child, frame, wasSynchronouslyLoaded) {
          if (wasSynchronouslyLoaded) return child;
          // Reduced tier: swap in directly — each in-flight fade is a tile-sized
          // saveLayer, and grid scrolling runs many of them concurrently.
          // TV: the AnimatedSwitcher is a paint-time swap that defers compositing
          // under the rail's reveal transform, leaving lazy rows blank until an
          // L/R nudge. A plain child-swap dirties the RenderImage and composites
          // correctly under the transform.
          if (DevicePerformance.isReduced || PlatformDetector.isTV()) {
            return frame != null ? child : _buildPlaceholder(context, imageUrl);
          }
          return AnimatedSwitcher(
            duration: const Duration(milliseconds: 300),
            child: frame != null ? child : _buildPlaceholder(context, imageUrl),
          );
        },
      );
    }
    return _VisibleArtworkRegistration(
      epoch: context.select<LocalLibraryProvider?, int>((owner) => owner?.artworkRegistrationEpoch ?? 0),
      owner: context.read<LocalLibraryProvider?>(),
      request: client == null
          ? null
          : VisibleArtworkRequest(client: client!, path: imagePath!, url: imageUrl, baseKey: baseCacheKey),
      child: image,
    );
  }

  Widget _surfacePlaceholder(BuildContext context, {IconData? icon, Color? iconColor, bool fillParent = false}) {
    final theme = Theme.of(context).colorScheme;
    return Container(
      width: fillParent ? null : width,
      height: fillParent ? null : height,
      color: theme.surfaceContainerHighest,
      child: icon == null
          ? null
          : Center(child: AppIcon(icon, fill: 1, size: 40, color: iconColor ?? theme.onSurfaceVariant)),
    );
  }

  Widget _buildPlaceholder(BuildContext context, String imageUrl) {
    // BlurHash (Jellyfin) wins over a caller-supplied shimmer/surface
    // placeholder — it's a truer preview of the poster while it loads.
    if (blurHash != null && blurHash!.isNotEmpty) {
      return Stack(
        fit: StackFit.expand,
        children: [_surfacePlaceholder(context, fillParent: true), BlurHashPlaceholder(blurHash!)],
      );
    }
    if (placeholder != null) return placeholder!(context, imageUrl);
    // No iconColor: the default (onSurfaceVariant) tracks the theme. A fixed
    // white54 vanishes on the light theme's pale placeholder fill, which the
    // error and fallback paths below already avoid.
    return _surfacePlaceholder(context, icon: fallbackIcon);
  }

  Widget _buildErrorWidget(BuildContext context, dynamic _) => _surfacePlaceholder(
    context,
    icon: fallbackIcon ?? Symbols.broken_image_rounded,
    fillParent: !_hasKnownDimensions,
  );

  Widget _buildFallback(BuildContext context) =>
      _surfacePlaceholder(context, icon: fallbackIcon ?? Symbols.image_not_supported_rounded);

  // URL already encodes bucketed transcode dimensions via roundDimensions, so
  // the URL hash alone uniquely identifies the bytes on disk. Including
  // mem-cache dimensions would re-introduce churn on every pixel of window
  // resize and defeat getMemCacheDimensions' bucketing. Hashing the token-free
  // URL keeps auth-token rotation from invalidating the whole disk cache on
  // every re-auth. See [artworkCacheKey].
  String _generateCacheKey(String imageUrl) => artworkCacheKey(imageUrl);
}

/// No layout or paint change. The lease lives exactly as long as this mounted
/// network image, and equal rebuilds keep one registration.
class _VisibleArtworkRegistration extends StatefulWidget {
  const _VisibleArtworkRegistration({
    required this.owner,
    required this.request,
    required this.child,
    required this.epoch,
  });
  final LocalLibraryProvider? owner;
  final int epoch;
  final VisibleArtworkRequest? request;
  final Widget child;
  @override
  State<_VisibleArtworkRegistration> createState() => _VisibleArtworkRegistrationState();
}

class _VisibleArtworkRegistrationState extends State<_VisibleArtworkRegistration> {
  final Object _lease = Object();
  void _register() {
    final request = widget.request;
    if (request != null) widget.owner?.registerVisibleArtwork(_lease, request);
  }

  @override
  void initState() {
    super.initState();
    _register();
  }

  @override
  void didUpdateWidget(covariant _VisibleArtworkRegistration oldWidget) {
    super.didUpdateWidget(oldWidget);
    final a = oldWidget.request;
    final b = widget.request;
    if (identical(oldWidget.owner, widget.owner) &&
        identical(a?.client, b?.client) &&
        a?.url == b?.url &&
        a?.baseKey == b?.baseKey &&
        a?.path == b?.path &&
        a?.permanent == b?.permanent &&
        oldWidget.epoch == widget.epoch &&
        (widget.owner?.hasVisibleArtworkLease(_lease) ?? true))
      return;
    oldWidget.owner?.unregisterVisibleArtwork(_lease);
    _register();
  }

  @override
  void dispose() {
    widget.owner?.unregisterVisibleArtwork(_lease);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
