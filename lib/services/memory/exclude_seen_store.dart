import '../preferences/preference_sync_scope.dart';
import '../settings_service.dart';
import 'memory_validation.dart';

/// Whether Big P leaves out every title this profile watched or started, as a
/// standing preference (BP-11d). Local only, like [MemoryEnabledStore]: the key
/// sits under the profile's `user_<scope>_` prefix and is registered as
/// profile runtime cache, so it is never synced or exported. Off by default.
///
/// The memory shows the preference as one fact with [sentenceFor]'s fixed
/// wording, so it can be seen and removed where every other fact is; removing
/// that fact turns this off ([isSentence], read by `MemoryService`).
class ExcludeSeenStore {
  ExcludeSeenStore(String profileId) : _prefix = PreferenceSyncScope.forProfile(profileId).localPrefix;

  static const _base = BoolPref('assistant_exclude_seen');

  static const _nl = 'Nooit titels voorstellen die je al gezien of begonnen hebt';
  static const _en = 'Never suggest titles you already watched or started';

  final String _prefix;

  Future<bool> read() async {
    if (_prefix.isEmpty) return false;
    return (await SettingsService.getInstance()).read(_scoped);
  }

  Future<void> save(bool value) async {
    if (_prefix.isEmpty) return;
    await (await SettingsService.getInstance()).write(_scoped, value);
  }

  /// Turns the preference off when its fact goes. Through the settings the
  /// app bootstrapped at start: without them (a widget test that never set
  /// them up) nothing was saved this run, so there is nothing to clear.
  Future<void> clear() async {
    final settings = SettingsService.instanceOrNull;
    if (_prefix.isEmpty || settings == null) return;
    await settings.write(_scoped, false);
  }

  /// The memory fact for the preference, in Dutch or English.
  static String sentenceFor({required bool dutch}) => dutch ? _nl : _en;

  /// Whether [value] is the preference's own fact, in either language.
  static bool isSentence(String value) {
    final key = memoryValueKey(value);
    return key == memoryValueKey(_nl) || key == memoryValueKey(_en);
  }

  /// Drops the preference of [profileScope], from the profile delete flow.
  static Future<void> clearForProfileScope(String profileScope) async {
    final prefix = PreferenceSyncScope.forProfile(profileScope).localPrefix;
    if (prefix.isEmpty) return;
    await SettingsService.instance.prefs.remove('$prefix${_base.key}');
  }

  BoolPref get _scoped => BoolPref('$_prefix${_base.key}', defaultValue: _base.defaultValue);
}
