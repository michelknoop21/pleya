import '../utils/app_logger.dart';

/// Backend identifier for a media item, library, or server.
///
/// Used as a discriminator on neutral domain types so consumers can branch on
/// backend-specific behavior (e.g. only Plex supports server-side play queues
/// in v1) and so persisted records can round-trip the source of an item.
enum MediaBackend {
  plex,
  jellyfin,
  local,
  pleyaServer;

  String get id => switch (this) {
    MediaBackend.plex => 'plex',
    MediaBackend.jellyfin => 'jellyfin',
    MediaBackend.local => 'local',
    MediaBackend.pleyaServer => 'pleyaServer',
  };

  static MediaBackend fromId(String id) => switch (id) {
    'plex' => MediaBackend.plex,
    'jellyfin' => MediaBackend.jellyfin,
    'local' => MediaBackend.local,
    'pleyaServer' => MediaBackend.pleyaServer,
    _ => throw ArgumentError('Unknown MediaBackend id: $id'),
  };

  /// Like [fromId] but tolerates legacy/missing values by defaulting to Plex.
  /// Used by JSON deserialization of cached offline data:
  /// - `null` is the pre-Jellyfin shape and silently defaults to Plex.
  /// - An unrecognized non-null id logs a warning and defaults to Plex; this
  ///   surfaces corrupted cache rows or schema drift instead of silently
  ///   misclassifying Jellyfin items as Plex.
  ///
  /// The known-id set is derived from [values] rather than written out again.
  /// A hand-maintained list here is how a new backend ends up parsed as Plex
  /// without a single warning: the enum grows, the literal list does not, and
  /// the fallback swallows the difference. That failure is silent by
  /// construction, which is why PS-3 added a regression test for exactly this
  /// value.
  static MediaBackend fromString(String? id) {
    if (id == null) return MediaBackend.plex;
    for (final backend in MediaBackend.values) {
      if (backend.id == id) return backend;
    }
    appLogger.w('Unknown MediaBackend id "$id"; defaulting to plex');
    return MediaBackend.plex;
  }
}
