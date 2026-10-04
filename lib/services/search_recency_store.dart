import 'dart:async';

import 'preferences/preference_sync_scope.dart';
import 'settings_service.dart';

/// Search queries and opened titles, per profile (Z8: a child profile must not
/// see what the parent searched for or opened).
///
/// Both lists live under the active profile's `user_<scope>_` prefix, the same
/// local prefix `StorageService` and the sync coordinator use. The device-wide
/// keys from before the split ([SettingsService.searchHistory] and
/// [SettingsService.searchRecentItems]) are dropped, not migrated: nobody can
/// tell whose searches they were, so every profile starts empty. Without an
/// active profile there is no owner, so reads are empty and writes go nowhere.
class SearchRecencyStore {
  const SearchRecencyStore._();

  static List<String> readHistory() => _read(SettingsService.searchHistory);

  static Future<void> writeHistory(List<String> queries) => _write(SettingsService.searchHistory, queries);

  static List<String> readRecentItems() => _read(SettingsService.searchRecentItems);

  static Future<void> writeRecentItems(List<String> entries) => _write(SettingsService.searchRecentItems, entries);

  /// Drops the search queries and opened titles of [profileScope], from the
  /// profile delete flow.
  static Future<void> clearForProfileScope(String profileScope) async {
    final prefix = PreferenceSyncScope.forProfile(profileScope).localPrefix;
    if (prefix.isEmpty) return;
    final prefs = SettingsService.instance.prefs;
    await prefs.remove('$prefix${SettingsService.searchHistory.key}');
    await prefs.remove('$prefix${SettingsService.searchRecentItems.key}');
  }

  static List<String> _read(StringListPref devicePref) {
    final scoped = _scoped(devicePref);
    return scoped == null ? const <String>[] : SettingsService.instance.read(scoped);
  }

  static Future<void> _write(StringListPref devicePref, List<String> value) async {
    final scoped = _scoped(devicePref);
    if (scoped == null) return;
    await SettingsService.instance.write(scoped, value);
  }

  /// [devicePref] under the active profile's prefix, or null without one.
  static StringListPref? _scoped(StringListPref devicePref) {
    final settings = SettingsService.instance;
    if (settings.prefs.containsKey(devicePref.key)) unawaited(settings.prefs.remove(devicePref.key));
    final prefix = PreferenceSyncScope.forProfile(
      settings.prefs.getString(PreferenceSyncScope.activeProfileIdKey),
    ).localPrefix;
    if (prefix.isEmpty) return null;
    return StringListPref('$prefix${devicePref.key}');
  }
}
