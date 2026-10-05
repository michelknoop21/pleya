import '../profiles/profile.dart';
import '../services/preferences/preference_sync_scope.dart';
import '../services/settings_service.dart';

/// Whether this profile is a children's profile, as set in Instellingen >
/// Big P. Local only, like [KidsAgesStore]: the key sits under the active
/// profile's `user_<scope>_` prefix and is registered as profile runtime
/// cache, so it is never synced or exported. Without an active profile reads
/// are false and writes go nowhere.
class KidsProfileStore {
  static const _base = BoolPref('assistant_kids_profile');

  Future<bool> read() async {
    final pref = await _scoped();
    return pref != null && (await SettingsService.getInstance()).read(pref);
  }

  Future<void> save(bool value) async {
    final pref = await _scoped();
    if (pref != null) await (await SettingsService.getInstance()).write(pref, value);
  }

  /// Drops the switch of [profileScope], from the profile delete flow.
  static Future<void> clearForProfileScope(String profileScope) async {
    final prefix = PreferenceSyncScope.forProfile(profileScope).localPrefix;
    if (prefix.isEmpty) return;
    await SettingsService.instance.prefs.remove('$prefix${_base.key}');
  }

  static Future<BoolPref?> _scoped() async {
    final settings = await SettingsService.getInstance();
    final prefix = PreferenceSyncScope.forProfile(
      settings.prefs.getString(PreferenceSyncScope.activeProfileIdKey),
    ).localPrefix;
    return prefix.isEmpty ? null : BoolPref('$prefix${_base.key}');
  }
}

/// The one answer to "is this a children's profile": a Plex Home account
/// Plex marks as restricted always is; any other profile when its switch in
/// Instellingen is on. Big P's age filter follows this and nothing else.
Future<bool> assistantIsKidsProfile(Profile? profile, {KidsProfileStore? store}) async =>
    (profile?.plexRestricted ?? false) || await (store ?? KidsProfileStore()).read();
