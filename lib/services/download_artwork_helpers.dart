import '../media/download_resolution.dart';
import '../media/media_item.dart';

/// Maps a per-item image path/URL to the actual downloadable URL.
/// Plex resolves paths through `getThumbnailUrl` (token-aware); Jellyfin
/// stores absolute URLs already and passes them through. Returning `null`
/// or an empty string skips the entry.
typedef ArtworkUrlResolver = String? Function(String path);

/// Stable storage key for artwork. Jellyfin image URLs carry `api_key` and
/// Plex transcode URLs carry `X-Plex-Token` (twice: as an outer param and
/// inside the encoded `url=` param). Tokens rotate between sessions, so keys
/// derived from the raw URL would miss the cache on every re-auth; persisted
/// DB rows and hashed filenames must not contain long-lived tokens either.
String artworkStorageKey(String pathOrUrl) {
  final uri = Uri.tryParse(pathOrUrl);
  if (uri == null || !uri.hasQuery) return pathOrUrl;
  final params = <String, String>{};
  uri.queryParameters.forEach((key, value) {
    final lower = key.toLowerCase();
    if (lower == 'api_key' || lower == 'x-plex-token') return;
    // Plex nests the source path (with its own token) inside `url=`.
    params[key] = lower == 'url' ? artworkStorageKey(value) : value;
  });
  // replace(queryParameters: null) means "keep the original query", so strip
  // the query manually when nothing survives.
  if (params.isEmpty) return uri.removeFragment().toString().split('?').first;
  return uri.replace(queryParameters: params).toString();
}

/// Build [DownloadArtworkSpec]s for the four standard [MediaItem] image
/// fields (thumb, clearLogo, art, backgroundSquare). The four-field
/// enumeration is the same across backends; only the URL transformation
/// differs.
List<DownloadArtworkSpec> buildArtworkSpecs(MediaItem item, ArtworkUrlResolver resolveUrl) {
  final specs = <DownloadArtworkSpec>[];
  void addIfPresent(String? path) {
    if (path == null || path.isEmpty) return;
    final url = resolveUrl(path);
    if (url == null || url.isEmpty) return;
    specs.add(DownloadArtworkSpec(localKey: artworkStorageKey(path), url: url));
  }

  addIfPresent(item.thumbPath);
  addIfPresent(item.clearLogoPath);
  addIfPresent(item.artPath);
  addIfPresent(item.backgroundSquarePath);
  return specs;
}
