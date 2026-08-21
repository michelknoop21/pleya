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
/// Nothing here is gated on a runtime check. `ServerCapabilities` already keeps
/// the affordances off the screen ([PleyaServerCapabilityResolver]); these are
/// the belt to that pair of braces, for the paths that call a member without
/// asking first.
mixin _PleyaServerUnsupportedMethods {
  // ── Library shape the contract does not carry ──

  /// The contract has `limit`, `cursor` and `sort` on a library listing and no
  /// filter parameter at all. Answering with a synthetic category list would
  /// put a filter sheet on screen that cannot filter. G13 in the replacement
  /// matrix.
  Future<LibraryFilterResult> fetchLibraryFiltersWithValues(String libraryId) async => LibraryFilterResult.empty;

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

  /// Scanning is server-side and has no admin endpoint yet. G6.
  Future<void> refreshLibraryMetadata(String libraryId) async {}

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

  Future<ExternalIds> fetchExternalIds(String itemId) async => const ExternalIds();

  // ── Per-user state: PS-9 ──

  Future<void> setFavorite(MediaItem item, bool isFavorite) async {}

  Future<LibraryPage<MediaItem>> fetchFavorites({MediaKind? kind, int offset = 0, int limit = 100}) async =>
      const LibraryPage(items: [], totalCount: 0);

  Future<void> rate(MediaItem item, double rating) async {}

  // ── Playlists and collections: G1, no phase yet ──

  Future<List<MediaPlaylist>> fetchPlaylists({String playlistType = 'video', bool? smart}) async => const [];

  Future<LibraryPage<MediaPlaylist>> fetchPlaylistsPage({
    String playlistType = 'video',
    bool? smart,
    int? start,
    int? size,
    AbortController? abort,
  }) async => const LibraryPage(items: [], totalCount: 0);

  Future<MediaPlaylist?> fetchPlaylistMetadata(String id) async => null;

  Future<List<MediaItem>> fetchPlaylistItems(String id, {int offset = 0, int limit = 100}) async => const [];

  Future<LibraryPage<MediaItem>> fetchPlaylistPage(String id, {int? start, int? size, AbortController? abort}) async =>
      const LibraryPage(items: [], totalCount: 0);

  Future<MediaPlaylist?> createPlaylist({required String title, required List<MediaItem> items}) async => null;

  Future<bool> addToPlaylist({required String playlistId, required List<MediaItem> items}) async => false;

  Future<bool> deletePlaylist(MediaPlaylist playlist) async => false;

  Future<bool> movePlaylistItem({
    required String playlistId,
    required MediaItem item,
    required int newIndex,
    required MediaItem? afterItem,
  }) async => false;

  Future<bool> removeFromPlaylist({required String playlistId, required MediaItem item}) async => false;

  Future<List<MediaItem>> fetchCollections(String libraryId) async => const [];

  Future<LibraryPage<MediaItem>> fetchCollectionsPage(
    String libraryId, {
    int? start,
    int? size,
    AbortController? abort,
  }) async => const LibraryPage(items: [], totalCount: 0);

  Future<LibraryPage<MediaItem>> fetchCollectionPage(
    String collectionId, {
    int? start,
    int? size,
    String? libraryId,
    String? libraryTitle,
    AbortController? abort,
  }) async => const LibraryPage(items: [], totalCount: 0);

  Future<String?> createCollection({
    required String libraryId,
    required String title,
    required List<MediaItem> items,
    MediaKind? itemKind,
  }) async => null;

  Future<bool> addToCollection({required String collectionId, required List<MediaItem> items}) async => false;

  Future<bool> removeFromCollection({required String collectionId, required MediaItem item}) async => false;

  Future<bool> deleteCollection(MediaItem collection) async => false;

  /// Media mounts are read-only from v1 on, by design and by threat model.
  /// This is not a missing phase; it is a decision.
  Future<bool> deleteMediaItem(MediaItem item) async => false;

  // ── Playback: PS-4 and later ──

  Future<MediaFileInfo?> getFileInfo(MediaItem item) async => null;

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

  Future<MediaSourceInfo?> fetchCachedMediaSourceInfo(String itemId) async => null;

  Future<ScrubPreviewSource?> createScrubPreviewSource({
    required MediaItem item,
    required MediaSourceInfo mediaSource,
  }) async => null;

  LiveTvSupport get liveTv => const NoopLiveTvSupport();

  LiveTvDvrSupport? get liveTvDvr => null;

  // ── Downloads: PS-10 ──

  Future<DownloadResolution> resolveDownload(MediaItem item, {int mediaIndex = 0}) async =>
      const DownloadResolution(videoUrl: null);

  List<DownloadArtworkSpec> resolveDownloadArtwork(MediaItem item) => const [];
}
