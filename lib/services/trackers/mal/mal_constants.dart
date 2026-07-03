/// Bundled MyAnimeList API endpoints and public client ID.
///
/// The authorize flow lives in the Plezy relay's OAuth proxy; see
/// `lib/services/trackers/oauth_proxy_client.dart`. Only the refresh path
/// (public-client, no redirect) calls MAL directly from the device.
class MalConstants {
  MalConstants._();

  /// Public MAL client ID, injected at build time via
  /// --dart-define=MAL_CLIENT_ID=... Empty ships no third-party identity.
  static const String clientId = String.fromEnvironment('MAL_CLIENT_ID');

  /// Whether MyAnimeList integration has been configured for this build.
  static bool get isConfigured => clientId.isNotEmpty;

  static const String apiBase = 'https://api.myanimelist.net/v2';
  static const String tokenUrl = 'https://myanimelist.net/v1/oauth2/token';

  static Map<String, String> headers({String? accessToken}) => {
    'Accept': 'application/json',
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };
}
