import 'dart:io' show Directory, Platform;

import 'package:flutter/services.dart';

import '../i18n/strings.g.dart';
import '../media/ids.dart';
import '../media/media_item.dart';
import '../media/media_item_types.dart';
import '../media/media_kind.dart';
import '../media/media_server_client.dart';
import '../utils/app_logger.dart';
import '../utils/platform_detector.dart';
import 'settings_service.dart' show EpisodePosterMode;
import 'top_shelf_images.dart';

/// What a launcher shelf tap asks for. Top Shelf sends `play` for the remote's
/// Play button and `open` for a click; Android Watch Next and links written by
/// older builds carry no action and keep the original play-on-tap behaviour.
enum ShelfLinkAction { legacy, play, open }

class ShelfDeepLink {
  const ShelfDeepLink(this.contentId, [this.action = ShelfLinkAction.legacy]);

  final String contentId;
  final ShelfLinkAction action;

  /// Native sends either a bare content id or `{contentId, action?}`.
  static ShelfDeepLink? fromNative(Object? raw) {
    if (raw is String) return raw.isEmpty ? null : ShelfDeepLink(raw);
    if (raw is! Map) return null;
    final contentId = raw['contentId'];
    if (contentId is! String || contentId.isEmpty) return null;
    final action = switch (raw['action']) {
      'play' => ShelfLinkAction.play,
      'open' => ShelfLinkAction.open,
      _ => ShelfLinkAction.legacy,
    };
    return ShelfDeepLink(contentId, action);
  }

  /// True when the tap starts the player; false opens the detail page. `play`
  /// on something that cannot play by itself (a show, a season) opens detail.
  bool startsPlaybackFor(MediaKind kind) => switch (action) {
    ShelfLinkAction.legacy => true,
    ShelfLinkAction.open => false,
    ShelfLinkAction.play => kind == MediaKind.movie || kind == MediaKind.episode || kind == MediaKind.clip,
  };
}

/// Syncs Continue Watching content to platform launcher surfaces.
///
/// Android uses the Watch Next row. tvOS uses the app's Top Shelf extension.
class SystemShelfService {
  static const MethodChannel _androidChannel = MethodChannel('com.pleya/watch_next');
  static const MethodChannel _tvosChannel = MethodChannel('com.pleya/system_shelf');
  static const bool _tvosBuild = bool.fromEnvironment('TVOS_BUILD');

  static final SystemShelfService _instance = SystemShelfService._internal();
  factory SystemShelfService() => _instance;

  SystemShelfService._internal() {
    _androidChannel.setMethodCallHandler(_handleMethodCall);
    _tvosChannel.setMethodCallHandler(_handleMethodCall);
  }

  /// Downloads carousel artwork into the app-group container (tvOS only).
  TopShelfImages topShelfImages = TopShelfImages();

  /// Callback for warm-start launcher surface taps.
  ValueChanged<ShelfDeepLink>? onShelfItemTap;

  MethodChannel? get _channel {
    if (Platform.isAndroid) return _androidChannel;
    if (Platform.isIOS && (_tvosBuild || PlatformDetector.isAppleTV())) return _tvosChannel;
    return null;
  }

  Future<dynamic> _handleMethodCall(MethodCall call) async {
    if (call.method == 'onWatchNextTap' || call.method == 'onShelfItemTap') {
      final args = call.arguments;
      final link = args is Map ? ShelfDeepLink.fromNative(args) : null;
      final callback = onShelfItemTap;
      if (link != null && callback != null) {
        callback(link);
        // Native also parks every tap as its pending cold-start link. This one
        // was delivered, so drain it; otherwise a later getInitialDeepLink (a
        // MainScreen rebuild) would replay it. Undelivered taps stay parked.
        await _takePendingLink(call.method == 'onShelfItemTap' ? _tvosChannel : _androidChannel);
      }
    }
  }

  /// Get a pending deep link from cold start (consumed on first call).
  Future<ShelfDeepLink?> getInitialDeepLink() => _takePendingLink(_channel);

  Future<ShelfDeepLink?> _takePendingLink(MethodChannel? channel) async {
    if (channel == null) return null;
    try {
      return ShelfDeepLink.fromNative(await channel.invokeMethod<Object?>('getInitialDeepLink'));
    } on MissingPluginException catch (e) {
      appLogger.w('System shelf initial deep link failed: native channel missing', error: e);
      return null;
    } catch (e) {
      appLogger.w('Failed to get system shelf initial deep link', error: e);
      return null;
    }
  }

  /// Check whether the current platform has a launcher shelf integration.
  Future<bool> isSupported() async {
    final channel = _channel;
    if (channel == null) return false;
    try {
      return await channel.invokeMethod<bool>('isSupported') ?? false;
    } on MissingPluginException catch (e) {
      appLogger.w('System shelf unsupported: native channel missing', error: e);
      return false;
    } on PlatformException catch (e) {
      appLogger.w('System shelf unsupported: native platform error', error: e);
      return false;
    } catch (e) {
      appLogger.w('System shelf unsupported: native support check failed', error: e);
      return false;
    }
  }

  /// Sync Continue Watching items to the current platform's launcher shelf.
  ///
  /// On tvOS the Top Shelf also gets a `carousel`: [hero] (the Home hero's
  /// films) first, then Continue Watching, see [carouselItemsFor]. Android
  /// Watch Next only reads `items`, so it stays Continue Watching only.
  Future<bool> syncFromContinueWatching(
    List<MediaItem> continueWatchingItems,
    MediaServerClient Function(ServerId serverId) getClientForServerId, {
    bool hideSpoilers = false,
    List<MediaItem> hero = const [],
  }) async {
    final channel = _channel;
    if (channel == null) return false;

    try {
      final items = continueWatchingItems.map((item) {
        return _convertToShelfItem(item, getClientForServerId, hideSpoilers: hideSpoilers);
      }).toList();

      final supported = await isSupported();
      if (!supported) return false;

      final args = <String, dynamic>{'items': items};
      if (identical(channel, _tvosChannel)) {
        args['sections'] = [
          {'id': 'continue_watching', 'title': t.discover.continueWatching, 'items': items},
        ];
        final carousel = await _localCarouselImages(
          carouselItemsFor(hero, continueWatchingItems, getClientForServerId, hideSpoilers: hideSpoilers),
        );
        // No carousel item with an image: the extension keeps the sectioned row.
        if (carousel.isNotEmpty) args['carousel'] = carousel;
      }

      return await channel.invokeMethod<bool>('sync', args) ?? false;
    } on MissingPluginException catch (e) {
      appLogger.e('Failed to sync system shelf: native channel missing', error: e);
      return false;
    } on PlatformException catch (e) {
      appLogger.e('Failed to sync system shelf: native platform error', error: e);
      return false;
    } catch (e) {
      appLogger.e('Failed to sync system shelf', error: e);
      return false;
    }
  }

  /// The carousel with `file://` artwork in the app-group folder the native
  /// side names; empty when that folder is unavailable, which leaves the
  /// sectioned row. Runs for an empty carousel too, so its files get removed.
  Future<List<Map<String, dynamic>>> _localCarouselImages(List<Map<String, dynamic>> carousel) async {
    final path = await _tvosChannel.invokeMethod<String>('imageDirectory');
    if (path == null || path.isEmpty) return const [];
    return topShelfImages.localize(carousel, Directory(path));
  }

  /// Clear all launcher shelf entries owned by the app.
  Future<bool> clear() async {
    final channel = _channel;
    if (channel == null) return false;
    try {
      return await channel.invokeMethod<bool>('clear') ?? false;
    } on MissingPluginException catch (e) {
      appLogger.e('Failed to clear system shelf: native channel missing', error: e);
      return false;
    } on PlatformException catch (e) {
      appLogger.e('Failed to clear system shelf: native platform error', error: e);
      return false;
    } catch (e) {
      appLogger.e('Failed to clear system shelf', error: e);
      return false;
    }
  }

  /// Remove a single launcher shelf item.
  Future<bool> removeItem(ServerId serverId, String ratingKey) async {
    final channel = _channel;
    if (channel == null) return false;
    try {
      final contentId = _buildContentId(serverId, ratingKey);
      return await channel.invokeMethod<bool>('remove', {'contentId': contentId}) ?? false;
    } on MissingPluginException catch (e) {
      appLogger.e('Failed to remove system shelf item: native channel missing', error: e);
      return false;
    } on PlatformException catch (e) {
      appLogger.e('Failed to remove system shelf item: native platform error', error: e);
      return false;
    } catch (e) {
      appLogger.e('Failed to remove system shelf item', error: e);
      return false;
    }
  }

  /// The Top Shelf carousel (`TVTopShelfCarouselContent`, style `.details`):
  /// [hero] first, then [continueWatching]. A film that is in both keeps only
  /// its Continue Watching entry, because tvOS requires unique identifiers and
  /// that entry carries the progress. Items without a usable 16:9 image are
  /// dropped; an empty result means the caller keeps the sectioned row.
  static List<Map<String, dynamic>> carouselItemsFor(
    List<MediaItem> hero,
    List<MediaItem> continueWatching,
    MediaServerClient Function(ServerId serverId) getClientForServerId, {
    bool hideSpoilers = false,
  }) {
    String idOf(MediaItem item) => _buildContentId(serverIdOrNull(item.serverId), item.id);
    final continueIds = continueWatching.map(idOf).toSet();
    final seen = <String>{};
    final result = <Map<String, dynamic>>[];
    void add(MediaItem item, String contextTitle) {
      final contentId = idOf(item);
      if (!seen.add(contentId)) return;
      final imageUri = _carouselImageUri(item, getClientForServerId, hideSpoilers: hideSpoilers);
      if (imageUri == null) return;
      final isEpisode = item.kind == MediaKind.episode && item.grandparentTitle != null;
      final spoilerSafe = hideSpoilers && item.shouldHideSpoiler;
      result.add({
        'contentId': contentId,
        'title': isEpisode ? item.grandparentTitle! : item.title ?? '',
        'contextTitle': contextTitle,
        'summary': spoilerSafe ? null : item.summary,
        'genre': item.genres?.firstOrNull,
        'releaseDate': _releaseDate(item),
        'duration': item.durationMs,
        'imageUri': imageUri,
        'namedAttributes': _namedAttributes(item),
      });
    }

    for (final item in hero) {
      if (continueIds.contains(idOf(item))) continue;
      add(item, t.discover.recentlyReleased);
    }
    for (final item in continueWatching) {
      add(item, _continueWatchingContext(item));
    }
    return result;
  }

  /// Director and cast for the details style; tvOS shows at most four.
  static List<Map<String, dynamic>> _namedAttributes(MediaItem item) {
    final directors = item.directors?.take(2).toList() ?? const <String>[];
    final cast = item.roles?.map((r) => r.tag).where((tag) => tag.isNotEmpty).take(3).toList() ?? const <String>[];
    return [
      if (directors.isNotEmpty) {'name': t.metadataEdit.director, 'values': directors},
      if (cast.isNotEmpty) {'name': t.discover.cast, 'values': cast},
    ];
  }

  /// "Verder kijken · S2E5 · 42 min over"; a carousel item has no progress bar.
  static String _continueWatchingContext(MediaItem item) {
    final season = item.parentIndex;
    final episode = item.index;
    final offset = item.viewOffsetMs ?? 0;
    final duration = item.durationMs ?? 0;
    final minutesLeft = offset > 0 && duration > offset ? ((duration - offset) / 60000).round() : 0;
    return [
      t.discover.continueWatching,
      if (item.kind == MediaKind.episode && season != null && episode != null)
        t.discover.playEpisode(season: season, episode: episode),
      if (minutesLeft > 0) t.discover.minutesLeft(minutes: minutesLeft),
    ].join(' · ');
  }

  /// Full-screen 16:9 backdrop: the show's for an episode, else the item's own.
  /// Without one, an episode or clip falls back to its 16:9 still (never for an
  /// unwatched episode when spoilers are hidden). A film poster is portrait,
  /// so a film without a backdrop gets null.
  static String? _carouselImageUri(
    MediaItem item,
    MediaServerClient Function(ServerId serverId) getClientForServerId, {
    required bool hideSpoilers,
  }) {
    final serverId = item.serverId;
    if (serverId == null) return null;
    final wideStill =
        item.kind == MediaKind.clip || (item.kind == MediaKind.episode && !(hideSpoilers && item.shouldHideSpoiler));
    final path = item.kind == MediaKind.episode ? item.grandparentArtPath ?? item.artPath : item.artPath;
    final chosen = path ?? (wideStill ? item.thumbPath : null);
    if (chosen == null) return null;
    try {
      // ponytail: tvOS draws the carousel full screen (1920x1080 pt); the SDK
      // names no pixel size. One 1080p URL serves both scale traits, because
      // Plex upscales on request and a 4K fetch would mostly be upscaled 1080p.
      final url = getClientForServerId(ServerId(serverId)).thumbnailUrl(chosen, width: 1920, height: 1080);
      return url.isEmpty ? null : url;
    } catch (e) {
      appLogger.w('Failed to get Top Shelf image URL for ${item.title}', error: e);
      return null;
    }
  }

  /// `yyyy-MM-dd` for `creationDate`: the release date, else January 1 of the year.
  static String? _releaseDate(MediaItem item) {
    final date = DateTime.tryParse(item.originallyAvailableAt ?? '');
    if (date != null) return date.toIso8601String().substring(0, 10);
    final year = item.year;
    return year != null && year > 999 ? '$year-01-01' : null;
  }

  /// Build a content ID. Format: pleya_{serverId}_{ratingKey}
  static String _buildContentId(ServerId? serverId, String ratingKey) {
    return 'pleya_${serverId ?? 'unknown'}_$ratingKey';
  }

  /// Parse a content ID back to (serverId, ratingKey), or null if invalid.
  static (ServerId serverId, String ratingKey)? parseContentId(String contentId) {
    if (!contentId.startsWith('pleya_')) return null;
    final parts = contentId.substring(6).split('_');
    if (parts.length < 2) return null;
    return (ServerId(parts.first), parts.sublist(1).join('_'));
  }

  Map<String, dynamic> _convertToShelfItem(
    MediaItem item,
    MediaServerClient Function(ServerId serverId) getClientForServerId, {
    bool hideSpoilers = false,
  }) {
    final contentId = _buildContentId(serverIdOrNull(item.serverId), item.id);

    String? posterUri;
    try {
      if (item.serverId != null) {
        final client = getClientForServerId(ServerId(item.serverId!));
        String? thumbPath;
        if (hideSpoilers && item.shouldHideSpoiler) {
          thumbPath = item.spoilerSafeArt;
        }
        thumbPath ??= item.posterThumb(mode: EpisodePosterMode.episodeThumbnail, mixedHubContext: true);
        if (thumbPath != null) {
          posterUri = client.thumbnailUrl(thumbPath);
        }
      }
    } catch (e) {
      appLogger.w('Failed to get shelf poster URL for ${item.title}', error: e);
    }

    final String title;
    final String? episodeTitle;
    if (item.kind == MediaKind.episode && item.grandparentTitle != null) {
      title = item.grandparentTitle!;
      episodeTitle = item.title;
    } else {
      title = item.title ?? '';
      episodeTitle = null;
    }

    final lastEngagementTime = item.lastViewedAt != null
        ? item.lastViewedAt! * 1000
        : DateTime.now().millisecondsSinceEpoch;

    return {
      'contentId': contentId,
      'title': title,
      'episodeTitle': episodeTitle,
      'description': item.summary,
      'posterUri': posterUri,
      'type': item.kind.name,
      'duration': item.durationMs ?? 0,
      'lastPlaybackPosition': item.viewOffsetMs ?? 0,
      'lastEngagementTime': lastEngagementTime,
      'seriesTitle': item.grandparentTitle,
      'seasonNumber': item.parentIndex,
      'episodeNumber': item.index,
    };
  }
}
