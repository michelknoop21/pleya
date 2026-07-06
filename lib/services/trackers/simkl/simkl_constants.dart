/// Bundled Simkl API credentials and endpoints.
///
/// Register at https://simkl.com/settings/developer — app type should be
/// "Commandline / Console / Device code" (the same flow Trakt uses).
/// Replace [clientId] with the registered client ID before shipping.
class SimklConstants {
  SimklConstants._();

  /// Registered Simkl app client ID, injected at build time via
  /// --dart-define=SIMKL_CLIENT_ID=... Empty ships no third-party identity.
  static const String clientId = String.fromEnvironment('SIMKL_CLIENT_ID');

  /// Whether Simkl integration has been configured for this build.
  static bool get isConfigured => clientId.isNotEmpty;

  static const String apiBase = 'https://api.simkl.com';

  // OAuth (device-code / PIN) endpoints
  static const String pinUrl = '$apiBase/oauth/pin';

  /// Poll URL for a given user code. Append `/<userCode>?client_id=...`.
  static String pinPollUrl(String userCode) => '$apiBase/oauth/pin/$userCode';

  /// Web page the user visits to enter the code.
  static const String verificationUrl = 'https://simkl.com/pin';

  /// Headers on every Simkl request. `simkl-api-key` is required on all
  /// endpoints, authed or not.
  static Map<String, String> headers({String? accessToken}) => {
    'Content-Type': 'application/json',
    'Accept': 'application/json',
    'simkl-api-key': clientId,
    if (accessToken != null) 'Authorization': 'Bearer $accessToken',
  };
}
