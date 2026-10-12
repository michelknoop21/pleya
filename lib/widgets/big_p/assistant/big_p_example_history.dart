import 'dart:async';

import '../../../assistant/assistant_capabilities.dart';
import '../../../services/preferences/preference_sync_scope.dart';
import '../../../services/settings_service.dart';
import '../../../utils/app_logger.dart';

/// One start question as it was shown: the capability and which of its
/// phrasings. Stored by name and index, so a change of language keeps the
/// history.
typedef BigPShownExample = ({AssistantCapability capability, int phrasing});

/// The start questions the greeting showed last, newest last: eight summons
/// of three. The picker reads it so a capability shown long ago, or never,
/// comes up before one shown just now.
///
/// In memory by default. [BigPExampleHistory.stored] keeps it per profile,
/// local only like `KidsAgesStore`: the key sits under the active profile's
/// `user_<scope>_` prefix and is registered as profile runtime cache, so it
/// is never synced or exported.
class BigPExampleHistory {
  BigPExampleHistory() : _stored = false;
  BigPExampleHistory.stored() : _stored = true;

  static const limit = 24;
  static const _base = StringListPref('assistant_example_history');

  final bool _stored;
  final List<BigPShownExample> _shown = [];
  Future<StringListPref?>? _pref;
  Future<void>? _loading;

  List<BigPShownExample> get shown => List.unmodifiable(_shown);

  /// How many summons ago [capability] was last shown (0 is the last one), or
  /// null when it is not in the history.
  int? summonsSince(AssistantCapability capability) {
    final at = _shown.lastIndexWhere((e) => e.capability == capability);
    return at < 0 ? null : (_shown.length - 1 - at) ~/ 3;
  }

  bool showed(AssistantCapability capability, int phrasing) =>
      _shown.any((e) => e.capability == capability && e.phrasing == phrasing);

  /// Reads the stored history of the active profile, once. What was shown
  /// before the read finished stays the newest.
  Future<void> load() => _loading ??= _stored ? _read() : Future.value();

  Future<void> _read() async {
    final pref = _pref = _scoped();
    try {
      final key = await pref;
      if (key == null) return;
      final earlier = [
        for (final s in (await SettingsService.getInstance()).read(key))
          if (_parse(s) case final e?) e,
      ];
      _shown.insertAll(0, earlier);
      _trim();
    } catch (e) {
      appLogger.d('Big P example history read failed', error: e.runtimeType);
    }
  }

  /// The greeting showed [examples].
  void note(Iterable<BigPShownExample> examples) {
    _shown.addAll(examples);
    _trim();
    if (_stored) unawaited(_save());
  }

  Future<void> _save() async {
    try {
      await load();
      // The profile the history was read for, also after a profile switch.
      final key = await _pref;
      if (key == null) return;
      await (await SettingsService.getInstance()).write(key, [
        for (final e in _shown) '${e.capability.name}#${e.phrasing}',
      ]);
    } catch (e) {
      appLogger.d('Big P example history write failed', error: e.runtimeType);
    }
  }

  void _trim() {
    if (_shown.length > limit) _shown.removeRange(0, _shown.length - limit);
  }

  static BigPShownExample? _parse(String stored) {
    final parts = stored.split('#');
    if (parts.length != 2) return null;
    final capability = AssistantCapability.values.asNameMap()[parts[0]];
    final phrasing = int.tryParse(parts[1]);
    return capability == null || phrasing == null || phrasing < 0 ? null : (capability: capability, phrasing: phrasing);
  }

  /// Drops the history of [profileScope], from the profile delete flow.
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
