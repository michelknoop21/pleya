import '../preferences/preference_sync_scope.dart';
import '../settings_service.dart';

/// Whether a profile's assistant memory is on. Local only: the key sits under
/// the profile's `user_<scope>_` prefix and is registered as profile runtime
/// cache, so it is never synced or exported. On by default, because nothing is
/// stored without an explicit request or a yes. Without a profile it reads off
/// and writes go nowhere.
class MemoryEnabledStore {
  MemoryEnabledStore(String profileId) : _prefix = PreferenceSyncScope.forProfile(profileId).localPrefix;

  static const _base = BoolPref('assistant_memory_enabled', defaultValue: true);

  final String _prefix;

  Future<bool> read() async {
    if (_prefix.isEmpty) return false;
    return (await SettingsService.getInstance()).read(_scoped);
  }

  Future<void> save(bool value) async {
    if (_prefix.isEmpty) return;
    await (await SettingsService.getInstance()).write(_scoped, value);
  }

  /// Drops the switch of [profileScope], from the profile delete flow.
  static Future<void> clearForProfileScope(String profileScope) async {
    final prefix = PreferenceSyncScope.forProfile(profileScope).localPrefix;
    if (prefix.isEmpty) return;
    await SettingsService.instance.prefs.remove('$prefix${_base.key}');
  }

  BoolPref get _scoped => BoolPref('$_prefix${_base.key}', defaultValue: _base.defaultValue);
}
