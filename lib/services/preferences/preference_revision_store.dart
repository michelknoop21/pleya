import 'dart:async';
import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'preference_revision.dart';

/// A stamp as stored locally or read from a record.
typedef PreferenceStamp = ({int at, String device, bool deleted});

/// This device's per-preference revision metadata, and the wire envelope that
/// carries a stamp. Knows nothing about transports or scopes.
class PreferenceRevisionStore {
  PreferenceRevisionStore(this._prefs, this._deviceId);

  final SharedPreferencesWithCache _prefs;
  final String _deviceId;

  /// Key holding this device's per-preference revision metadata. Registered as
  /// runtime cache, so it never syncs: it describes this device's edits.
  static const String storeKey = 'pleya_pref_revisions_v1';

  /// The revision a value carries when it was not written by a user but found
  /// already there: a v1 cloud value adopted at upgrade, or a local value that
  /// predates the revision store.
  ///
  /// Zero, not `now()`. A migrated value has no real change time, and stamping
  /// it with the moment the migration happened to run would make the last
  /// device to upgrade look like the most recent editor of every setting it
  /// touched. At zero, the first genuine change on any device wins.
  static const int legacyAt = 0;

  /// The device a stamp-less record is attributed to. Any real id compares
  /// above the empty string, which is exactly the tie we want unstamped local
  /// values to lose (see [remoteStampWins]).
  static const String noDevice = '';

  Map<String, dynamic> all() {
    final raw = _prefs.getString(storeKey);
    if (raw == null) return {};
    try {
      final decoded = json.decode(raw);
      return decoded is Map ? Map<String, dynamic>.from(decoded) : {};
    } catch (_) {
      return {};
    }
  }

  // Every method takes a stamp key: the base key for a global preference, the
  // full `user_<scope>_` key for a profile-scoped one (see
  // `PreferenceKeyMapper.stampKeyFor`). Callers decide what may be stamped.

  PreferenceStamp stampOf(String stampKey) {
    final entry = all()[stampKey];
    if (entry is Map && entry['t'] is int && entry['d'] is String) {
      return (at: entry['t'] as int, device: entry['d'] as String, deleted: entry['x'] == true);
    }
    return (at: legacyAt, device: noDevice, deleted: false);
  }

  /// Remember the stamp of a remote record this device just adopted, so the
  /// next comparison is against it and the next local change stamps past it.
  Future<void> adopt(String stampKey, PreferenceStamp stamp) async {
    final revisions = all();
    revisions[stampKey] = {'t': stamp.at, 'd': stamp.device, if (stamp.deleted) 'x': true};
    await _prefs.setString(storeKey, json.encode(revisions));
  }

  /// Stamp a change a user made on this device.
  void stampUserChange(String stampKey, {required bool removed}) {
    final revisions = all();
    revisions[stampKey] = {'t': _nextTimestamp(stampKey, revisions), 'd': _deviceId, if (removed) 'x': true};
    unawaited(_prefs.setString(storeKey, json.encode(revisions)));
  }

  /// A timestamp that never goes backwards on this device.
  ///
  /// Cross-device clock skew is a real limit of client-side last-writer-wins
  /// and this does not fix it. What it does fix is the local case: set the
  /// clock back an hour, change a setting, and without this the new value would
  /// carry a revision below its own predecessor, so the *older* value would win
  /// on the very device that just replaced it. One millisecond past the last
  /// revision is enough to keep the local sequence honest.
  int _nextTimestamp(String stampKey, Map<String, dynamic> revisions) {
    final now = DateTime.now().toUtc().millisecondsSinceEpoch;
    final previous = revisions[stampKey];
    final previousAt = previous is Map ? previous['t'] : null;
    if (previousAt is! int) return now;
    return now > previousAt ? now : previousAt + 1;
  }

  /// Record a revision for a value that was already present, without pretending
  /// the user just chose it. Idempotent: an existing revision is never
  /// downgraded to the legacy one.
  Future<void> bootstrapLegacy(String stampKey) async {
    final revisions = all();
    if (revisions.containsKey(stampKey)) return;
    revisions[stampKey] = {'t': legacyAt, 'd': _deviceId};
    await _prefs.setString(storeKey, json.encode(revisions));
  }

  /// Drop the stamp for [stampKey], so the key is "never seen" again.
  Future<void> forget(String stampKey) async {
    final revisions = all();
    if (revisions.remove(stampKey) == null) return;
    await _prefs.setString(storeKey, json.encode(revisions));
  }

  /// Forget every stamp.
  Future<void> clear() => _prefs.remove(storeKey);
}

/// Whether a remote record replaces what this device holds.
///
/// A local value without a stamp counts as [PreferenceRevisionStore.legacyAt]
/// on [PreferenceRevisionStore.noDevice], so it is older than any stamped
/// remote record. Unstamped means nobody wrote it through the coordinator's
/// `apply` with a user source: a value from before the revision store, a write
/// made before `ICloudSyncService.start` installed the hook (which happens
/// before the first frame), or a migration. Every write a user makes in this
/// session is stamped, including one during start-up and one inside a remote
/// batch, so this rule never overrules a choice made on this device.
///
/// Two unstamped sides (a record from the previous build against a local
/// value nobody stamped) cannot be ordered, and the store wins: that is what
/// enabling sync always did and what the cutover chose.
bool remoteStampWins(PreferenceStamp remote, PreferenceStamp local) {
  if (remote.at == PreferenceRevisionStore.legacyAt && local.at == PreferenceRevisionStore.legacyAt) return true;
  return PreferenceRevision.stampWins(
    at: remote.at,
    device: remote.device,
    deleted: remote.deleted,
    overAt: local.at,
    overDevice: local.device,
    overDeleted: local.deleted,
  );
}

bool sameStamp(PreferenceStamp a, PreferenceStamp b) => a.at == b.at && a.device == b.device && a.deleted == b.deleted;

String encodeStampedRecord(Map<String, dynamic> typed, PreferenceStamp stamp) =>
    json.encode({...typed, 't': stamp.at, 'd': stamp.device});

/// A removal on the wire: no `type`, so the released v2 build skips it.
String encodeTombstone(PreferenceStamp stamp) => json.encode({'x': true, 't': stamp.at, 'd': stamp.device});

/// A wire record, or null when [raw] is not one. `type` is empty for a
/// tombstone. A missing stamp is the previous build's record.
({String type, Object? value, PreferenceStamp stamp})? decodeStampedRecord(String raw) {
  try {
    final m = json.decode(raw);
    if (m is! Map) return null;
    final deleted = m['x'] == true;
    final type = m['type'];
    if (!deleted && type is! String) return null;
    final at = m['t'];
    final device = m['d'];
    return (
      type: type is String ? type : '',
      value: m['value'],
      stamp: (
        at: at is int ? at : PreferenceRevisionStore.legacyAt,
        device: device is String ? device : PreferenceRevisionStore.noDevice,
        deleted: deleted,
      ),
    );
  } catch (_) {
    return null;
  }
}
