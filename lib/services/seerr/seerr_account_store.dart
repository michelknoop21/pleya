import '../base_shared_preferences_service.dart';
import '../integration_credential_changes.dart';
import 'seerr_session.dart';

/// Per-Plex-profile persistence for the seerr session, keyed by
/// `user_{uuid}_seerr_session`. Mirrors `TrackerAccountStore`; the payload is a
/// vault-protected [SeerrSession] JSON blob. Empty uuid falls back to a single
/// global slot (before a profile is selected).
class SeerrAccountStore {
  SeerrAccountStore._();
  static final SeerrAccountStore instance = SeerrAccountStore._();

  static const String _baseKey = 'seerr_session';

  String _scopedKey(String userUuid) => userUuid.isEmpty ? _baseKey : 'user_${userUuid}_$_baseKey';

  Future<SeerrSession?> load(String userUuid) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(_scopedKey(userUuid));
    if (raw == null) return null;
    try {
      return await SeerrSession.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> save(String userUuid, SeerrSession session, {bool refresh = false}) async {
    final key = _scopedKey(userUuid);
    if (refresh) {
      final prefs = await BaseSharedPreferencesService.sharedCache();
      final expected = prefs.getString(key);
      if (expected == null) return; // A refresh never creates a disconnected binding.
      final SeerrSession current;
      try {
        current = await SeerrSession.decode(expected);
      } catch (_) {
        return; // A background refresh cannot repair an unreadable binding.
      }
      if (current.baseUrl != session.baseUrl ||
          current.authMode != session.authMode ||
          current.apiKey != session.apiKey ||
          current.email != session.email ||
          current.password != session.password)
        return;
      await IntegrationCredentialChanges.write(
        key,
        await session.encode(),
        source: IntegrationCredentialChangeSource.refresh,
        expected: {key: expected},
      );
    } else {
      await IntegrationCredentialChanges.write(key, await session.encode());
    }
  }

  Future<void> clear(String userUuid) async {
    await IntegrationCredentialChanges.write(_scopedKey(userUuid), null);
  }
}
