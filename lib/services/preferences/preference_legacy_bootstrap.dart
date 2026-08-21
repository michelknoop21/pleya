import 'package:shared_preferences/shared_preferences.dart';

/// The one-time import of v1 cloud state into v2, and the marker that stops it
/// happening twice.
///
/// The cutover is deliberately sharp. v1 has no shared revision, no tombstones
/// and no profile namespace, so a client that kept writing both formats could
/// not tell a newer user action in v1 from an older snapshot of it. That is the
/// ambiguity the envelope exists to remove, and dual-write would rebuild it in
/// a more complicated shape.
///
/// So v1 becomes read-only legacy state:
///
/// - unambiguously **global** v1 values are imported once, carrying
///   `legacyRevisionAt`, so the first genuine change on any device beats them;
/// - **profile-scoped** v1 values are not imported at all. The format stripped
///   the profile before the value left the device, so nobody can say whose they
///   are; they stay quarantined;
/// - after that, nothing writes v1 again, and nothing merges an incoming v1
///   change into v2 state;
/// - the frozen v1 records are left in the store. Deleting them would take a
///   working setting away from a device still running the older build, and the
///   compatibility window is not this release's to close.
class PreferenceLegacyBootstrap {
  const PreferenceLegacyBootstrap._();

  /// Set once the v1 import has run to completion. Lives in the local prefs,
  /// so a reinstall re-imports and a restart does not.
  static const String completedKey = 'pleya_pref_v1_bootstrap_done';

  static bool hasRun(SharedPreferencesWithCache prefs) => prefs.getBool(completedKey) ?? false;

  static Future<void> markComplete(SharedPreferencesWithCache prefs) => prefs.setBool(completedKey, true);

  /// Clear the marker so the import runs again. Used by tests, and the
  /// documented manual recovery if an upgrade is ever found to have imported
  /// nothing.
  static Future<void> reset(SharedPreferencesWithCache prefs) => prefs.remove(completedKey);
}
