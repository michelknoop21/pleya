import 'dart:convert';

import '../credential_vault.dart';
import 'tautulli_constants.dart';

/// Immutable Tautulli connection state for one Plex profile.
///
/// [token] is AES-GCM protected through [CredentialVault] before it is
/// persisted, so encode and decode are async. It is the only secret here, and
/// it is deliberately the only thing worth stealing: whether it is a device
/// token or the master API key, it opens the whole Tautulli API.
class TautulliSession {
  final String baseUrl;
  final TautulliAuthMode authMode;

  /// Device token or master API key, depending on [authMode].
  final String token;

  /// The device id we registered under, so the app can re-register or point the
  /// user at the right entry in Tautulli's device list. Null in apiKey mode.
  final String? deviceId;

  /// Friendly server name from `get_server_friendly_name`, shown in settings so
  /// the user can tell two configured servers apart.
  final String? serverName;

  /// `pms_identifier`: the machine identifier of the Plex server this instance
  /// monitors. Not cosmetic. It is the same string a client is registered
  /// under, and rating keys are per-server, so it is what binds a reported
  /// session to the server that can resolve it. Null for a session paired
  /// before it was recorded.
  final String? machineIdentifier;

  /// Tautulli version at the time of pairing, for support and for gating
  /// anything that needs a newer build.
  final String? version;

  const TautulliSession({
    required this.baseUrl,
    required this.authMode,
    required this.token,
    this.deviceId,
    this.serverName,
    this.machineIdentifier,
    this.version,
  });

  bool get isDeviceToken => authMode == TautulliAuthMode.device;

  TautulliSession copyWith({
    String? baseUrl,
    TautulliAuthMode? authMode,
    String? token,
    String? deviceId,
    String? serverName,
    String? machineIdentifier,
    String? version,
  }) {
    return TautulliSession(
      baseUrl: baseUrl ?? this.baseUrl,
      authMode: authMode ?? this.authMode,
      token: token ?? this.token,
      deviceId: deviceId ?? this.deviceId,
      serverName: serverName ?? this.serverName,
      machineIdentifier: machineIdentifier ?? this.machineIdentifier,
      version: version ?? this.version,
    );
  }

  Future<String> encode() async {
    return json.encode(<String, dynamic>{
      'base_url': baseUrl,
      'auth_mode': authMode.name,
      'token': await CredentialVault.protect(token),
      'device_id': deviceId,
      'server_name': serverName,
      'machine_identifier': machineIdentifier,
      'version': version,
    });
  }

  /// Throws on a malformed payload or an unrecognised mode. The store turns
  /// that into "not configured" rather than keeping a session that can only
  /// ever fail, the same way [SeerrSession] does.
  static Future<TautulliSession> decode(String raw) async {
    final map = json.decode(raw) as Map<String, dynamic>;
    final protectedToken = map['token'];
    if (protectedToken is! String || protectedToken.isEmpty) {
      throw const FormatException('Tautulli session has no token');
    }
    return TautulliSession(
      baseUrl: map['base_url'] as String,
      authMode: TautulliAuthMode.values.firstWhere((m) => m.name == map['auth_mode']),
      token: await CredentialVault.reveal(protectedToken),
      deviceId: map['device_id'] as String?,
      serverName: map['server_name'] as String?,
      machineIdentifier: map['machine_identifier'] as String?,
      version: map['version'] as String?,
    );
  }

  /// Never let the token reach a log line.
  @override
  String toString() => 'TautulliSession($baseUrl, ${authMode.name}, server: $serverName)';
}
