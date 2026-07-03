import '../base_shared_preferences_service.dart';
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

  Future<void> save(String userUuid, SeerrSession session) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.setString(_scopedKey(userUuid), await session.encode());
  }

  Future<void> clear(String userUuid) async {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    await prefs.remove(_scopedKey(userUuid));
  }
}
