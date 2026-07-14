/// Shared constants, enums and permission helpers for the Jellyseerr /
/// Overseerr ("seerr") request integration.
///
/// Jellyseerr is API-compatible with Overseerr v1, so everything is pinned to
/// `/api/v1`. Responses are parsed leniently (unknown fields ignored) so both
/// Overseerr and Jellyseerr (v1/v2) keep working.
class SeerrConstants {
  SeerrConstants._();

  /// Pinned API prefix. The client tolerates a base URL that already ends in
  /// `/api/v1` (see [normalizeBaseUrl]).
  static const String apiPrefix = '/api/v1';

  static const Duration requestTimeout = Duration(seconds: 10);
  static const Duration authTimeout = Duration(seconds: 10);

  /// How long a status/me lookup is cached before re-fetching.
  static const Duration statusCacheTtl = Duration(seconds: 60);

  /// TMDB poster size used across request/discover surfaces.
  static const String tmdbImageBase = 'https://image.tmdb.org/t/p/w342';

  /// Wide backdrop used on the seerr media detail hero.
  static const String tmdbBackdropBase = 'https://image.tmdb.org/t/p/w1280';

  /// Cast profile photos.
  static const String tmdbProfileBase = 'https://image.tmdb.org/t/p/w185';

  static String tmdbPosterUrl(String? posterPath) =>
      (posterPath == null || posterPath.isEmpty) ? '' : '$tmdbImageBase$posterPath';

  static String tmdbBackdropUrl(String? backdropPath) =>
      (backdropPath == null || backdropPath.isEmpty) ? '' : '$tmdbBackdropBase$backdropPath';

  static String tmdbProfileUrl(String? profilePath) =>
      (profilePath == null || profilePath.isEmpty) ? '' : '$tmdbProfileBase$profilePath';

  /// Normalize a user-entered server URL: strip a trailing slash and tolerate a
  /// pasted `/api/v1` suffix (we always append the prefix ourselves).
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    // A pasted `host:5055` without scheme would fail every request; assume
    // https (the common reverse-proxy setup) when none is given.
    if (url.isNotEmpty && !url.contains('://')) {
      url = 'https://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    // Only strip the exact pinned suffix we append ourselves. A bare `/api` is
    // left alone — some servers are legitimately reverse-proxied under `/api`.
    if (url.toLowerCase().endsWith('/api/v1')) {
      url = url.substring(0, url.length - '/api/v1'.length);
    }
    return url;
  }
}

/// How the app authenticates against the seerr server.
///
/// The `.name` is persisted — do not rename without a migration.
enum SeerrAuthMode {
  /// `POST /auth/plex {authToken}` using the Plex token the app already holds.
  /// Default & recommended: per-user attribution, quota, no key to type.
  plex,

  /// `POST /auth/local {email, password}` for Jellyseerr local users.
  local,

  /// `X-Api-Key` admin mode; requests are attributed to the admin user.
  apiKey,
}

/// `mediaInfo.status` values (Overseerr `MediaStatus`).
enum SeerrMediaStatus {
  unknown(1),
  pending(2),
  processing(3),
  partiallyAvailable(4),
  available(5);

  final int value;
  const SeerrMediaStatus(this.value);

  static SeerrMediaStatus fromValue(int? v) {
    for (final s in values) {
      if (s.value == v) return s;
    }
    return SeerrMediaStatus.unknown;
  }

  bool get isAvailable => this == available;
  bool get isRequested => this == pending || this == processing || this == partiallyAvailable;
}

/// Request lifecycle status (Overseerr `MediaRequestStatus`).
enum SeerrRequestStatus {
  pending(1),
  approved(2),
  declined(3),
  failed(4),
  completed(5);

  final int value;
  const SeerrRequestStatus(this.value);

  static SeerrRequestStatus fromValue(int? v) {
    for (final s in values) {
      if (s.value == v) return s;
    }
    return SeerrRequestStatus.pending;
  }
}

/// Overseerr permission bitmask flags. `ADMIN` implies everything.
class SeerrPermission {
  SeerrPermission._();

  static const int admin = 2;
  static const int manageRequests = 16;
  static const int request = 32;
  // Overseerr `Permission`: REQUEST_4K=1024, _MOVIE=2048, _TV=4096. (512 is
  // AUTO_APPROVE_TV — using it here silently mis-gated the 4K toggle.)
  static const int request4k = 1024;
  static const int request4kMovie = 2048;
  static const int request4kTv = 4096;
  static const int anyRequest4k = request4k | request4kMovie | request4kTv;

  /// True when [permissions] grants [flag] (or is ADMIN).
  static bool has(int permissions, int flag) => (permissions & admin) != 0 || (permissions & flag) != 0;
}
