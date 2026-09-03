import '../utils/app_logger.dart';
import 'base_shared_preferences_service.dart';
import 'pleya_share/pleya_share_device_name.dart';
import 'preferences/preference_device_id.dart';

/// What this installation calls itself when it opens a session on a Pleya
/// Server.
///
/// A session on that server is one device, not one user (DEC-069): revoking
/// the session on a lost phone must not log the household's television out.
/// That only works if the server can tell two devices apart, and the only
/// honest source for that is the client — an IP address or a User-Agent
/// identifies a network path and a build, not a device.
///
/// The id is [PreferenceDeviceId], reused rather than invented. It is already
/// stable across launches, already different per installation, already not the
/// Plex client identifier (which is sent to plex.tv and identifies the device
/// to a third party), and already excluded from preference sync. A second
/// identifier with the same properties would only be a second thing to keep in
/// step.
///
/// The name is the one Pleya Share shows during pairing, for the same reason:
/// a person picking their old phone out of a session list recognises it by the
/// name their phone already has.
typedef PleyaServerDeviceIdentity = ({String id, String name});

/// Resolve this device's identity, or null when it cannot be read.
///
/// Null is a normal answer and not a failure to handle upstream: the device
/// fields are optional on the wire, and a server that receives neither creates
/// a session with `device_id` null and a fixed placeholder name. That is the
/// same session an older client gets, so losing the identity costs the ability
/// to tell two devices apart, not the ability to log in.
Future<PleyaServerDeviceIdentity?> pleyaServerDeviceIdentity() async {
  try {
    final prefs = await BaseSharedPreferencesService.sharedCache();
    final id = await PreferenceDeviceId.getOrCreate(prefs);
    if (id.isEmpty) return null;
    return (id: id, name: await pleyaShareDeviceName());
  } catch (e) {
    appLogger.d('PleyaServer: device identity lookup failed', error: e);
    return null;
  }
}
