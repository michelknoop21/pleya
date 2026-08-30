/// Warms poster artwork just ahead of where the user is in the unified
/// Films/Series grid (hoofdstuk 10.2 of docs/tvos-unified-experience.md), so a
/// D-pad scroll on a TV does not walk into a wall of placeholders.
///
/// ## Why this is a service and not a few lines in the grid
///
/// Prefetching is a policy — how far ahead, how many at once, what to do when
/// a server is offline — and every one of those answers is testable without a
/// widget tree. The grid's job is to know *which cards are visible*; deciding
/// what that means for the network is this file's. [prefetchAround] is the
/// whole seam between them: a widget that knows its visible index range can
/// call it on every scroll or focus change without knowing anything else.
///
/// ## It reuses the artwork pipeline, it does not add one
///
/// Every URL comes from [MediaImageHelper.getOptimizedImageUrl] with the same
/// arguments `OptimizedMediaImage` passes for a poster, the provider is the
/// same [CachedNetworkImageProvider] on the same [PlexImageCacheManager], and
/// the same `ResizeImage` wrapper and cache key go around it. That is not
/// politeness: the point of warming an entry is that the widget later finds
/// *that* entry. [CachedNetworkImageProvider.obtainKey] ignores the
/// [ImageConfiguration] and its equality is `(cacheKey ?? url, scale,
/// maxHeight, maxWidth)`, so a request built here and the one the card builds
/// later collapse onto one disk file and one decode — provided the URL and the
/// cache key match exactly, which is why both are derived the same way rather
/// than approximated.
///
/// ## Bounded on purpose, in three independent ways
///
/// A catalogue is tens of thousands of titles and a poster is a real network
/// request on a device with a weak radio and 1 GB of RAM. So:
///
/// 1. the window is the visible range plus [lookaheadItems] on each side, and
///    never more than [maxWindowItems] entries in total, whatever range the
///    caller hands over;
/// 2. at most [maxConcurrent] requests are in flight, deliberately fewer than
///    the six permits `image_cache_service.dart` hands out globally, so a
///    prefetch burst can never occupy every artwork slot and starve the cards
///    that are actually on screen;
/// 3. a URL that has been dispatched once is not dispatched again, remembered
///    in a bounded LRU of [maxRememberedUrls] entries.
library;

import 'dart:collection';

import 'package:cached_network_image_ce/cached_network_image.dart';
import 'package:flutter/widgets.dart';

import '../../media/media_server_client.dart';
import '../../media/unified/unified_media_group.dart';
import '../../utils/media_image_helper.dart';
import '../../widgets/optimized_media_image.dart';
import '../image_cache_service.dart';

/// Resolves the client that can sign a group's artwork URL, by server id.
/// Same shape the grid and the card already take, so one resolver serves all
/// three. Returning null (offline, not yet bound) is a normal answer, not an
/// error — that group is simply skipped.
typedef UnifiedArtworkClientResolver = MediaServerClient? Function(String serverId);

/// The seam that makes this testable without a network.
///
/// The default is [precacheImage], the same call `library_browse_tab.dart`
/// already uses for its grid. A test injects its own and asserts which
/// requests would have been warmed, in what order.
typedef UnifiedArtworkPrecache = Future<void> Function(ArtworkPrefetchRequest request, BuildContext context);

/// One poster the prefetcher decided to warm.
///
/// Carries the resolved [url] and [cacheKey] beside the [provider] so a caller
/// (and a test) can see *what* is being fetched without unwrapping the
/// provider chain.
@immutable
class ArtworkPrefetchRequest {
  const ArtworkPrefetchRequest({
    required this.groupId,
    required this.url,
    required this.cacheKey,
    required this.provider,
  });

  /// [UnifiedMediaGroup.groupId] of the title this poster belongs to.
  final String groupId;

  /// The sized, signed artwork URL, straight from
  /// [MediaImageHelper.getOptimizedImageUrl].
  final String url;

  /// The disk-cache key `OptimizedMediaImage` will look this image up under.
  final String cacheKey;

  /// Ready to hand to [precacheImage]; identical in key to what the card
  /// resolves later.
  final ImageProvider<Object> provider;

  @override
  String toString() => 'ArtworkPrefetchRequest($groupId, $url)';
}

/// Warms poster artwork around the visible range of the unified catalog grid.
///
/// Owned by the widget that scrolls; [dispose] it with that widget. Safe to
/// call [prefetchAround] on every scroll tick — repeat calls over an unchanged
/// window are a no-op, and anything already dispatched is never dispatched
/// twice.
class UnifiedArtworkPrefetcher {
  UnifiedArtworkPrefetcher({
    required this.clientFor,
    UnifiedArtworkPrecache? precache,
    this.lookaheadItems = defaultLookaheadItems,
    this.maxConcurrent = defaultMaxConcurrent,
    this.maxRememberedUrls = defaultMaxRememberedUrls,
  }) : _precache = precache ?? _precacheThroughFlutter;

  /// How many cards beyond each edge of the viewport get warmed.
  ///
  /// Twelve, counted in *cards* rather than rows because this type is not told
  /// the column count: hoofdstuk 10.2's grid runs five to seven columns
  /// depending on the panel width, so twelve is roughly two rows ahead and two
  /// behind on every one of them. Two rows is the smallest margin that covers
  /// a single D-pad row step plus the frame it takes to notice one, and small
  /// enough that a fast scroll through forty titles never has more than a few
  /// dozen posters in the air.
  static const int defaultLookaheadItems = 12;

  /// Hard ceiling on one window, whatever range a caller reports.
  ///
  /// A grid that reports its whole list as visible (a caller bug, or a very
  /// tall panel) must not turn into a catalogue-wide download. Sixty is a
  /// generous full screen of a seven-column grid plus both margins.
  static const int maxWindowItems = 60;

  /// In-flight cap. Below the six permits `image_cache_service.dart` grants
  /// artwork globally, so on-screen cards always keep slots.
  static const int defaultMaxConcurrent = 3;

  /// How many dispatched URLs are remembered for de-duplication. Bounded
  /// because a long scroll session would otherwise grow the set without limit;
  /// falling off the end costs at most one repeat request, which the disk
  /// cache answers.
  static const int defaultMaxRememberedUrls = 512;

  /// Resolves the client for a group's server. Same callback the grid and the
  /// card take, so one resolver serves all three.
  final UnifiedArtworkClientResolver clientFor;

  final UnifiedArtworkPrecache _precache;

  final int lookaheadItems;
  final int maxConcurrent;
  final int maxRememberedUrls;

  /// URLs already handed to [_precache]. Insertion-ordered so the oldest can
  /// be evicted once the set is full.
  final LinkedHashSet<String> _requested = LinkedHashSet<String>();

  /// Built but not yet dispatched, in warm order. Replaced wholesale by the
  /// next [prefetchAround]: a queue from a viewport the user has already left
  /// is stale by definition.
  final List<_PendingPrefetch> _pending = <_PendingPrefetch>[];
  final Set<String> _pendingUrls = <String>{};

  int _inFlight = 0;
  bool _disposed = false;

  /// The window the current queue was built from, so an unchanged call costs
  /// nothing. Identity on the list: the catalogue rebuilds its group list
  /// wholesale on every merge round, so a new list instance means new content.
  List<UnifiedMediaGroup>? _lastGroups;
  int? _lastFirst;
  int? _lastLast;
  Size? _lastPosterSize;

  /// Queues the posters around the visible range and starts warming them.
  ///
  /// [firstVisibleIndex] and [lastVisibleIndex] are inclusive indices into
  /// [groups]; out-of-range or inverted values are clamped rather than
  /// rejected, because a scroll callback firing one frame after a filter
  /// shortened the list is normal, not a bug.
  ///
  /// [posterSize] is the *logical* box the artwork will be laid out in — for
  /// the unified card, the artwork's width and its 2:3 height, which is the
  /// card's width minus whatever the focus ring insets. It is required rather
  /// than derived because this service deliberately knows nothing about the
  /// grid's layout. Passing a slightly wrong size is harmless but wasteful:
  /// the transcode dimensions bucket in steps of 40×60, so a large enough
  /// error lands in a different bucket and warms a URL the card will not ask
  /// for.
  ///
  /// [context] is used exactly as `OptimizedMediaImage` uses its own: to read
  /// the effective device pixel ratio, and to hand [precacheImage] a
  /// configuration. It is not retained across a dispatch — a queued entry
  /// whose context has been unmounted is dropped.
  void prefetchAround({
    required BuildContext context,
    required List<UnifiedMediaGroup> groups,
    required int firstVisibleIndex,
    required int lastVisibleIndex,
    required Size posterSize,
  }) {
    if (_disposed || groups.isEmpty) return;
    if (!posterSize.width.isFinite || !posterSize.height.isFinite) return;
    if (posterSize.width <= 0 || posterSize.height <= 0) return;

    if (identical(groups, _lastGroups) &&
        firstVisibleIndex == _lastFirst &&
        lastVisibleIndex == _lastLast &&
        posterSize == _lastPosterSize) {
      return;
    }
    _lastGroups = groups;
    _lastFirst = firstVisibleIndex;
    _lastLast = lastVisibleIndex;
    _lastPosterSize = posterSize;

    final last = groups.length - 1;
    final first = firstVisibleIndex.clamp(0, last);
    final visibleEnd = lastVisibleIndex.clamp(first, last);

    final devicePixelRatio = MediaImageHelper.effectiveDevicePixelRatio(context);

    _pending.clear();
    _pendingUrls.clear();

    for (final index in _warmOrder(first: first, visibleEnd: visibleEnd, lastIndex: last)) {
      if (_pending.length >= maxWindowItems) break;
      final request = _buildRequest(groups[index], posterSize, devicePixelRatio);
      if (request == null) continue;
      if (_requested.contains(request.url) || !_pendingUrls.add(request.url)) continue;
      _pending.add(_PendingPrefetch(request, context));
    }

    _pump();
  }

  /// The order posters are warmed in, as indices into the group list.
  ///
  /// Visible first — those are the placeholders the user is looking at right
  /// now. Then forward, because a grid is scrolled downwards far more often
  /// than upwards. Then backwards, nearest first, which is what a user who
  /// overshot and comes back needs.
  Iterable<int> _warmOrder({required int first, required int visibleEnd, required int lastIndex}) sync* {
    for (var index = first; index <= visibleEnd; index++) {
      yield index;
    }
    final forwardEnd = (visibleEnd + lookaheadItems).clamp(0, lastIndex);
    for (var index = visibleEnd + 1; index <= forwardEnd; index++) {
      yield index;
    }
    final backwardEnd = (first - lookaheadItems).clamp(0, lastIndex);
    for (var index = first - 1; index >= backwardEnd; index--) {
      yield index;
    }
  }

  /// The request for one group, or null when there is nothing to warm: no
  /// artwork on the representative source, no client to sign a relative path
  /// with (an offline or unbound server), or a resolver that threw.
  ArtworkPrefetchRequest? _buildRequest(UnifiedMediaGroup group, Size posterSize, double devicePixelRatio) {
    final source = group.representativeSource;
    final thumbPath = source.item.thumbPath;
    if (thumbPath == null || thumbPath.isEmpty) return null;

    MediaServerClient? client;
    try {
      client = clientFor(source.serverId.value);
    } catch (_) {
      // A resolver that throws means the same thing to us as one that returns
      // null: no client. Degrade to that rather than letting it reach the
      // scroll callback — and a self-contained URL that needs no client at all
      // still gets warmed.
      client = null;
    }

    final String url;
    try {
      url = MediaImageHelper.getOptimizedImageUrl(
        client: client,
        thumbPath: thumbPath,
        maxWidth: posterSize.width,
        maxHeight: posterSize.height,
        devicePixelRatio: devicePixelRatio,
        imageType: ImageType.poster,
      );
    } catch (_) {
      // A URL that cannot be signed is a poster we do not warm, not a crash.
      return null;
    }
    if (url.isEmpty) return null;

    final scaledWidth = posterSize.width * devicePixelRatio;
    final scaledHeight = posterSize.height * devicePixelRatio;
    final (_, memHeight) = MediaImageHelper.getMemCacheDimensions(
      displayWidth: scaledWidth.isFinite && scaledWidth > 0 ? scaledWidth.round() : 0,
      displayHeight: scaledHeight.isFinite && scaledHeight > 0 ? scaledHeight.round() : 0,
      imageType: ImageType.poster,
    );

    // The image widget's own key, not a copy of it: a warmed entry stored
    // under a different key is a second copy the card never finds.
    final cacheKey = OptimizedMediaImage.artworkCacheKey(url);
    final provider = CachedNetworkImageProvider(
      url,
      cacheKey: cacheKey,
      cacheManager: PlexImageCacheManager.instance,
      headers: const {'User-Agent': 'Pleya'},
    );

    return ArtworkPrefetchRequest(
      groupId: group.groupId,
      url: url,
      cacheKey: cacheKey,
      // Same wrapper the card puts around the same provider, so both resolve
      // to one entry in Flutter's image cache instead of two decodes.
      provider: ResizeImage.resizeIfNeeded(null, memHeight > 0 ? memHeight : null, provider),
    );
  }

  void _pump() {
    while (!_disposed && _inFlight < maxConcurrent && _pending.isNotEmpty) {
      final next = _pending.removeAt(0);
      _pendingUrls.remove(next.request.url);
      // A context torn down between queueing and dispatch (the grid left the
      // tree while a burst was draining) can no longer produce an image
      // configuration; skip rather than assert.
      if (!next.context.mounted) continue;
      _remember(next.request.url);
      _dispatch(next);
    }
  }

  void _dispatch(_PendingPrefetch pending) {
    _inFlight++;
    Future<void> warming;
    try {
      warming = _precache(pending.request, pending.context);
    } catch (_) {
      // A synchronously throwing precache still has to release its slot.
      _onSettled();
      return;
    }
    // Errors are the normal outcome for a server that went away mid-scroll:
    // swallow them here so nothing surfaces as an unhandled async error in the
    // widget that called us.
    warming.catchError((Object _) {}).whenComplete(_onSettled);
  }

  void _onSettled() {
    if (_inFlight > 0) _inFlight--;
    if (!_disposed) _pump();
  }

  void _remember(String url) {
    _requested.add(url);
    while (_requested.length > maxRememberedUrls) {
      _requested.remove(_requested.first);
    }
  }

  /// Stops queueing and forgets everything queued.
  ///
  /// Requests already in flight are not cancellable — `precacheImage` has no
  /// handle — but their completion becomes a no-op, and no further request is
  /// ever dispatched. Idempotent.
  void dispose() {
    _disposed = true;
    _pending.clear();
    _pendingUrls.clear();
    _requested.clear();
    _lastGroups = null;
    _lastFirst = null;
    _lastLast = null;
    _lastPosterSize = null;
  }

  @visibleForTesting
  bool get isDisposed => _disposed;

  @visibleForTesting
  int get pendingCount => _pending.length;

  @visibleForTesting
  int get inFlightCount => _inFlight;
}

/// The default seam: Flutter's own [precacheImage], on the context the caller
/// handed to [UnifiedArtworkPrefetcher.prefetchAround].
Future<void> _precacheThroughFlutter(ArtworkPrefetchRequest request, BuildContext context) =>
    // onError swallows: a poster that 404s while scrolling is a missing
    // poster, not a FlutterError dumped to the console for every tile.
    precacheImage(request.provider, context, onError: (Object error, StackTrace? stack) {});

class _PendingPrefetch {
  const _PendingPrefetch(this.request, this.context);

  final ArtworkPrefetchRequest request;
  final BuildContext context;
}
