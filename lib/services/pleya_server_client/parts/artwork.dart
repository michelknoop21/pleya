part of '../../pleya_server_client.dart';

/// Artwork URLs and the header that makes them load.
///
/// `GET /artwork/{id}` is class `authenticated` and takes a bearer header. The
/// contract deliberately does not accept a token in the query string here: the
/// stream token exists for players that cannot set a header, and it is scoped
/// to `/stream` and `/subtitles` alone. Plex and Jellyfin both put their token
/// in the artwork URL, and copying that would be a protocol violation dressed
/// as consistency.
///
/// The app renders artwork through `CachedNetworkImage`, which carries a URL
/// and no headers. Rather than threading a header parameter through every image
/// call site, the client registers a header supplier for its origin with
/// [ArtworkAuthorizationRegistry], which the artwork transport already funnels
/// every download through. Backend-specific knowledge stops at this file; the
/// registry knows about origins and headers only.
mixin _PleyaServerArtworkMethods on _PleyaServerRequests {
  /// An absolute URL for an artwork path produced by [PleyaServerMappers].
  ///
  /// Returns an empty string for anything else, including a path from another
  /// backend that ended up here through a cached row. An empty string is what
  /// the image helper already treats as "no artwork".
  String thumbnailUrl(String? path, {int? width, int? height}) {
    if (!wireCapabilities.artwork) return '';
    final id = PleyaServerMappers.artworkIdFromPath(path);
    if (id == null) return '';
    // The contract has `width` and nothing else. Height is not a parameter,
    // because the server preserves the aspect ratio and a second dimension
    // would only let a client ask for a shape the image has not got.
    final query = width != null && width > 0 ? {'width': '${width.clamp(1, 4096)}'} : null;
    return Uri.parse(
      '${connection.baseUrl}$pleyaProtocolPrefix/artwork/${Uri.encodeComponent(id)}',
    ).replace(queryParameters: query).toString();
  }

  /// The protocol has no image proxy. Plex offers `/photo/:/transcode?url=`;
  /// there is no counterpart, so an external URL is fetched as it stands.
  String externalImageUrl(String url, {int? width, int? height}) => url;

  /// Make this server's artwork loadable by the shared image transport.
  ///
  /// Called once per client. The supplier mints a token through the session, so
  /// a rotation between two posters is handled by the same single-flight path
  /// as everything else.
  void _registerArtworkAuthorization() {
    ArtworkAuthorizationRegistry.register(connection.baseUrl, () => _session.authHeaders());
  }

  /// Stop answering for this origin.
  ///
  /// Keyed on the origin, so two connections to one server share an entry and
  /// removing it on the first close would take the second one's artwork with
  /// it. That is a PS-9 concern (one server, several identities); for now a
  /// closed client is a client whose connection is gone.
  void _unregisterArtworkAuthorization() {
    ArtworkAuthorizationRegistry.unregister(connection.baseUrl);
  }
}
