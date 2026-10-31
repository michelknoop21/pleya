import 'package:flutter/foundation.dart';

/// Trakt API client id and base URLs.
///
/// Only the public client id is bundled. The device-code flow, token refresh
/// and revoke work without a client secret (measured 11 October 2026, see
/// docs/ROADMAP.md "BP-07 Trakt-poort"), and a secret never goes into a
/// dart-define because it is readable from the binary.
class TraktConstants {
  TraktConstants._();

  // Registered Trakt app client id, injected at build time. Register your own
  // app at https://trakt.tv/oauth/applications and pass it via
  // --dart-define=TRAKT_CLIENT_ID=...
  // Empty by default so no third-party app identity is shipped.
  static const String clientId = String.fromEnvironment('TRAKT_CLIENT_ID');

  /// Whether Trakt integration has been configured for this build: a client
  /// id is all it needs.
  static bool get isConfigured => configuredFor(clientId);

  @visibleForTesting
  static bool configuredFor(String id) => id.isNotEmpty;

  static const String apiBase = 'https://api.trakt.tv';
  static const String apiVersion = '2';

  // OAuth endpoints
  static const String deviceCodeUrl = '$apiBase/oauth/device/code';
  static const String deviceTokenUrl = '$apiBase/oauth/device/token';
  static const String tokenUrl = '$apiBase/oauth/token';
  static const String revokeUrl = '$apiBase/oauth/revoke';

  // Scopes — Trakt's OAuth doesn't use granular scopes; "public" is the only value
  static const String scope = 'public';

  /// Headers required on every Trakt API call. Reading public data takes
  /// [clientId] alone: no [accessToken], so no account.
  static Map<String, String> headers({String? accessToken, String clientId = clientId}) {
    return {
      'Content-Type': 'application/json',
      'Accept': 'application/json',
      'trakt-api-version': apiVersion,
      'trakt-api-key': clientId,
      if (accessToken != null) 'Authorization': 'Bearer $accessToken',
    };
  }
}

/// Build a `SharedPreferences` key scoped to the given Plex profile UUID.
/// Mirrors the `_userPrefix` pattern in [StorageService] so each profile gets
/// its own Trakt session and sync queue.
String traktUserKey(String userUuid, String baseKey) => userUuid.isEmpty ? baseKey : 'user_${userUuid}_$baseKey';

/// Scrobble lifecycle state sent to Trakt's `/scrobble/{name}` endpoints.
enum TraktScrobbleState { start, pause, stop }

/// Direction of a watched-status sync push.
enum TraktSyncOp {
  add,
  remove;

  static TraktSyncOp fromName(String name) =>
      values.firstWhere((v) => v.name == name, orElse: () => throw ArgumentError('Unknown TraktSyncOp: $name'));
}

/// Trakt-relevant media types. Accepts the neutral [MediaKind.id] string
/// (`'movie'`, `'episode'`) used across both Plex and Jellyfin watch events.
enum TraktMediaKind {
  movie,
  episode;

  static TraktMediaKind? tryFromMediaKindId(String type) => switch (type) {
    'movie' => movie,
    'episode' => episode,
    _ => null,
  };

  static TraktMediaKind fromName(String name) =>
      values.firstWhere((v) => v.name == name, orElse: () => throw ArgumentError('Unknown TraktMediaKind: $name'));
}
