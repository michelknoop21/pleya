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
}
