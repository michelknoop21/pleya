import 'dart:convert';

import '../credential_vault.dart';
import 'seerr_constants.dart';

/// Immutable seerr connection state for one Plex profile.
///
/// Secrets ([apiKey], [cookie], [password]) are AES-GCM protected via
/// [CredentialVault] before persistence (`enc:v1:` prefix), so encode/decode
/// are async. The cached user + permissions let the UI gate request/admin
/// actions without an extra round-trip on every screen.
class SeerrSession {
  final String baseUrl;
  final SeerrAuthMode authMode;

  /// Admin API key (apiKey mode only).
  final String? apiKey;

  /// Captured `connect.sid` cookie header value (plex/local modes).
  final String? cookie;

  /// Local-login credentials, kept for silent re-auth on cookie expiry.
  final String? email;
  final String? password;

  final int? userId;
  final String? displayName;
  final int permissions;

  const SeerrSession({
    required this.baseUrl,
    required this.authMode,
    this.apiKey,
    this.cookie,
    this.email,
    this.password,
    this.userId,
    this.displayName,
    this.permissions = 0,
  });

  bool get isApiKeyMode => authMode == SeerrAuthMode.apiKey;

  SeerrSession copyWith({
    String? baseUrl,
    SeerrAuthMode? authMode,
    String? apiKey,
    String? cookie,
    String? email,
    String? password,
    int? userId,
    String? displayName,
    int? permissions,
  }) {
    return SeerrSession(
      baseUrl: baseUrl ?? this.baseUrl,
      authMode: authMode ?? this.authMode,
      apiKey: apiKey ?? this.apiKey,
      cookie: cookie ?? this.cookie,
      email: email ?? this.email,
      password: password ?? this.password,
      userId: userId ?? this.userId,
      displayName: displayName ?? this.displayName,
      permissions: permissions ?? this.permissions,
    );
  }

  /// Encode to a persistable JSON string, protecting the secrets.
  Future<String> encode() async {
    final map = <String, dynamic>{
      'base_url': baseUrl,
      'auth_mode': authMode.name,
      'api_key': apiKey == null ? null : await CredentialVault.protect(apiKey!),
      'cookie': cookie == null ? null : await CredentialVault.protect(cookie!),
      'email': email,
      'password': password == null ? null : await CredentialVault.protect(password!),
      'user_id': userId,
      'display_name': displayName,
      'permissions': permissions,
    };
    return json.encode(map);
  }

  static Future<SeerrSession> decode(String raw) async {
    final map = json.decode(raw) as Map<String, dynamic>;
    Future<String?> revealed(Object? v) async => v is String && v.isNotEmpty ? await CredentialVault.reveal(v) : null;

    return SeerrSession(
      baseUrl: map['base_url'] as String,
      // Throw on an unrecognized mode rather than silently coercing to apiKey:
      // a plex/local session mis-tagged as apiKey has no key, so every call
      // 401s with no re-auth. The store's load() catch turns this into a clean
      // reconfigure instead of a permanently-dead session.
      authMode: SeerrAuthMode.values.firstWhere((m) => m.name == map['auth_mode']),
      apiKey: await revealed(map['api_key']),
      cookie: await revealed(map['cookie']),
      email: map['email'] as String?,
      password: await revealed(map['password']),
      userId: (map['user_id'] as num?)?.toInt(),
      displayName: map['display_name'] as String?,
      permissions: (map['permissions'] as num?)?.toInt() ?? 0,
    );
  }
}
