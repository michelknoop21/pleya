import '../exceptions/media_server_exceptions.dart';

/// Service-side half of the owner rule: only the owner of a server may change
/// or delete its canonical metadata (metadata and artwork, match, media and
/// collection deletes, collection membership, library maintenance).
///
/// The UI hides those actions for everyone else, but a hidden button is not a
/// boundary. Every canonical mutation calls [assertCanManageServerMetadata]
/// before it touches the network, so a new menu entry, a test seed or a remote
/// path cannot reach the server around the UI.
///
/// [MultiServerManager] wires [canManageServerMetadata] when it registers the
/// client. An unwired client refuses: fail closed.
mixin ServerAuthorityGuard {
  bool Function()? canManageServerMetadata;

  void assertCanManageServerMetadata() {
    if (canManageServerMetadata?.call() != true) {
      throw const MediaServerAuthException('Only the server owner can change server metadata', statusCode: 403);
    }
  }

  /// Canonical collections: creating one, changing its membership, deleting
  /// it. On Plex and Jellyfin this is [canManageServerMetadata]. On Pleya
  /// Server it is the owner role alone, while the rest of the canonical
  /// metadata has no write path there. It is deliberately not
  /// [canAdministerServer]: a Pleya admin does not manage canonical
  /// collections. Sharing one is the exception and goes through
  /// [assertCanAdministerServer]. Unwired refuses.
  bool Function()? canManageCollections;

  void assertCanManageCollections() {
    if (canManageCollections?.call() != true) {
      throw const MediaServerAuthException('Only the server owner can change collections', statusCode: 403);
    }
  }

  /// Server administration beyond metadata: users, library access, jobs and
  /// scans on backends whose admin role is wider than the owner rule
  /// (Pleya Server admins). Wired and evaluated like
  /// [canManageServerMetadata]; unwired refuses.
  bool Function()? canAdministerServer;

  void assertCanAdministerServer() {
    if (canAdministerServer?.call() != true) {
      throw const MediaServerAuthException('Only a server administrator can do this', statusCode: 403);
    }
  }
}
