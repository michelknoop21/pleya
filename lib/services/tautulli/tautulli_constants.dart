/// Shared constants for the Tautulli integration.
///
/// Tautulli is a Plex-only monitoring tool. Everything it exposes is admin
/// data: one key opens the whole API, including `sql`, `download_database` and
/// `delete_all_user_history`. There is no read-only variant and no per-user
/// scoping, so every Tautulli-backed surface in the app is gated on server
/// ownership and the credential never leaves the admin's device.
///
/// Contracts were measured against Tautulli v2.17.2; the sanitised captures and
/// what each measurement showed live in `test/fixtures/tautulli/`.
class TautulliConstants {
  TautulliConstants._();

  /// Pinned API path. v2 is the only version Tautulli has ever shipped.
  static const String apiPath = '/api/v2';

  static const Duration requestTimeout = Duration(seconds: 10);

  /// Activity is polled while a dashboard is open, so it needs a shorter leash
  /// than the statistics calls.
  static const Duration activityTimeout = Duration(seconds: 6);

  /// A device token generated in Tautulli is only valid for five minutes
  /// (`mobile_app.set_temp_device_token`), so pairing has to be prompt.
  static const Duration pairingWindow = Duration(minutes: 5);

  /// Normalize a user-entered Tautulli URL.
  ///
  /// Tautulli is commonly reverse-proxied onto a subdomain on 443 rather than
  /// sitting on its default 8181, and it supports a base path (`HTTP_ROOT`), so
  /// anything after the host is kept as-is. Only a pasted `/api/v2` suffix is
  /// stripped, because we append that ourselves.
  static String normalizeBaseUrl(String raw) {
    var url = raw.trim();
    if (url.isEmpty) return url;
    if (!url.contains('://')) {
      url = 'http://$url';
    }
    while (url.endsWith('/')) {
      url = url.substring(0, url.length - 1);
    }
    if (url.toLowerCase().endsWith(apiPath)) {
      url = url.substring(0, url.length - apiPath.length);
    }
    return url;
  }
}

/// How the app authenticates against Tautulli.
///
/// The `.name` is persisted; renaming needs a migration.
enum TautulliAuthMode {
  /// A per-device token obtained through `register_device`. Preferred: the
  /// admin's master API key never reaches the app, and the token can be revoked
  /// for one device from Tautulli's own settings.
  device,

  /// The permanent API key from Settings > Web Interface. Works everywhere but
  /// grants everything, so it is the fallback rather than the default.
  apiKey,
}
