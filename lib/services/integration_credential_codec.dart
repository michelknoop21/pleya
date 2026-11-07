import 'dart:convert';

import 'credential_vault.dart';
import 'preferences/preference_sync_scope.dart';
import 'seerr/seerr_session.dart';
import 'tautulli/tautulli_integration_store.dart';
import 'tautulli/tautulli_server_integration.dart';

/// The only credentials allowed into the private, encrypted CloudKit field.
/// These payloads must never pass through settings export or KVS.
class IntegrationCredentialCodec {
  static bool isSupportedKey(String key) {
    if (key.startsWith(TautulliIntegrationStore.keyPrefix)) {
      return key.length > TautulliIntegrationStore.keyPrefix.length && key.length <= 512;
    }
    const suffix = '_seerr_session';
    return key.length > 5 + suffix.length &&
        key.startsWith('user_') &&
        key.endsWith(suffix) &&
        PreferenceSyncScope.isPortableProfileScope(key.substring(5, key.length - suffix.length));
  }

  static const _seerrFields = {
    'base_url',
    'auth_mode',
    'api_key',
    'cookie',
    'email',
    'password',
    'user_id',
    'display_name',
    'permissions',
  };
  static const _tautulliFields = {
    'machine_identifier',
    'base_url',
    'auth_mode',
    'token',
    'device_id',
    'server_name',
    'version',
    'connection_state',
    'use_history_for_recommendations',
    'configured_by_profile_id',
    'configured_at_ms',
    'policy_changed_at_ms',
    'has_unresolved_conflict',
  };

  static Future<Map<String, dynamic>> toCloud(String key, String encrypted) async {
    if (!isSupportedKey(key)) throw const FormatException('Unsupported integration');
    final map = Map<String, dynamic>.from(jsonDecode(encrypted) as Map);
    final tautulli = key.startsWith(TautulliIntegrationStore.keyPrefix);
    final fields = tautulli ? _tautulliFields : _seerrFields;
    final clear = {
      for (final field in fields)
        if (map.containsKey(field)) field: map[field],
    };
    for (final field in tautulli ? ['token'] : ['api_key', 'cookie', 'password']) {
      final value = clear[field];
      if (value is String && value.isNotEmpty) clear[field] = await CredentialVault.reveal(value);
    }
    // Validate outgoing data too. An unreadable local credential is not a
    // disconnect and must never erase a working cloud copy.
    await fromCloud(key, clear);
    return clear;
  }

  static Future<String> fromCloud(String key, Map<String, dynamic> clear) async {
    if (!isSupportedKey(key)) throw const FormatException('Unsupported integration');
    final url = Uri.tryParse(clear['base_url'] is String ? clear['base_url'] as String : '');
    if (url == null || !['http', 'https'].contains(url.scheme) || url.host.isEmpty || url.userInfo.isNotEmpty) {
      throw const FormatException('Invalid integration address');
    }
    if (key.startsWith(TautulliIntegrationStore.keyPrefix)) {
      final integration = await TautulliServerIntegration.decode(jsonEncode(clear));
      if (TautulliIntegrationStore.keyFor(integration.machineIdentifier) != key) {
        throw const FormatException('Integration server mismatch');
      }
      if (integration.isConnected && !integration.hasCredential) {
        throw const FormatException('Missing integration credential');
      }
      return integration.encode();
    }
    final session = await SeerrSession.decode(jsonEncode(clear));
    if (session.isApiKeyMode && (session.apiKey == null || session.apiKey!.isEmpty)) {
      throw const FormatException('Missing integration credential');
    }
    return session.encode();
  }
}
