part of '../../pleya_server_client.dart';

/// Everything a Pleya Server cannot do in PS-3, in one place.
///
/// `MediaServerClient` is a wide interface, and every backend has to answer all
/// of it. Splitting the answers apart means a reader of `pleya_server_client.dart`
/// sees browse, search and artwork without wading through forty stubs, and a
/// later phase can lift a member out of here into a real part file.
///
/// Two rules hold across this file, both from the interface's error contract:
///
///   * a read that has no source answers empty, never null-as-error and never
///     a throw. An empty list is a state the UI already renders;
///   * a write that cannot apply returns `false` or does nothing, because
///     "operation impossible" is explicitly not the same as "server error".
///
/// The canonical write below (media delete) is a no-op, so it skips
/// [ServerAuthorityGuard]. The day one lifts
/// out of here into a real part file, it asserts the guard before its first
/// request, like the admin part does: `assertCanManageServerMetadata()` for
/// metadata (owner only), `assertCanAdministerServer()` for administration,
/// which a Pleya Server admin passes as well as the owner.
///
/// Nothing here is gated on a runtime check. `ServerCapabilities` already keeps
/// the affordances off the screen ([PleyaServerCapabilityResolver]); these are
/// the belt to that pair of braces, for the paths that call a member without
/// asking first.
mixin _PleyaServerUnsupportedMethods {
  // ── Library shape the contract does not carry ──

  /// No first-character endpoint and no name-prefix filter. Counting a page
  /// client-side would place the bar's offsets against a cursored list, and
  /// every jump past the first page would land somewhere else.
  Future<List<LibraryFirstCharacter>> fetchFirstCharacters(String libraryId, {Map<String, String>? filters}) async =>
      const [];

  /// No folder listing. `storage_locations` is server-side state the protocol
  /// does not expose.
  Future<List<MediaItem>> fetchLibraryFolders(
    String libraryId, {
    void Function(List<MediaItem> itemsSoFar)? onPage,
  }) async => const [];

  Future<List<MediaItem>> fetchFolderChildren(
    MediaItem folder, {
    String? libraryId,
    String? libraryTitle,
    void Function(List<MediaItem> itemsSoFar)? onPage,
  }) async => const [];

  /// No extras, trailers or behind-the-scenes in the catalogue.
  Future<List<MediaItem>> fetchExtras(String id) async => const [];

  /// People arrive with metadata in PS-7.
  Future<List<MediaItem>> fetchPersonMedia(String personId) async => const [];

  Future<LibraryPage<MediaItem>> fetchPersonMediaPage(
    String personId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => const LibraryPage(items: [], totalCount: 0);

  /// Related titles need genres and people, which arrive in PS-7.
  Future<List<MediaHub>> fetchRelatedHubs(String id, {int count = 10}) async => const [];

  /// No `external_ids` table until PS-7, so identity lookups have nothing to
  /// match on. Answering null rather than guessing keeps the watchlist
  /// availability count honest.
  Future<MediaItem?> findByIdentity(MediaIdentity identity) async => null;

  Future<List<MediaItem>> findAllByIdentity(MediaIdentity identity) async => const [];

  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  /// Media mounts are read-only from v1 on, by design and by threat model.
  /// This is not a missing phase; it is a decision.
  Future<bool> deleteMediaItem(MediaItem item) async => false;

  // ── Playback: PS-4 and later ──

  Future<PlaybackExtras> fetchPlaybackExtras(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
    bool forceRefresh = false,
  }) async => PlaybackExtras(chapters: const [], markers: const []);

  Future<PlaybackExtras?> fetchPlaybackExtrasFromCacheOnly(
    String itemId, {
    String? introPattern,
    String? creditsPattern,
    bool forceChapterFallback = false,
  }) async => null;

  Future<ScrubPreviewSource?> createScrubPreviewSource({
    required MediaItem item,
    required MediaSourceInfo mediaSource,
  }) async => null;

  LiveTvSupport get liveTv => const NoopLiveTvSupport();

  LiveTvDvrSupport? get liveTvDvr => null;

  // ── Downloads ──
  // `resolveDownload` lives in downloads.dart (S23).
}
