/// Hand-written wire types for Pleya Protocol v1.
///
/// `docs/pleya-protocol/v1/openapi.yaml` is contractually leading; these
/// classes are a transcription of it and nothing more. They carry no app
/// semantics, no defaults the server did not send, and no fields the contract
/// does not name. Mapping to the app's neutral domain model happens one layer
/// up, in `PleyaServerMappers`.
///
/// ## Why by hand
///
/// Pleya Web generates its TypeScript client from the same YAML, and the
/// obvious symmetry would be a Dart generator. There is no maintained one that
/// fits this build, and adding a code generator to the Flutter toolchain is new
/// infrastructure without a demonstrated need, which chapter 23.1 of the
/// architecture forbids. The safety net is instead a contract test that reads
/// the 25 fixtures under `docs/pleya-protocol/v1/examples/` and the manifest
/// that assigns each one a schema, so a field that drifts fails a test rather
/// than a screen.
///
/// ## Unknown values
///
/// Four fields are marked `x-unknown-safe` in the contract: `auth.methods[]`,
/// `Library.kind`, `Item.kind` and `SubtitleStream.format`. Those parse into a
/// nullable value and never throw, because a v1 server is allowed to add a
/// value there. Every other enum is closed, and an unexpected value there is a
/// protocol violation rather than a forward-compatible extension.
library;

import 'pleya_wire_parse.dart';

part 'pleya_wire_capabilities.dart';

/// Thrown when a response does not match the contract in a way the client
/// cannot recover from: a required field is missing, or a field carries a type
/// the contract does not allow.
///
/// Deliberately not thrown for an unknown enum value on an unknown-safe field.
/// That is a forward-compatible server, not a broken one.
class PleyaWireFormatException implements Exception {
  PleyaWireFormatException(this.message);

  final String message;

  @override
  String toString() => 'PleyaWireFormatException: $message';
}

// ---------------------------------------------------------------------------
// Enums
// ---------------------------------------------------------------------------

/// `LibraryKind`, unknown-safe. Null means the server named a kind this build
/// does not know; the caller hides that library rather than failing.
enum PleyaLibraryKind {
  movies,
  shows;

  static PleyaLibraryKind? tryParse(String? raw) => switch (raw) {
    'movies' => PleyaLibraryKind.movies,
    'shows' => PleyaLibraryKind.shows,
    _ => null,
  };
}

/// `ItemKind`, unknown-safe. Null means the server named a kind this build does
/// not know; the caller drops that item rather than failing.
enum PleyaItemKind {
  movie,
  show,
  season,
  episode;

  String get wire => name;

  static PleyaItemKind? tryParse(String? raw) => switch (raw) {
    'movie' => PleyaItemKind.movie,
    'show' => PleyaItemKind.show,
    'season' => PleyaItemKind.season,
    'episode' => PleyaItemKind.episode,
    _ => null,
  };
}

/// `SubtitleStream.format`, unknown-safe. Null means a format this build cannot
/// offer; the caller leaves that track out of the picker rather than failing.
enum PleyaSubtitleFormat {
  srt,
  ass,
  ssa,
  vtt,
  pgs,
  dvdsub;

  static PleyaSubtitleFormat? tryParse(String? raw) => switch (raw) {
    'srt' => PleyaSubtitleFormat.srt,
    'ass' => PleyaSubtitleFormat.ass,
    'ssa' => PleyaSubtitleFormat.ssa,
    'vtt' => PleyaSubtitleFormat.vtt,
    'pgs' => PleyaSubtitleFormat.pgs,
    'dvdsub' => PleyaSubtitleFormat.dvdsub,
    _ => null,
  };
}

/// Sort keys `GET /libraries/{id}/items` accepts. Closed: the contract lists
/// the literal values (each with its `-` twin) and marks the field
/// `x-unknown-safe: false`, so this is the whole set a client may send.
/// `lastPlayedAt` and `duration` exist only under `capabilities.filters`.
enum PleyaSortKey {
  title('title'),
  addedAt('added_at'),
  year('year'),
  lastPlayedAt('last_played_at'),
  duration('duration');

  const PleyaSortKey(this.wire);

  final String wire;

  /// A leading minus reverses the order, which is how the contract spells
  /// descending. There is no separate direction parameter.
  String query({required bool descending}) => descending ? '-$wire' : wire;
}

/// The three hub ids the contract defines. Closed, so a client cannot invent
/// a fourth and hope.
enum PleyaHubId {
  recentlyAdded('recently_added'),
  continueWatching('continue_watching'),
  nextUp('next_up');

  const PleyaHubId(this.wire);

  final String wire;
}

// ---------------------------------------------------------------------------
// Discovery and auth
// ---------------------------------------------------------------------------

/// `TrackPreference`: the audio and subtitle choice remembered for a title.
/// [sourceItemId] names the item it was set on, which is an ancestor when the
/// choice carried over from a show to its episodes.
class PleyaTrackPreference {
  const PleyaTrackPreference({this.sourceItemId, this.audioLanguage, this.subtitleLanguage, this.subtitleMode});

  final String? sourceItemId;
  final String? audioLanguage;
  final String? subtitleLanguage;

  /// `off`, `on` or `forced`; null when no choice is remembered.
  final String? subtitleMode;

  factory PleyaTrackPreference.fromJson(Map<String, dynamic> json) => PleyaTrackPreference(
    sourceItemId: json['source_item_id'] as String?,
    audioLanguage: json['audio_language'] as String?,
    subtitleLanguage: json['subtitle_language'] as String?,
    subtitleMode: json['subtitle_mode'] as String?,
  );
}

/// `Download`: a file the server prepared for the requester to take offline.
/// [status] is `preparing` while the server computes the digest, then `ready`
/// or `failed`; [sizeBytes] and [sha256] are null until it is ready.
class PleyaDownload {
  const PleyaDownload({
    required this.id,
    required this.itemId,
    required this.versionId,
    required this.status,
    required this.fileUrl,
    this.sizeBytes,
    this.sha256,
  });

  final String id;
  final String itemId;
  final String versionId;
  final String status;
  final String fileUrl;
  final int? sizeBytes;
  final String? sha256;

  bool get isReady => status == 'ready';
  bool get isFailed => status == 'failed';

  factory PleyaDownload.fromJson(Map<String, dynamic> json) => PleyaDownload(
    id: str(json, 'id'),
    itemId: str(json, 'item_id'),
    versionId: str(json, 'version_id'),
    status: str(json, 'status'),
    fileUrl: str(json, 'file_url'),
    sizeBytes: integerOrNull(json, 'size_bytes'),
    sha256: strOrNull(json, 'sha256'),
  );
}

/// `Info.auth`.
class PleyaAuthInfo {
  const PleyaAuthInfo({required this.methods, required this.setupRequired});

  /// Method names the server offers. Unknown-safe: a name this build does not
  /// know is kept as a raw string so a caller can skip it and pick one it does
  /// know, which is exactly what the contract prescribes.
  final List<String> methods;

  final bool setupRequired;

  bool get supportsPassword => methods.contains('password');

  factory PleyaAuthInfo.fromJson(Map<String, dynamic> json) {
    final raw = json['methods'];
    if (raw is! List) fail('auth.methods is missing or not an array');
    return PleyaAuthInfo(
      methods: [
        for (final method in raw)
          if (method is String) method,
      ],
      setupRequired: boolean(json, 'setup_required'),
    );
  }
}

/// `Info`. Public, so it deliberately carries no server name, version or build
/// number; those live behind auth in `GET /server`.
class PleyaInfo {
  const PleyaInfo({
    required this.major,
    required this.featureLevel,
    required this.profile,
    required this.serverId,
    required this.capabilities,
    required this.auth,
  });

  final int major;
  final int featureLevel;

  /// `minimal` or `full`. Closed enum, kept as a string because nothing in the
  /// client branches on it; `capabilities` is what decides.
  final String profile;

  final String serverId;
  final PleyaCapabilities capabilities;
  final PleyaAuthInfo auth;

  factory PleyaInfo.fromJson(Map<String, dynamic> json) {
    final protocol = obj(json['protocol'], 'protocol');
    final server = obj(json['server'], 'server');
    return PleyaInfo(
      major: integer(protocol, 'major'),
      featureLevel: integer(protocol, 'feature_level'),
      profile: str(protocol, 'profile'),
      serverId: str(server, 'id'),
      capabilities: PleyaCapabilities.fromJson(obj(json['capabilities'], 'capabilities')),
      auth: PleyaAuthInfo.fromJson(obj(json['auth'], 'auth')),
    );
  }
}

/// `ServerDetail`. Behind auth.
class PleyaServerDetail {
  const PleyaServerDetail({required this.id, required this.name, required this.version, required this.startedAt});

  final String id;
  final String name;
  final String version;
  final DateTime startedAt;

  factory PleyaServerDetail.fromJson(Map<String, dynamic> json) => PleyaServerDetail(
    id: str(json, 'id'),
    name: str(json, 'name'),
    version: str(json, 'version'),
    startedAt: timestamp(json, 'started_at'),
  );
}

/// `TokenPair`. The refresh token rotates on every use and the old one dies
/// immediately, so a caller must persist the new one before the next call.
class PleyaTokenPair {
  const PleyaTokenPair({required this.accessToken, required this.refreshToken, required this.expiresInMs});

  final String accessToken;
  final String refreshToken;
  final int expiresInMs;

  factory PleyaTokenPair.fromJson(Map<String, dynamic> json) => PleyaTokenPair(
    accessToken: str(json, 'access_token'),
    refreshToken: str(json, 'refresh_token'),
    expiresInMs: integer(json, 'expires_in_ms'),
  );
}

/// `User`, as returned by `GET /users/me`.
class PleyaUser {
  const PleyaUser({required this.id, required this.username, required this.role});

  final String id;
  final String username;
  final String role;

  factory PleyaUser.fromJson(Map<String, dynamic> json) =>
      PleyaUser(id: str(json, 'id'), username: str(json, 'username'), role: str(json, 'role'));
}

/// `UserList`, the answer of `GET /users`. An admin gets every account; a
/// member gets only itself.
List<PleyaUser> pleyaUsersFromJson(Map<String, dynamic> json) => [
  for (final item in objectList(json['items'], 'items')) PleyaUser.fromJson(item),
];

/// `Job`, one row of `GET /jobs`. A scan is a job of kind `scan_library` and
/// then carries [libraryId] and [scanId].
class PleyaJob {
  const PleyaJob({
    required this.id,
    required this.kind,
    required this.state,
    required this.createdAt,
    this.lastError,
    this.finishedAt,
    this.libraryId,
  });

  final String id;
  final String kind;

  /// `pending`, `running`, `succeeded`, `failed` or `cancelled`. Kept as text:
  /// the mapper decides what an unrecognised value means.
  final String state;
  final DateTime createdAt;
  final String? lastError;
  final DateTime? finishedAt;
  final String? libraryId;

  factory PleyaJob.fromJson(Map<String, dynamic> json) => PleyaJob(
    id: str(json, 'id'),
    kind: str(json, 'kind'),
    state: str(json, 'state'),
    createdAt: timestamp(json, 'created_at'),
    lastError: strOrNull(json, 'last_error'),
    finishedAt: json['finished_at'] == null ? null : timestamp(json, 'finished_at'),
    libraryId: strOrNull(json, 'library_id'),
  );

  /// `JobPage.items`.
  static List<PleyaJob> listFromJson(Map<String, dynamic> json) => [
    for (final item in objectList(json['items'], 'items')) PleyaJob.fromJson(item),
  ];
}

/// `StreamToken`. Short-lived, bound to one media resource, and explicitly not
/// single-use: a player does a HEAD, an open range, one range per seek, plus
/// retries.
class PleyaStreamToken {
  const PleyaStreamToken({required this.streamToken, required this.expiresAt});

  final String streamToken;
  final DateTime expiresAt;

  factory PleyaStreamToken.fromJson(Map<String, dynamic> json) =>
      PleyaStreamToken(streamToken: str(json, 'stream_token'), expiresAt: timestamp(json, 'expires_at'));
}

/// `ErrorEnvelope`. `retryable` is explicit rather than derived from the status
/// code, because a 503 is sometimes not worth repeating and a 409 sometimes is.
class PleyaError {
  const PleyaError({required this.code, required this.message, required this.retryable, this.details});

  /// Stable machine-readable code, `domain.reason`. The client branches on
  /// this and never on [message], which is for logs.
  final String code;

  final String message;
  final bool retryable;
  final Map<String, dynamic>? details;

  /// Domain half of [code]: auth, library, playback, session, settings,
  /// storage, server or job. The list is not closed. It grows one protocol
  /// window at a time, so treat an unfamiliar domain as an unfamiliar
  /// code and fall back to the generic message instead of branching.
  String get domain => code.split('.').first;

  /// `details.retry_after_ms` on a rate-limit answer. Null when the server did
  /// not say, which is not the same as zero.
  int? get retryAfterMs {
    final value = details?['retry_after_ms'];
    return value is int ? value : null;
  }

  factory PleyaError.fromJson(Map<String, dynamic> json) {
    final error = obj(json['error'], 'error');
    final details = error['details'];
    return PleyaError(
      code: str(error, 'code'),
      message: str(error, 'message'),
      retryable: boolean(error, 'retryable'),
      details: details is Map<String, dynamic> ? details : null,
    );
  }

  /// Parse a response body that is expected to be an error envelope. Returns
  /// null rather than throwing: an error path that throws while parsing the
  /// error hides the original failure.
  static PleyaError? tryParse(Object? body) {
    if (body is! Map<String, dynamic>) return null;
    try {
      return PleyaError.fromJson(body);
    } on PleyaWireFormatException {
      return null;
    }
  }
}
