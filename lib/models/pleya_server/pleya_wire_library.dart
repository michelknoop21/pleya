/// Library-side wire types for Pleya Protocol v1: libraries, items, versions,
/// streams and pages. Split from `pleya_wire.dart` so neither file grows past
/// what fits in one reading.
library;

import 'pleya_wire.dart';
import 'pleya_wire_parse.dart';

/// `Library`.
class PleyaLibrary {
  const PleyaLibrary({required this.id, required this.title, required this.kind, required this.itemCount});

  final String id;
  final String title;

  /// Null when the server named a kind this build does not know. Unknown-safe:
  /// the caller hides the library and carries on.
  final PleyaLibraryKind? kind;

  final int itemCount;

  factory PleyaLibrary.fromJson(Map<String, dynamic> json) => PleyaLibrary(
    id: str(json, 'id'),
    title: str(json, 'title'),
    kind: PleyaLibraryKind.tryParse(strOrNull(json, 'kind')),
    itemCount: integer(json, 'item_count'),
  );

  /// `LibraryList`. Libraries with an unknown kind stay in the list; deciding
  /// to hide them is a caller's job, not the parser's.
  static List<PleyaLibrary> listFromJson(Map<String, dynamic> json) => [
    for (final item in objectList(json['items'], 'items')) PleyaLibrary.fromJson(item),
  ];
}

/// `Artwork`. Ids of images that exist; null where there is none.
class PleyaArtwork {
  const PleyaArtwork({this.posterId, this.backdropId});

  static const PleyaArtwork none = PleyaArtwork();

  final String? posterId;
  final String? backdropId;

  factory PleyaArtwork.fromJson(Map<String, dynamic> json) =>
      PleyaArtwork(posterId: strOrNull(json, 'poster_id'), backdropId: strOrNull(json, 'backdrop_id'));
}

/// `VideoStream`.
class PleyaVideoStream {
  const PleyaVideoStream({
    required this.id,
    required this.index,
    required this.codec,
    this.profile,
    this.width,
    this.height,
    this.bitDepth,
    this.frameRate,
  });

  final String id;
  final int index;
  final String codec;
  final String? profile;
  final int? width;
  final int? height;
  final int? bitDepth;
  final double? frameRate;

  factory PleyaVideoStream.fromJson(Map<String, dynamic> json) => PleyaVideoStream(
    id: str(json, 'id'),
    index: integer(json, 'index'),
    codec: str(json, 'codec'),
    profile: strOrNull(json, 'profile'),
    width: integerOrNull(json, 'width'),
    height: integerOrNull(json, 'height'),
    bitDepth: integerOrNull(json, 'bit_depth'),
    frameRate: doubleOrNull(json, 'frame_rate'),
  );
}

/// `AudioStream`.
class PleyaAudioStream {
  const PleyaAudioStream({
    required this.id,
    required this.index,
    required this.codec,
    this.channels,
    this.language,
    this.title,
    this.isDefault = false,
  });

  final String id;
  final int index;
  final String codec;
  final int? channels;

  /// ISO 639-2/B in three letters, or null.
  final String? language;

  final String? title;
  final bool isDefault;

  factory PleyaAudioStream.fromJson(Map<String, dynamic> json) => PleyaAudioStream(
    id: str(json, 'id'),
    index: integer(json, 'index'),
    codec: str(json, 'codec'),
    channels: integerOrNull(json, 'channels'),
    language: strOrNull(json, 'language'),
    title: strOrNull(json, 'title'),
    isDefault: booleanOr(json, 'is_default', orElse: false),
  );
}

/// `SubtitleStream`. Two shapes with one field set: external has a url and no
/// index, embedded has an index and no url.
class PleyaSubtitleStream {
  const PleyaSubtitleStream({
    required this.id,
    required this.format,
    required this.isExternal,
    required this.isForced,
    required this.isHearingImpaired,
    this.index,
    this.language,
    this.title,
    this.isDefault = false,
    this.url,
  });

  final String id;

  /// Null when the server named a format this build cannot render.
  /// Unknown-safe: the caller leaves the track out of the picker.
  final PleyaSubtitleFormat? format;

  final bool isExternal;

  /// Explicit on the wire, never derived from the title.
  final bool isForced;

  /// Explicit on the wire, never derived from the title.
  final bool isHearingImpaired;

  final int? index;
  final String? language;
  final String? title;
  final bool isDefault;

  /// Server-relative path for an external track, e.g.
  /// `/pleya/v1/subtitles/{id}`. Null for embedded tracks.
  final String? url;

  factory PleyaSubtitleStream.fromJson(Map<String, dynamic> json) => PleyaSubtitleStream(
    id: str(json, 'id'),
    format: PleyaSubtitleFormat.tryParse(strOrNull(json, 'format')),
    isExternal: boolean(json, 'is_external'),
    isForced: boolean(json, 'is_forced'),
    isHearingImpaired: boolean(json, 'is_hearing_impaired'),
    index: integerOrNull(json, 'index'),
    language: strOrNull(json, 'language'),
    title: strOrNull(json, 'title'),
    isDefault: booleanOr(json, 'is_default', orElse: false),
    url: strOrNull(json, 'url'),
  );
}

/// `Version`. One cut of a title, possibly spread over several files.
class PleyaVersion {
  const PleyaVersion({
    required this.id,
    required this.container,
    required this.durationMs,
    required this.fileCount,
    this.edition,
    this.videoStreams = const [],
    this.audioStreams = const [],
    this.subtitleStreams = const [],
  });

  final String id;
  final String container;
  final int durationMs;

  /// A version may span several files. Direct play accepts only 1 in v1, but
  /// the domain model allows more and the client must not pretend otherwise.
  final int fileCount;

  /// For example "Director's Cut". Distinguishes two cuts of one title.
  final String? edition;

  final List<PleyaVideoStream> videoStreams;
  final List<PleyaAudioStream> audioStreams;
  final List<PleyaSubtitleStream> subtitleStreams;

  factory PleyaVersion.fromJson(Map<String, dynamic> json) => PleyaVersion(
    id: str(json, 'id'),
    container: str(json, 'container'),
    durationMs: integer(json, 'duration_ms'),
    fileCount: integer(json, 'file_count'),
    edition: strOrNull(json, 'edition'),
    videoStreams: [for (final s in objectList(json['video_streams'], 'video_streams')) PleyaVideoStream.fromJson(s)],
    audioStreams: [for (final s in objectList(json['audio_streams'], 'audio_streams')) PleyaAudioStream.fromJson(s)],
    subtitleStreams: [
      for (final s in objectList(json['subtitle_streams'], 'subtitle_streams')) PleyaSubtitleStream.fromJson(s),
    ],
  );
}

/// `UserState`. Rides along in every item answer so a detail screen needs no
/// second request.
class PleyaUserState {
  const PleyaUserState({
    required this.positionMs,
    required this.watched,
    required this.playCount,
    required this.updatedAt,
    this.revision,
    this.ownedByThisSession,
  });

  final int positionMs;
  final bool watched;
  final int playCount;
  final DateTime updatedAt;

  /// Server-issued and monotonic. The client stores the last one it saw and
  /// sends it back as `base_revision`, which is how the server tells an event
  /// that acted on the current state apart from one that acted on a stale
  /// view. Null on a server without `watch_state_ownership`.
  final int? revision;

  /// Whether the session that sent the event may still write the canonical
  /// position. Only present in the answer to `POST /watch-state`: an item
  /// answer has no session to answer the question about.
  final bool? ownedByThisSession;

  factory PleyaUserState.fromJson(Map<String, dynamic> json) => PleyaUserState(
    positionMs: integer(json, 'position_ms'),
    watched: boolean(json, 'watched'),
    playCount: integer(json, 'play_count'),
    updatedAt: timestamp(json, 'updated_at'),
    revision: integerOrNull(json, 'revision'),
    ownedByThisSession: booleanOrNull(json, 'owned_by_this_session'),
  );
}

/// `Item`.
class PleyaItem {
  const PleyaItem({
    required this.id,
    required this.kind,
    required this.title,
    required this.addedAt,
    this.sortTitle,
    this.year,
    this.durationMs,
    this.parentId,
    this.index,
    this.childCount,
    this.episodeCount,
    this.watchedEpisodeCount,
    this.artwork = PleyaArtwork.none,
    this.versions = const [],
    this.userState,
  });

  final String id;

  /// Null when the server named a kind this build does not know. Unknown-safe:
  /// [pageFromJson] drops those items instead of failing the whole page.
  final PleyaItemKind? kind;

  final String title;
  final DateTime addedAt;
  final String? sortTitle;
  final int? year;
  final int? durationMs;
  final String? parentId;

  /// Season or episode number.
  final int? index;

  final int? childCount;
  final int? episodeCount;
  final int? watchedEpisodeCount;
  final PleyaArtwork artwork;
  final List<PleyaVersion> versions;
  final PleyaUserState? userState;

  factory PleyaItem.fromJson(Map<String, dynamic> json) {
    final artwork = json['artwork'];
    final userState = json['user_state'];
    return PleyaItem(
      id: str(json, 'id'),
      kind: PleyaItemKind.tryParse(strOrNull(json, 'kind')),
      title: str(json, 'title'),
      addedAt: timestamp(json, 'added_at'),
      sortTitle: strOrNull(json, 'sort_title'),
      year: integerOrNull(json, 'year'),
      durationMs: integerOrNull(json, 'duration_ms'),
      parentId: strOrNull(json, 'parent_id'),
      index: integerOrNull(json, 'index'),
      childCount: integerOrNull(json, 'child_count'),
      episodeCount: integerOrNull(json, 'episode_count'),
      watchedEpisodeCount: integerOrNull(json, 'watched_episode_count'),
      artwork: artwork is Map<String, dynamic> ? PleyaArtwork.fromJson(artwork) : PleyaArtwork.none,
      versions: [for (final v in objectList(json['versions'], 'versions')) PleyaVersion.fromJson(v)],
      userState: userState is Map<String, dynamic> ? PleyaUserState.fromJson(userState) : null,
    );
  }
}

/// `ItemPage`: a page of items plus the cursor for the next one.
class PleyaItemPage {
  const PleyaItemPage({required this.items, this.nextCursor, this.totalEstimate});

  static const PleyaItemPage empty = PleyaItemPage(items: []);

  final List<PleyaItem> items;

  /// Null on the last page. Opaque, and tied to the sort it was issued for.
  final String? nextCursor;

  /// Explicitly an estimate, so a scrollbar can be drawn without the server
  /// counting per page. Never shown as an exact number.
  final int? totalEstimate;

  bool get hasMore => nextCursor != null;

  /// Items of a kind this build knows. The contract says a client that does
  /// not know a kind hides the item and does not fail, so the drop happens
  /// here rather than at every call site.
  List<PleyaItem> get knownItems => [
    for (final item in items)
      if (item.kind != null) item,
  ];

  factory PleyaItemPage.fromJson(Map<String, dynamic> json) => PleyaItemPage(
    items: [for (final item in objectList(json['items'], 'items')) PleyaItem.fromJson(item)],
    nextCursor: strOrNull(json, 'next_cursor'),
    totalEstimate: integerOrNull(json, 'total_estimate'),
  );
}

/// `WatchStateEvent`, the write side of watch state.
///
/// A typed body rather than a map at the call site, because the schema is
/// closed (`additionalProperties: false`): a stray key does not get ignored,
/// it gets the whole request refused. Building it in one place means the three
/// ownership fields from DEC-049 are decided once, and the contract test can
/// hold this type against the same fixtures the server validates against.
class PleyaWatchStateEvent {
  const PleyaWatchStateEvent({
    required this.itemId,
    required this.sessionId,
    required this.positionMs,
    required this.occurredAt,
    this.durationMs,
    this.completed = false,
    this.action = 'none',
    this.cause,
    this.baseRevision,
    this.backlog = false,
  });

  final String itemId;
  final String sessionId;
  final int positionMs;
  final DateTime occurredAt;
  final int? durationMs;
  final bool completed;
  final String action;

  /// Only meaningful with `playback_started`, and only sendable when the server
  /// advertises `watch_state_ownership`.
  final String? cause;

  /// The revision this client based its view on. Null means no causal claim,
  /// which is not the same as zero: zero claims there is no state yet.
  final int? baseRevision;

  /// This event comes out of an offline queue. A backlog never acquires
  /// ownership and never moves a newer canonical state.
  final bool backlog;

  /// The body as the contract wants it.
  ///
  /// [ownership] is the server's `watch_state_ownership` flag. When it is false
  /// the three newer fields are left out entirely and `playback_started` falls
  /// back to `none`: an older server does not know the enum value and refuses
  /// the request rather than ignoring it.
  Map<String, dynamic> toJson({required bool ownership}) => {
    'item_id': itemId,
    'session_id': sessionId,
    'position_ms': positionMs < 0 ? 0 : positionMs,
    if (durationMs != null) 'duration_ms': durationMs,
    'occurred_at': _rfc3339(occurredAt),
    'completed': completed,
    'explicit_action': ownership || action != 'playback_started' ? action : 'none',
    if (ownership && cause != null && action == 'playback_started') 'cause': cause,
    if (ownership && backlog) 'backlog': true,
    if (ownership && baseRevision != null) 'base_revision': baseRevision,
  };

  factory PleyaWatchStateEvent.fromJson(Map<String, dynamic> json) => PleyaWatchStateEvent(
    itemId: str(json, 'item_id'),
    sessionId: str(json, 'session_id'),
    positionMs: integer(json, 'position_ms'),
    occurredAt: timestamp(json, 'occurred_at'),
    durationMs: integerOrNull(json, 'duration_ms'),
    completed: booleanOr(json, 'completed', orElse: false),
    action: str(json, 'explicit_action'),
    cause: strOrNull(json, 'cause'),
    baseRevision: integerOrNull(json, 'base_revision'),
    backlog: booleanOr(json, 'backlog', orElse: false),
  );

  /// RFC 3339 in UTC with a `Z` suffix, per chapter 2 of the specification.
  static String _rfc3339(DateTime value) => '${value.toUtc().toIso8601String().split('.').first.replaceAll('Z', '')}Z';
}

/// `StreamSession`, the answer to `POST /auth/stream-session`.
///
/// Carries only the non-secret half; the secret rides in a cookie. This app
/// does not open stream sessions (its player sets a header), so the type exists
/// to keep the fixture under contract rather than to be called.
class PleyaStreamSession {
  const PleyaStreamSession({required this.streamSessionId, required this.expiresAt});

  final String streamSessionId;
  final DateTime expiresAt;

  factory PleyaStreamSession.fromJson(Map<String, dynamic> json) =>
      PleyaStreamSession(streamSessionId: str(json, 'stream_session_id'), expiresAt: timestamp(json, 'expires_at'));
}

/// `WatchStateEntry`, read side. PS-3 does not call the watch-state endpoints;
/// the type is here because the contract test walks every fixture in the
/// manifest, and a fixture without a type would silently go unchecked.
class PleyaWatchStateEntry {
  const PleyaWatchStateEntry({required this.itemId, required this.state});

  final String itemId;
  final PleyaUserState state;

  factory PleyaWatchStateEntry.fromJson(Map<String, dynamic> json) =>
      PleyaWatchStateEntry(itemId: str(json, 'item_id'), state: PleyaUserState.fromJson(obj(json['state'], 'state')));

  /// `WatchStatePage`.
  static List<PleyaWatchStateEntry> pageFromJson(Map<String, dynamic> json) => [
    for (final entry in objectList(json['items'], 'items')) PleyaWatchStateEntry.fromJson(entry),
  ];
}
