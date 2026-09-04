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
/// six literal values and marks the field `x-unknown-safe: false`, so this is
/// the whole set a client may send.
enum PleyaSortKey {
  title('title'),
  addedAt('added_at'),
  year('year');

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

/// `Capabilities`. Always leading over `feature_level`, per the contract.
///
/// The four required flags have no default; the six optional ones default to
/// false, which is what the contract says and also the only safe reading of a
/// server that stays silent about a feature.
class PleyaCapabilities {
  const PleyaCapabilities({
    required this.browse,
    required this.search,
    required this.artwork,
    required this.watchState,
    this.playbackPlan = false,
    this.transcode = false,
    this.downloads = false,
    this.liveTv = false,
    this.realtime = false,
    this.users = false,
    this.watchStateOwnership = false,
    this.streamSessions = false,
    this.sessions = false,
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
  final bool transcode;
  final bool downloads;
  final bool liveTv;
  final bool realtime;
  final bool users;

  /// The server knows the ownership model: `base_revision`, the
  /// `playback_started` acquisition and the backlog marker on a watch-state
  /// event. `WatchStateEvent` is a closed schema, so a client that sends those
  /// fields to a server without this flag gets its whole request refused.
  final bool watchStateOwnership;

  /// The server knows `POST /auth/stream-session` and the `ss` parameter on
  /// `/stream`. For browsers; this app authorises its player with a header.
  final bool streamSessions;

  /// The server binds a session to a device (DEC-102): `device_id` and
  /// `device_name` are accepted on login and setup, `GET`/`DELETE /sessions`
  /// and `POST /auth/logout` exist, and revoking a session takes effect within
  /// two seconds even for a stream already in flight.
  ///
  /// Sending the device fields to a server without this flag is refused whole:
  /// `LoginRequest` and `SetupRequest` are closed schemas. That is the reason
  /// this is negotiated rather than assumed.
  final bool sessions;

  factory PleyaCapabilities.fromJson(Map<String, dynamic> json) => PleyaCapabilities(
    browse: boolean(json, 'browse'),
    search: boolean(json, 'search'),
    artwork: boolean(json, 'artwork'),
    watchState: boolean(json, 'watch_state'),
    playbackPlan: booleanOr(json, 'playback_plan', orElse: false),
    transcode: booleanOr(json, 'transcode', orElse: false),
    downloads: booleanOr(json, 'downloads', orElse: false),
    liveTv: booleanOr(json, 'live_tv', orElse: false),
    realtime: booleanOr(json, 'realtime', orElse: false),
    watchStateOwnership: booleanOr(json, 'watch_state_ownership', orElse: false),
    streamSessions: booleanOr(json, 'stream_sessions', orElse: false),
    users: booleanOr(json, 'users', orElse: false),
    sessions: booleanOr(json, 'sessions', orElse: false),
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

  /// Domain half of [code], one of auth, library, playback, session, storage.
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
