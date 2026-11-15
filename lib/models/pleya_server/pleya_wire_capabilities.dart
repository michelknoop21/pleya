part of 'pleya_wire.dart';

class PleyaCapabilities {
  const PleyaCapabilities({
    required this.browse,
    required this.search,
    required this.artwork,
    required this.watchState,
    this.playbackPlan = false,
    this.playbackQuality = false,
    this.playbackAudioSelection = false,
    this.playbackStartPosition = false,
    this.embeddedSubtitles = false,
    this.playbackSubtitles = false,
    this.history = false,
    this.favorites = false,
    this.ratings = false,
    this.trackPreferences = false,
    this.collections = false,
    this.playlists = false,
    this.itemActivity = false,
    this.assistantMemory = false,
    this.pushNotifications = false,
    this.pushRichContent = false,
    this.transcode = false,
    this.downloads = false,
    this.liveTv = false,
    this.realtime = false,
    this.users = false,
    this.artworkSizes = false,
    this.filters = false,
    this.externalIdLookup = false,
    this.appliedExternalIdentity = false,
    this.metadataMatchStatus = false,
    this.watchStateOwnership = false,
    this.watchStateCopy = false,
    this.streamSessions = false,
    this.sessions = false,
    this.administration = false,
    this.libraryMaintenance = false,
    this.watchStateTree = false,
    this.itemMetadataRefresh = false,
    this.scanSchedule = false,
    this.mediaDelete = false,
    this.mcp = false,
  });

  /// What a client may assume before the first successful `GET /info`.
  ///
  /// Everything off, including the four required flags. A connection that has
  /// not answered yet is not a server that browses; it is a server that has
  /// told us nothing, and claiming otherwise is how a screen ends up calling an
  /// endpoint that is not there.
  static const PleyaCapabilities unknown = PleyaCapabilities(
    browse: false,
    search: false,
    artwork: false,
    watchState: false,
  );

  final bool browse;
  final bool search;
  final bool artwork;
  final bool watchState;
  final bool playbackPlan;
  final bool playbackQuality;
  final bool playbackAudioSelection;

  /// `POST /playback/plan` takes `start_position_ms` and a conversion starts
  /// there (DEC-XXX, startpositie in het afspeelplan). The request body is
  /// closed, so the field goes out only behind this flag.
  final bool playbackStartPosition;
  final bool embeddedSubtitles;
  final bool playbackSubtitles;

  /// The personal layer of S20: play history, favorites and ratings on items,
  /// and the remembered audio and subtitle choice per title.
  final bool history;
  final bool favorites;
  final bool ratings;
  final bool trackPreferences;

  /// S19, chapter 14c: the `/collections` resource.
  final bool collections;

  /// S19, chapter 14c: the `/playlists` resource.
  final bool playlists;

  /// `GET /items/{id}/activity` and the opt-out under
  /// `/users/me/activity-sharing`, which always come together.
  final bool itemActivity;
  final bool assistantMemory;
  final bool pushNotifications;

  /// DEC-XXX: the push PUT takes `content_key`, so a notification can carry
  /// the sealed title and poster. Without it the body must not carry the key.
  final bool pushRichContent;
  final bool transcode;
  final bool downloads;
  final bool liveTv;
  final bool realtime;
  final bool users;

  /// `GET /artwork/{id}` answers `width` with a step of a fixed ladder instead of
  /// the original. The app sends `width` regardless: a server without the flag
  /// ignores it, so the flag changes what comes back and not what is asked.
  final bool artworkSizes;

  /// `GET /libraries/{id}/items` executes the filter parameters (`genre`,
  /// `year`, `watch`, ...) and the sorts `last_played_at` and `duration`, and
  /// `GET /libraries/{id}/facets` exists. A server without the flag ignores
  /// the parameters, so a client that sent them anyway would show a whole
  /// library as the answer to a filter; this flag decides whether they are sent.
  final bool filters;

  /// `GET /libraries/{id}/items` answers `external_id=tmdb:<n>` and items carry
  /// `external_ids`. Without it the parameter is ignored and the whole library
  /// comes back, so the client never sends it.
  final bool externalIdLookup;
  final bool appliedExternalIdentity;
  final bool metadataMatchStatus;

  /// The server knows the ownership model: `base_revision`, the
  /// `playback_started` acquisition and the backlog marker on a watch-state
  /// event. `WatchStateEvent` is a closed schema, so a client that sends those
  /// fields to a server without this flag gets its whole request refused.
  final bool watchStateOwnership;

  /// The server knows `copy` on a watch-state event: the state of another source
  /// of this title, which is no viewing (voorstel DEC-XXX, kopie zonder kijkactie).
  /// The same closed schema, so the same negotiation.
  final bool watchStateCopy;

  /// The server knows `POST /auth/stream-session` and the `ss` parameter on
  /// `/stream`. For browsers; this app authorises its player with a header.
  final bool streamSessions;

  /// The server binds a session to a device (DEC-123): `device_id` and
  /// `device_name` are accepted on login and setup, `GET`/`DELETE /sessions`
  /// and `POST /auth/logout` exist, and revoking a session takes effect within
  /// two seconds even for a stream already in flight.
  ///
  /// Sending the device fields to a server without this flag is refused whole:
  /// `LoginRequest` and `SetupRequest` are closed schemas. That is the reason
  /// this is negotiated rather than assumed.
  final bool sessions;

  /// The server has its admin surface (settings, diagnostics, audit). The
  /// app reads it as "offer server administration at all"; the server still
  /// refuses every admin route with a 404 for whoever is not an admin.
  final bool administration;

  /// `POST /libraries/{id}/empty-trash` and `/refresh-metadata` exist
  /// (chapter 17f, proposal). Without it a library offers only the scan.
  final bool libraryMaintenance;

  /// `POST /items/{id}/watch-state` marks an item and everything below it in
  /// one transaction (chapter 14.1c). Without it a season or show is marked
  /// one episode at a time.
  final bool watchStateTree;

  /// `POST /items/{id}/refresh-metadata` exists for an admin (chapter 17f).
  final bool itemMetadataRefresh;

  /// `Library.next_scan_at` is on every library an admin reads (chapter 17f).
  final bool scanSchedule;

  /// `DELETE /items/{id}` erases a title and its files from storage (chapter
  /// 17h). Only true when the server admin switched it on and a media root was
  /// measured writable at startup; absent means off.
  final bool mediaDelete;
  final bool mcp;

  factory PleyaCapabilities.fromJson(Map<String, dynamic> json) => PleyaCapabilities(
    browse: boolean(json, 'browse'),
    search: boolean(json, 'search'),
    artwork: boolean(json, 'artwork'),
    watchState: boolean(json, 'watch_state'),
    playbackPlan: booleanOr(json, 'playback_plan', orElse: false),
    playbackQuality: booleanOr(json, 'playback_quality', orElse: false),
    playbackAudioSelection: booleanOr(json, 'playback_audio_selection', orElse: false),
    playbackStartPosition: booleanOr(json, 'playback_start_position', orElse: false),
    embeddedSubtitles: booleanOr(json, 'embedded_subtitles', orElse: false),
    playbackSubtitles: booleanOr(json, 'playback_subtitles', orElse: false),
    history: booleanOr(json, 'history', orElse: false),
    favorites: booleanOr(json, 'favorites', orElse: false),
    ratings: booleanOr(json, 'ratings', orElse: false),
    trackPreferences: booleanOr(json, 'track_preferences', orElse: false),
    collections: booleanOr(json, 'collections', orElse: false),
    playlists: booleanOr(json, 'playlists', orElse: false),
    itemActivity: booleanOr(json, 'item_activity', orElse: false),
    assistantMemory: booleanOr(json, 'assistant_memory', orElse: false),
    pushNotifications: booleanOr(json, 'push_notifications', orElse: false),
    pushRichContent: booleanOr(json, 'push_rich_content', orElse: false),
    transcode: booleanOr(json, 'transcode', orElse: false),
    downloads: booleanOr(json, 'downloads', orElse: false),
    liveTv: booleanOr(json, 'live_tv', orElse: false),
    realtime: booleanOr(json, 'realtime', orElse: false),
    artworkSizes: booleanOr(json, 'artwork_sizes', orElse: false),
    filters: booleanOr(json, 'filters', orElse: false),
    externalIdLookup: booleanOr(json, 'external_id_lookup', orElse: false),
    appliedExternalIdentity: booleanOr(json, 'applied_external_identity', orElse: false),
    metadataMatchStatus: booleanOr(json, 'metadata_match_status', orElse: false),
    watchStateOwnership: booleanOr(json, 'watch_state_ownership', orElse: false),
    watchStateCopy: booleanOr(json, 'watch_state_copy', orElse: false),
    streamSessions: booleanOr(json, 'stream_sessions', orElse: false),
    users: booleanOr(json, 'users', orElse: false),
    sessions: booleanOr(json, 'sessions', orElse: false),
    administration: booleanOr(json, 'administration', orElse: false),
    libraryMaintenance: booleanOr(json, 'library_maintenance', orElse: false),
    watchStateTree: booleanOr(json, 'watch_state_tree', orElse: false),
    itemMetadataRefresh: booleanOr(json, 'item_metadata_refresh', orElse: false),
    scanSchedule: booleanOr(json, 'scan_schedule', orElse: false),
    mediaDelete: booleanOr(json, 'media_delete', orElse: false),
    mcp: booleanOr(json, 'mcp', orElse: false),
  );
}
