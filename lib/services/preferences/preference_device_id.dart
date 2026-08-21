import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

/// The identifier this installation signs its preference revisions with.
///
/// It exists to break ties in last-writer-wins, so it has to be stable across
/// launches and different from every other installation. Three things it is
/// deliberately not:
///
/// - **Not regenerated per launch.** A fresh id every start makes every tie
///   break arbitrarily and defeats the point.
/// - **Not the Plex client identifier.** That value is sent to plex.tv as
///   `X-Plex-Client-Identifier` and identifies the device to a third party.
///   Reusing it would copy an identifier with an external meaning into every
///   cloud record, for no benefit: any stable random string does the job.
/// - **Not synced.** It describes this device. It is registered as runtime
///   cache so the engine can never mirror it.
class PreferenceDeviceId {
  const PreferenceDeviceId._();

  static const String prefsKey = 'pleya_pref_device_id_v1';

  /// Read the stored id, generating and persisting one on first call.
  static Future<String> getOrCreate(SharedPreferencesWithCache prefs) async {
    final existing = prefs.getString(prefsKey);
    if (existing != null && existing.isNotEmpty) return existing;
    final generated = const Uuid().v4();
    await prefs.setString(prefsKey, generated);
    return generated;
  }
}
