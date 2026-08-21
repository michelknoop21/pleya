import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// v1 cloud keys whose owner can no longer be established.
///
/// The v1 format stripped the profile prefix before a value left the device, so
/// one cloud slot per base key was shared by every profile and the last writer
/// won. Reading `hidden_libraries` out of a v1 store therefore says nothing
/// about which profile put it there.
///
/// The tempting move at upgrade is to hand it to whichever profile happens to
/// be active. That does not resolve the collision, it makes it permanent and
/// silent: profile B inherits profile A's hidden libraries and nobody ever
/// finds out why. "Active during the upgrade" is not evidence of ownership.
///
/// So these records are quarantined. They are recorded, not applied, not
/// adopted, and not deleted.
///
/// **Removal condition.** A quarantine entry goes when either holds:
///
/// 1. the same base key has been written under a v2 profile namespace by any
///    device on the account, so the profile has stated its own value and the
///    v1 record can no longer teach anyone anything; or
/// 2. the account has no client left that writes the v1 format, at which point
///    the v1 keys are dropped wholesale by the format retirement, not by this
///    class.
///
/// Neither is a timer. An entry that is still here is still ambiguous, and the
/// record says so rather than leaving mystery state in the store.
class PreferenceQuarantine {
  const PreferenceQuarantine._();

  static const String prefsKey = 'pleya_pref_quarantine_v1';

  static Map<String, dynamic> _read(SharedPreferencesWithCache prefs) {
    final raw = prefs.getString(prefsKey);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  /// Record that [baseKey] exists in the v1 store with no provable owner.
  /// Idempotent: re-recording keeps the first sighting.
  static Future<void> quarantine(
    SharedPreferencesWithCache prefs,
    String baseKey, {
    required String reason,
    required int seenAt,
  }) async {
    final entries = _read(prefs);
    if (entries.containsKey(baseKey)) return;
    entries[baseKey] = {'reason': reason, 'seenAt': seenAt};
    await prefs.setString(prefsKey, json.encode(entries));
  }

  static bool isQuarantined(SharedPreferencesWithCache prefs, String baseKey) => _read(prefs).containsKey(baseKey);

  static Set<String> keys(SharedPreferencesWithCache prefs) => _read(prefs).keys.toSet();

  /// Release [baseKey] once condition 1 above is met: the profile has stated
  /// its own value under the v2 namespace.
  static Future<void> release(SharedPreferencesWithCache prefs, String baseKey) async {
    final entries = _read(prefs);
    if (entries.remove(baseKey) == null) return;
    await prefs.setString(prefsKey, json.encode(entries));
  }
}
