import '../settings_export_service.dart';
import '../track_preference_store.dart';
import 'preference_merge_strategies.dart';
import 'preference_sync_policy.dart';
import 'preference_sync_scope.dart';
import 'preference_value_portability.dart';

/// Maps between local prefs keys and the keys records travel under, and decides
/// what may travel: scope, key portability and the per-family merges. Knows
/// nothing about transports or status.
class PreferenceKeyMapper {
  PreferenceKeyMapper({
    required String? Function() activeProfileId,
    required this.v2Format,
    required IsServerIdPortable isServerIdPortable,
  }) : _activeProfileId = activeProfileId,
       isServerIdPortable = isServerIdPortable {
    _registerBuiltInMergeFamilies();
  }

  final String? Function() _activeProfileId;

  /// Whether records travel in the scoped, enveloped v2 format.
  final bool v2Format;

  /// Whether a server id identifies the same server on another device. Deny by
  /// default: without the connection layer wired in, nothing is portable.
  ///
  /// Late-bindable, because the answer comes from the connection registry and
  /// that only exists once the database is open, well after the engine starts.
  /// Until it is supplied nothing library-scoped travels, which is the right
  /// way round: a missing answer must not read as "yes".
  IsServerIdPortable isServerIdPortable;

  /// The active profile's scope.
  PreferenceSyncScope get activeProfileScope => PreferenceSyncScope.forProfile(_activeProfileId());

  PreferenceSyncScope scopeFor(String baseKey) {
    final policy = PreferenceSyncPolicyRegistry.policyFor(baseKey);
    return switch (policy.scope) {
      PreferenceScopeKind.global => PreferenceSyncScope.global,
      PreferenceScopeKind.deviceLocal => PreferenceSyncScope.deviceLocal,
      PreferenceScopeKind.profile => activeProfileScope,
    };
  }

  /// Full prefs key to the key it travels under, or null when it must not
  /// travel: unregistered, sensitive, device-local, another profile's, or a
  /// profile-scoped value with no portable profile behind it.
  String? cloudKeyFor(String fullKey) {
    final baseKey = baseKeyOf(fullKey);
    if (baseKey == null) return null;
    if (!PreferenceSyncPolicyRegistry.maySync(baseKey)) return null;
    if (!_keyIdentityIsPortable(baseKey)) return null;
    final scope = scopeFor(baseKey);
    if (!scope.portable) return null;
    return v2Format ? scope.cloudKey(wireBaseKey(baseKey)) : baseKey;
  }

  /// [baseKey] as it appears inside a v2 cloud key. A per-library key carries
  /// its `serverId:libraryId` as a [PreferenceSyncScope.shortId], because the
  /// full identity does not fit in 64 bytes; everything else is unchanged.
  static String wireBaseKey(String baseKey) {
    for (final prefix in perLibraryKeyPrefixes) {
      if (baseKey.startsWith(prefix)) return '$prefix${PreferenceSyncScope.shortId(baseKey.substring(prefix.length))}';
    }
    return baseKey;
  }

  /// The full base key a record has to carry (as `k`) because its cloud key
  /// hides it, or null when the cloud key says it all.
  String? keyTagFor(String baseKey) => v2Format && wireBaseKey(baseKey) != baseKey ? baseKey : null;

  /// The base key of a received record: [segment] from the cloud key, or for
  /// a shortened per-library segment the record's [keyTag], but only when it
  /// hashes back to that segment. A portable per-library identity always has
  /// a `:` and a short id never does, so an unshortened segment (the long form
  /// an earlier build of this branch wrote) still reads as itself.
  static String? resolveBaseKey(String segment, String? keyTag) {
    final shortened = perLibraryKeyPrefixes.any(
      (prefix) => segment.startsWith(prefix) && !segment.substring(prefix.length).contains(':'),
    );
    if (!shortened) return segment;
    if (keyTag == null || wireBaseKey(keyTag) != segment) return null;
    return keyTag;
  }

  /// Per-library families put the identity in the key
  /// (`library_sort_<serverId:libraryId>`), so there is nothing to filter out
  /// of the value: the key travels whole or not at all.
  bool _keyIdentityIsPortable(String baseKey) {
    for (final prefix in perLibraryKeyPrefixes) {
      if (baseKey.startsWith(prefix)) {
        return PreferenceValuePortability.isPortableScopedKey(baseKey, prefix, isServerIdPortable);
      }
    }
    return true;
  }

  /// Families whose key carries a `serverId:libraryId`.
  static const List<String> perLibraryKeyPrefixes = [
    'library_filters_',
    'library_sort_',
    'library_grouping_',
    'library_tab_',
  ];

  /// The merge behaviour per family, looked up by the name in the policy.
  ///
  /// The coordinator never learns what a value means. It asks the registry
  /// whether this key's family has a merge and calls it. Before this there was
  /// one hardcoded `if` on a key list, which is why nothing else could ever
  /// need a merge.
  final PreferenceMergeRegistry merges = PreferenceMergeRegistry();

  void _registerBuiltInMergeFamilies() {
    // The closure reads the field rather than capturing it: the portability
    // predicate arrives from the connection registry after the engine starts.
    merges.register(buildServerScopedListFamily((serverId) => isServerIdPortable(serverId)));
    merges.register(buildProgressMapFamily(watchedMap: false));
    merges.register(buildProgressMapFamily(watchedMap: true));
    merges.register(buildProfileKeyedMapFamily());
    merges.register(TrackPreferenceStore.mergeFamily());
  }

  /// The value as it may leave the device, or null when nothing may.
  ///
  /// For a family with an outgoing merge this is where it runs. [remote] is the
  /// value currently in the store, when the caller could read it; null means
  /// "not available", and a family must then fall back to what it can decide on
  /// its own — for the server-scoped lists, dropping the entries whose server id
  /// is not portable. A device with one Plex server and one local folder still
  /// syncs its Plex choices; the folder's simply never leave.
  Object? portableValueFor(String baseKey, Object? value, {Object? remote}) {
    final outbound = merges.familyFor(baseKey)?.outbound;
    if (outbound == null) return value;
    return outbound(value, remote);
  }

  /// Strip the active profile's prefix. Returns null for a key belonging to
  /// another profile, or for a reserved namespace.
  String? baseKeyOf(String fullKey) {
    for (final reserved in PreferenceSyncPolicyRegistry.reservedPrefixes) {
      if (fullKey.startsWith(reserved)) return null;
    }
    final prefix = activeProfileScope.localPrefix;
    if (prefix.isNotEmpty && fullKey.startsWith(prefix)) return fullKey.substring(prefix.length);
    if (fullKey.startsWith(SettingsExportService.userPrefixRoot)) return null;
    return fullKey;
  }

  /// Inverse of [baseKeyOf] for a base key that arrived from a transport.
  String? localKeyFor(String baseKey) {
    if (!PreferenceSyncPolicyRegistry.isProfileScoped(baseKey)) return baseKey;
    final scope = activeProfileScope;
    if (scope.id == null) return null;
    return '${scope.localPrefix}$baseKey';
  }

  /// The key this device keeps its stamp for [baseKey] under.
  ///
  /// A profile-scoped preference is one value per profile, so it needs one
  /// stamp per profile too: keyed by the base key alone, profile A's change
  /// decided profile B's conflicts on the same device. The full local key
  /// (`user_<scope>_<baseKey>`) is that per-profile identity.
  String stampKeyFor(String baseKey) {
    if (!PreferenceSyncPolicyRegistry.isProfileScoped(baseKey)) return baseKey;
    return localKeyFor(baseKey) ?? baseKey;
  }

  /// Whether a transport key is a record this coordinator, in its current
  /// format, is entitled to delete.
  ///
  /// Under v2 the answer is always no. A removal travels as a tombstone since
  /// DEC-134, so a record this device does not hold is one it has not seen
  /// yet, never one it deleted. The v1 path keeps a prune for the
  /// rolling-upgrade test. That path is not the released v1 algorithm any
  /// more: it writes stamped records and compares before it writes.
  bool ownsCloudKey(String cloudKey) {
    if (v2Format) return false;
    if (cloudKey.startsWith('__')) return false;
    return PreferenceSyncPolicyRegistry.maySync(cloudKey);
  }
}
