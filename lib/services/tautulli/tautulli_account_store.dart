import '../base_shared_preferences_service.dart';
import 'tautulli_session.dart';

/// Per-Plex-profile persistence for the Tautulli session, keyed by
/// `user_{uuid}_tautulli_session`. Mirrors [SeerrAccountStore]; the payload is a
/// vault-protected [TautulliSession] JSON blob.
///
/// `tautulli_session` is denylisted in `SettingsExportService`, so the token
/// never travels through a settings export or iCloud sync. That is not only a
/// privacy call: the vault key is device-local, so a copied blob would be
/// undecryptable on the other device anyway.
class TautulliAccountStore {
  TautulliAccountStore._();
  static final TautulliAccountStore instance = TautulliAccountStore._();

  static const String baseKey = 'tautulli_session';

  String _scopedKey(String userUuid) => userUuid.isEmpty ? baseKey : 'user_${userUuid}_$baseKey';

  Future<TautulliSession?> load(String userUuid) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final raw = prefs.getString(_scopedKey(userUuid));
    if (raw == null) return null;
    try {
      return await TautulliSession.decode(raw);
    } catch (_) {
      // A blob we cannot read is worse than none: every call would fail with no
      // way back. Report "not configured" so the UI offers pairing again.
      return null;
    }
  }

  Future<void> save(String userUuid, TautulliSession session) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_scopedKey(userUuid), await session.encode());
  }

  Future<void> clear(String userUuid) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_scopedKey(userUuid));
  }
}
