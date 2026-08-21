/// Whether a server id means the same thing on somebody else's device.
///
/// Key scoping alone is not enough for the library families. Their *values*
/// carry `serverId:libraryId` entries, and a key can carry one too
/// (`library_sort_<serverId:libraryId>`), so a correctly namespaced cloud
/// record can still hold state that is meaningless elsewhere.
///
/// The plan assumed `serverId` was a locally assigned connection id. It is not,
/// and the difference matters:
///
/// - **Plex**: `serverId` is `PlexServer.clientIdentifier`, read from plex.tv's
///   `/resources` payload (`plex_auth_service.dart:354`) and used as the client
///   key in `multi_server_manager.dart:476`. plex.tv hands the same value to
///   every device on the account, so it is portable.
/// - **Jellyfin**: `serverId` is `connection.serverMachineId`, taken from the
///   server's own `machineId` (`jellyfin_auth_service.dart:434`). Also portable.
/// - **Local folder** and **Pleya Share**: `serverId` is `connection.id`, a
///   locally generated row id. Two installations never agree on it, and a local
///   folder is device-bound anyway.
///
/// So this is deny-by-default on the *connection kind*, not a guess about the
/// string: an id is portable only when it came from a backend that hands out a
/// stable server identity.
typedef IsServerIdPortable = bool Function(String serverId);

/// Nothing is portable. The safe default when the connection layer has not been
/// wired up yet: preferences stay on the device rather than syncing something
/// that cannot be read back.
bool noServerIdIsPortable(String serverId) => false;

class PreferenceValuePortability {
  const PreferenceValuePortability._();

  /// The server id an entry belongs to, or null when it carries none.
  ///
  /// Entries are `serverId:rest`, the shape `buildGlobalKey` produces. Server
  /// ids do not contain the separator, so the first segment is the answer;
  /// `indexOf` rather than `split` keeps colons in the remainder intact.
  static String? serverIdOf(String entry) {
    final index = entry.indexOf(':');
    if (index <= 0) return null;
    return entry.substring(0, index);
  }

  /// Whether one list entry may leave the device.
  ///
  /// An entry without a server id is not automatically fine: it is state whose
  /// origin cannot be established, so it stays local.
  static bool isPortableEntry(String entry, IsServerIdPortable isPortable) {
    final serverId = serverIdOf(entry);
    if (serverId == null) return false;
    return isPortable(serverId);
  }

  /// The subset of [entries] that may be transported, in the original order.
  static List<String> portableEntries(Iterable<String> entries, IsServerIdPortable isPortable) =>
      entries.where((e) => isPortableEntry(e, isPortable)).toList(growable: false);

  /// The subset that must stay behind.
  static List<String> localOnlyEntries(Iterable<String> entries, IsServerIdPortable isPortable) =>
      entries.where((e) => !isPortableEntry(e, isPortable)).toList(growable: false);

  /// Whether a per-library key (`library_sort_<serverId:libraryId>`) may travel.
  ///
  /// The identifier is in the key here rather than the value, so there is
  /// nothing to filter: the key travels whole or not at all.
  static bool isPortableScopedKey(String baseKey, String prefix, IsServerIdPortable isPortable) {
    if (!baseKey.startsWith(prefix)) return false;
    return isPortableEntry(baseKey.substring(prefix.length), isPortable);
  }

  /// Combine an incoming portable list with the local-only entries already
  /// here.
  ///
  /// A remote apply must not be a wholesale replacement. The other device never
  /// saw this device's local-folder libraries, so its list simply lacks them;
  /// treating that absence as a removal would delete a local folder's hidden
  /// state every time another device changed anything. Portable entries come
  /// from [remote], non-portable ones are preserved from [local].
  ///
  /// Order: remote first (the sending device's intent), then the local-only
  /// entries in their existing relative order.
  static List<String> mergeKeepingLocalOnly(
    Iterable<String> remote,
    Iterable<String> local,
    IsServerIdPortable isPortable,
  ) {
    final incoming = portableEntries(remote, isPortable);
    final kept = localOnlyEntries(local, isPortable);
    final seen = incoming.toSet();
    return [...incoming, ...kept.where(seen.add)];
  }
}
