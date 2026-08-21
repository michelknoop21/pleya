import '../../profiles/profile.dart';

/// Which population a preference belongs to.
enum PreferenceScopeKind {
  /// One value for the whole installation, shared by every profile.
  global,

  /// One value per Pleya profile.
  profile,

  /// Meaningful only on the device that wrote it: window geometry, download
  /// folders, LAN addresses, hardware capability overrides.
  deviceLocal,
}

/// The identity a preference syncs under.
///
/// v1 stripped the profile prefix before a value went to iCloud, so every
/// profile shared one cloud slot per base key and the last profile to write
/// won. This type keeps the identity attached, and it is honest about when
/// there is no identity worth syncing.
///
/// A scope is only [portable] when the identifier means the same thing on
/// another device. That holds for a Plex Home profile, because Plex owns the
/// home-user UUID and hands out the same one everywhere. It does not hold for a
/// local profile: `local-<uuid>` is generated on first run and a second device
/// generates a different one, so syncing under it would either do nothing or
/// silently graft one person's preferences onto another's profile.
class PreferenceSyncScope {
  const PreferenceSyncScope._(this.kind, this.id, this.portable);

  /// The preferences key holding which profile is active on this device.
  ///
  /// It lives here rather than in `StorageService` because it is scope
  /// business: it decides which namespace this device reads and writes, so the
  /// engine has to recognise a write to it. Device-local by nature — which
  /// profile somebody has open on the Apple TV is not the Mac's business — and
  /// unregistered in the policy, which is what keeps it that way.
  static const String activeProfileIdKey = 'active_app_profile_id';

  /// Shared by every profile on every device signed into the same iCloud
  /// account.
  static const PreferenceSyncScope global = PreferenceSyncScope._(PreferenceScopeKind.global, null, true);

  /// Never leaves this device, whatever the policy says.
  static const PreferenceSyncScope deviceLocal = PreferenceSyncScope._(PreferenceScopeKind.deviceLocal, null, false);

  /// No profile is active. Profile-scoped values have nowhere to go.
  static const PreferenceSyncScope none = PreferenceSyncScope._(PreferenceScopeKind.profile, null, false);

  final PreferenceScopeKind kind;

  /// The scope identifier, or null for [global], [deviceLocal] and [none].
  final String? id;

  /// Whether [id] identifies the same profile on another device.
  final bool portable;

  /// Resolve the scope for [profileId], the id [StorageService] stores under
  /// `active_app_profile_id`.
  ///
  /// A Plex Home profile resolves to its home-user UUID, which is what the
  /// existing `user_{scope}_` prefixes already use, so no local key changes
  /// shape. Anything else resolves to a non-portable scope carrying the full
  /// profile id: still usable for local storage, never usable as a cloud
  /// namespace.
  static PreferenceSyncScope forProfile(String? profileId) {
    if (profileId == null || profileId.isEmpty) return none;
    final home = parsePlexHomeProfileId(profileId);
    if (home != null) {
      return PreferenceSyncScope._(PreferenceScopeKind.profile, home.homeUserUuid, true);
    }
    return PreferenceSyncScope._(PreferenceScopeKind.profile, profileId, false);
  }

  /// The local prefs prefix for this scope. Matches what `StorageService`
  /// already writes, so this is a description of today's storage, not a change
  /// to it.
  String get localPrefix => switch (kind) {
    PreferenceScopeKind.global => '',
    PreferenceScopeKind.deviceLocal => '',
    PreferenceScopeKind.profile => id == null ? '' : 'user_${id}_',
  };

  /// The cloud namespace for [key], or null when this scope must not sync.
  ///
  /// The `__` prefix is not decoration. A shipped Pleya build skips every KVS
  /// key starting with `__`, both when pruning keys it cannot reproduce and
  /// when applying remote changes, so records written here are invisible to
  /// older clients instead of being deleted by them. See
  /// `test/services/icloud_rolling_upgrade_test.dart`.
  /// Specifically this coordinator's records, not everything under `__`.
  ///
  /// An older client skipping all `__` keys is what makes coexistence work, but
  /// the new client must not read that as "everything under `__` is mine".
  /// `__syncFormatVersion` is a sibling, a v3 would be another, and a future
  /// feature may add more. Ownership is claimed for exactly this prefix.
  static const String cloudNamespacePrefix = '__pleya_pref_v2/';

  /// Whether [cloudKey] is a record this sync format owns.
  static bool ownsCloudKey(String cloudKey) => cloudKey.startsWith(cloudNamespacePrefix);

  /// Inverse of [cloudKey]: the scope a v2 record belongs to and the base key
  /// inside it, or null when the key is not one of ours or is malformed.
  ///
  /// The profile id comes back so the caller can check it against the active
  /// profile. That check is the entire reason the namespace exists: under v1
  /// every profile shared one slot per base key, so there was nothing to
  /// compare and a record for profile B landed on profile A.
  static ({PreferenceScopeKind kind, String? id, String baseKey})? parseCloudKey(String cloudKey) {
    if (!ownsCloudKey(cloudKey)) return null;
    final rest = cloudKey.substring(cloudNamespacePrefix.length);
    if (rest.startsWith('global/')) {
      final baseKey = rest.substring('global/'.length);
      if (baseKey.isEmpty) return null;
      return (kind: PreferenceScopeKind.global, id: null, baseKey: baseKey);
    }
    if (rest.startsWith('profile/')) {
      final tail = rest.substring('profile/'.length);
      final slash = tail.indexOf('/');
      if (slash <= 0) return null;
      final id = tail.substring(0, slash);
      final baseKey = tail.substring(slash + 1);
      if (baseKey.isEmpty) return null;
      return (kind: PreferenceScopeKind.profile, id: id, baseKey: baseKey);
    }
    return null;
  }

  String? cloudKey(String key) {
    if (!portable) return null;
    return switch (kind) {
      PreferenceScopeKind.deviceLocal => null,
      PreferenceScopeKind.global => '${cloudNamespacePrefix}global/$key',
      PreferenceScopeKind.profile =>
        id == null
            ? null
            : '$cloudNamespacePrefix'
                  'profile/$id/$key',
    };
  }

  @override
  bool operator ==(Object other) =>
      other is PreferenceSyncScope && other.kind == kind && other.id == id && other.portable == portable;

  @override
  int get hashCode => Object.hash(kind, id, portable);

  @override
  String toString() => 'PreferenceSyncScope(${kind.name}, ${id ?? '-'}, portable: $portable)';
}
