import 'dart:math';

import '../services/base_shared_preferences_service.dart';
import '../services/preferences/preference_sync_scope.dart';
import '../services/settings_service.dart';

/// The ages of the children Big P picks for, per profile. Local only: the
/// key sits under the active profile's `user_<scope>_` prefix and is
/// registered as profile runtime cache, so it is never synced or exported.
/// Without an active profile reads are empty and writes go nowhere.
class KidsAgesStore {
  static const _base = StringListPref('assistant_kids_ages');

  List<int> _ages = const [];

  /// The youngest age from the last [read] or [save].
  int? get youngest => _ages.isEmpty ? null : _ages.reduce(min);

  Future<List<int>> read() async {
    final pref = await _scoped();
    final settings = await SettingsService.getInstance();
    return _ages = pref == null
        ? const []
        : [
            for (final s in settings.read(pref))
              if (int.tryParse(s) case final age? when age >= 0 && age < 18) age,
          ];
  }

  Future<void> save(List<int> ages) async {
    final pref = await _scoped();
    if (pref == null) return;
    _ages = [for (final a in ages) a.clamp(0, 17)];
    await (await SettingsService.getInstance()).write(pref, [for (final a in _ages) '$a']);
  }

  Future<void> clear() => save(const []);

  /// Drops the ages of [profileScope], from the profile delete flow.
  static Future<void> clearForProfileScope(String profileScope) async {
    final prefix = PreferenceSyncScope.forProfile(profileScope).localPrefix;
    if (prefix.isEmpty) return;
    await SettingsService.instance.prefs.remove('$prefix${_base.key}');
  }

  static Future<StringListPref?> _scoped() async {
    final settings = await SettingsService.getInstance();
    final prefix = PreferenceSyncScope.forProfile(
      settings.prefs.getString(PreferenceSyncScope.activeProfileIdKey),
    ).localPrefix;
    return prefix.isEmpty ? null : StringListPref('$prefix${_base.key}');
  }
}
