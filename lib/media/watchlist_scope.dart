import 'media_backend.dart';

/// Identity of a single watchlist as this app sees it.
///
/// A watchlist is never "the user's watchlist" in the abstract. Plex's lives on
/// an account plus a Home user; Jellyfin's favorites live on a server plus a
/// user on that server. Pleya adds a third axis, because the same device can
/// hold several profiles that each bind to their own connections.
///
/// Every persisted row, cache entry and in-memory index that holds watchlist
/// data is keyed by a [WatchlistScopeId]. That is what keeps a profile switch
/// from showing the previous user's list, and what keeps two Pleya profiles
/// that point at the same Jellyfin server with different Jellyfin users apart.
///
/// [accountId] carries the **bare** identifier:
///
/// * Plex: the plex.tv account uuid, without the `plex.` prefix that
///   `PlexAccountConnection.id` wears. The [backend] field already says what
///   kind of id this is, so repeating it inside the value only adds a way to
///   get it wrong.
/// * Jellyfin: `JellyfinConnection.serverMachineId`.
///
/// [userId] carries the real acting user:
///
/// * Plex: the Home user uuid, or the account uuid for the account owner.
/// * Jellyfin: `JellyfinConnection.userId`.
class WatchlistScopeId {
  /// The active Pleya profile this scope belongs to.
  final String profileId;

  /// Which backend this watchlist lives on.
  final MediaBackend backend;

  /// Account-level identity. See the class doc for the per-backend meaning.
  final String accountId;

  /// The acting user within [accountId]. See the class doc.
  final String userId;

  const WatchlistScopeId({
    required this.profileId,
    required this.backend,
    required this.accountId,
    required this.userId,
  });

  /// Separator between the encoded components of [storageKey].
  ///
  /// Safe because [Uri.encodeComponent] escapes everything outside
  /// `A-Z a-z 0-9 - _ . ! ~ * ' ( )`, so a colon can never survive inside an
  /// encoded component; it only ever appears where this key puts it.
  static const String _separator = ':';

  /// Canonical, collision-free string form, for use as a storage or cache key.
  ///
  /// Each component is percent-encoded on its own before the components are
  /// joined, so a value that happens to contain the separator cannot shift the
  /// boundary between components. A naive `a:b` join would let
  /// `(profileId: 'a:b', accountId: 'c')` and `(profileId: 'a', accountId:
  /// 'b:c')` produce the same key and hand one profile another profile's list.
  String get storageKey => [
    Uri.encodeComponent(profileId),
    Uri.encodeComponent(backend.id),
    Uri.encodeComponent(accountId),
    Uri.encodeComponent(userId),
  ].join(_separator);

  @override
  bool operator ==(Object other) =>
      identical(this, other) ||
      other is WatchlistScopeId &&
          other.profileId == profileId &&
          other.backend == backend &&
          other.accountId == accountId &&
          other.userId == userId;

  @override
  int get hashCode => Object.hash(profileId, backend, accountId, userId);

  @override
  String toString() => 'WatchlistScopeId($storageKey)';
}
