import 'dart:convert';

import 'preference_sync_policy.dart';
import 'preference_sync_scope.dart';
import 'preference_value_portability.dart';

/// Combine two versions of one preference value.
///
/// Both sides may be null: null on the left means this device has nothing,
/// null on the right means the store has nothing. Returning null means "no
/// value" — for an inbound merge that is a removal, for an outbound one it is
/// "send nothing".
typedef PreferenceValueMerge = Object? Function(Object? local, Object? remote);

/// One family's merge behaviour, registered by name.
///
/// The engine never learns what the values mean. It knows a family has a merge,
/// looks it up by the name in the policy, and calls it. That is the whole
/// contract, and it is what phase B needs for track choices: a family whose
/// value is a map of independently edited entries cannot be settled by
/// last-writer-wins without losing the entries the other device edited.
class PreferenceMergeFamily {
  const PreferenceMergeFamily({required this.name, required this.inbound, this.outbound, this.removed});

  final String name;

  /// A remote value arrived. Returns what this device should store.
  final PreferenceValueMerge inbound;

  /// A local value is about to leave. Returns what should be written to the
  /// store, given what is in it now.
  ///
  /// Null when the family does not need it, which is the common case: the value
  /// travels as-is. The asymmetry is deliberate and was the gap in v1 — the
  /// merge only ever ran inbound, so an outgoing write pushed the raw local
  /// value over entries another device owned.
  final PreferenceValueMerge? outbound;

  /// A newer tombstone arrived. Returns what this device keeps of [local], or
  /// null to remove the value. Null when the family has nothing to keep, which
  /// makes the tombstone a plain removal.
  final Object? Function(Object? local)? removed;

  bool get mergesOutgoing => outbound != null;
}

/// The families the coordinator knows about.
///
/// Instance state, not a static table: the built-in families need to know which
/// server ids identify the same server everywhere, and that answer arrives from
/// the connection registry long after the engine starts.
class PreferenceMergeRegistry {
  PreferenceMergeRegistry();

  final Map<String, PreferenceMergeFamily> _families = {};

  void register(PreferenceMergeFamily family) => _families[family.name] = family;

  Iterable<String> get registeredNames => _families.keys;

  /// The family for [baseKey], or null when the value is settled by the
  /// revision envelope instead.
  PreferenceMergeFamily? familyFor(String baseKey) {
    final policy = PreferenceSyncPolicyRegistry.policyFor(baseKey);
    if (policy.merge != PreferenceMergeStrategy.custom) return null;
    final name = policy.mergeFamily;
    if (name == null) return null;
    return _families[name];
  }
}

/// Lists of `serverId:libraryId` entries, where each device can only speak for
/// the servers it knows.
///
/// Inbound keeps what the sender never saw: their list lacks this device's
/// local-folder libraries, and treating that absence as a removal would wipe
/// them on every remote change.
///
/// Outbound keeps the entries in the store that belong to servers this device
/// cannot speak for, and lets the local list decide everything else. That
/// asymmetry is the point: unhiding a library on a shared server must still
/// reach the other devices, so a plain union would be wrong.
PreferenceMergeFamily buildServerScopedListFamily(IsServerIdPortable isServerIdPortable) => PreferenceMergeFamily(
  name: PreferenceMergeFamilies.serverScopedList,
  inbound: (local, remote) {
    final remoteEntries = decodeStringList(remote);
    if (remoteEntries == null) return local;
    final localEntries = decodeStringList(local) ?? const <String>[];
    return json.encode(
      PreferenceValuePortability.mergeKeepingLocalOnly(remoteEntries, localEntries, isServerIdPortable),
    );
  },
  outbound: (local, remote) {
    final localEntries = decodeStringList(local);
    if (localEntries == null) return local;
    final mine = PreferenceValuePortability.portableEntries(localEntries, isServerIdPortable);
    // Every entry belongs to a backend nobody else can read. Nothing to send,
    // and nothing to delete either: whatever is in the store belongs to the
    // other devices.
    if (mine.isEmpty) return null;
    final remoteEntries = decodeStringList(remote) ?? const <String>[];
    final foreign = PreferenceValuePortability.localOnlyEntries(remoteEntries, isServerIdPortable);
    final seen = mine.toSet();
    return json.encode(<String>[...mine, ...foreign.where(seen.add)]);
  },
  // The sender removed the list it could see. This device's local-folder
  // entries were never in it, so they stay.
  removed: (local) {
    final keep = PreferenceValuePortability.localOnlyEntries(decodeStringList(local) ?? const [], isServerIdPortable);
    return keep.isEmpty ? null : json.encode(keep);
  },
);

/// Maps keyed by profile scope, where a device speaks for the profiles it has.
///
/// Inbound keeps this device's non-portable entries and the entries of scopes
/// the sender does not know; for a scope both know, the sender's set replaces
/// this device's, so a removed series override travels. Outbound sends the
/// portable entries and carries the store's entries for scopes this device
/// lacks. An entry present on both sides is settled by its timestamp when both
/// carry one, otherwise the side doing the merge keeps its own.
///
/// Known limit (DEC-131): a device that removes the last entry of a scope no
/// longer "knows" that scope, so that final removal does not travel.
PreferenceMergeFamily buildProfileKeyedMapFamily() => PreferenceMergeFamily(
  name: PreferenceMergeFamilies.profileKeyedMap,
  inbound: (local, remote) {
    final theirs = decodeStringMap(remote);
    if (theirs == null) return local;
    final mine = decodeStringMap(local) ?? const <String, dynamic>{};
    final theirScopes = theirs.keys.map(profileScopeOfMapKey).toSet();
    final merged = <String, dynamic>{
      for (final e in mine.entries)
        if (!PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)) ||
            !theirScopes.contains(profileScopeOfMapKey(e.key)))
          e.key: e.value,
      for (final e in theirs.entries)
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)))
          e.key: _newerEntry(e.value, mine[e.key]),
    };
    return json.encode(merged);
  },
  outbound: (local, remote) {
    final mine = decodeStringMap(local);
    if (mine == null) return local;
    final myScopes = mine.keys.map(profileScopeOfMapKey).toSet();
    final theirs = decodeStringMap(remote) ?? const <String, dynamic>{};
    final out = <String, dynamic>{
      for (final e in mine.entries)
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)))
          e.key: _newerEntry(e.value, theirs[e.key]),
      for (final e in theirs.entries)
        if (PreferenceSyncScope.isPortableProfileScope(profileScopeOfMapKey(e.key)) &&
            !myScopes.contains(profileScopeOfMapKey(e.key)))
          e.key: e.value,
    };
    if (out.isEmpty) return null;
    return json.encode(out);
  },
);

/// The `{profileScope}` half of a map key: everything before the first `|`,
/// or the whole key when there is none.
String profileScopeOfMapKey(String key) {
  final pipe = key.indexOf('|');
  return pipe < 0 ? key : key.substring(0, pipe);
}

/// Prefer [preferred] unless both are maps carrying a timestamp and [other]'s
/// is higher. The stores write it as `u` (`TrackLanguageChoice.toJson`,
/// `PleyaProfileLanguagePreferences.toJson`); `updatedAt` is accepted too.
Object? _newerEntry(Object? preferred, Object? other) {
  if (preferred is Map && other is Map) {
    final a = preferred['u'] ?? preferred['updatedAt'];
    final b = other['u'] ?? other['updatedAt'];
    if (a is num && b is num && b > a) return other;
  }
  return preferred;
}

/// Decode a JSON object, or null when the value is not one.
Map<String, dynamic>? decodeStringMap(Object? raw) {
  if (raw is! String) return null;
  try {
    final decoded = json.decode(raw);
    return decoded is Map ? Map<String, dynamic>.from(decoded) : null;
  } catch (_) {
    return null;
  }
}

/// The legacy progress maps: progress takes the maximum, watched ORs.
///
/// Registered rather than special-cased. It does not run today — those keys are
/// runtime cache and never sync — but the family is where the behaviour belongs
/// if a legacy record ever turns up, and registering it removes the last
/// hardcoded key-prefix branch from the coordinator.
PreferenceMergeFamily buildProgressMapFamily({required bool watchedMap}) => PreferenceMergeFamily(
  name: watchedMap ? PreferenceMergeFamilies.watchedMap : PreferenceMergeFamilies.progressMap,
  inbound: (local, remote) {
    if (remote is! String) return local;
    return mergeProgressMapJson(local is String ? local : null, remote, watchedMap: watchedMap);
  },
);

/// Merge two JSON progress maps: progress = max, watched = OR.
String mergeProgressMapJson(String? local, String incoming, {required bool watchedMap}) {
  try {
    final localMap = local == null ? <String, dynamic>{} : json.decode(local) as Map<String, dynamic>;
    final incomingMap = json.decode(incoming) as Map<String, dynamic>;
    final merged = Map<String, dynamic>.from(localMap);
    incomingMap.forEach((key, value) {
      final existing = merged[key];
      if (watchedMap) {
        merged[key] = (existing == true) || (value == true);
      } else {
        final a = existing is num ? existing : 0;
        final b = value is num ? value : 0;
        merged[key] = a > b ? a : b;
      }
    });
    return json.encode(merged);
  } catch (_) {
    return local ?? incoming;
  }
}

/// Decode a JSON list of strings, or null when the value is not one.
List<String>? decodeStringList(Object? raw) {
  if (raw is! String) return null;
  try {
    final decoded = json.decode(raw);
    if (decoded is! List) return null;
    return decoded.map((e) => e.toString()).toList();
  } catch (_) {
    return null;
  }
}
