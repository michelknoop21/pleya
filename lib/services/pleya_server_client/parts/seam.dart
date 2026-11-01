part of '../../pleya_server_client.dart';

/// What the shell provides to the parts.
///
/// Declared in one place rather than repeated per part, so the three feature
/// mixins agree on the signature by construction instead of by care. A part
/// that needs something new adds it here, and the compiler points at the shell
/// until it is there.
mixin _PleyaServerRequests {
  ServerId get serverId;
  ApiCache get cache;
  bool get _closed;
  String? get serverName;
  PleyaServerConnection get connection;
  PleyaServerSession get _session;
  PleyaServerCursorLedger get _cursors;
  PleyaServerWatchLedger get _watchLedger;

  /// Capabilities as the server last reported them. Every call in a part gates
  /// on this: an endpoint the server says it does not have is not worth a
  /// round-trip, and the answer would be a 404 the UI has to interpret.
  PleyaCapabilities get wireCapabilities;
  bool get identityCapabilitiesKnown;
  String get externalIdentitySource;

  bool get isOfflineMode;

  /// Re-read the signed-in role from the server. True when that worked.
  Future<bool> _refreshRole();

  Future<MediaServerResponse> _getSubtitle(String subtitleId, AbortController abort);

  Future<Map<String, String>> _downloadHeaders() async {
    if (_closed) throw StateError('The download connection is closed.');
    final headers = await _session.authHeaders();
    if (_closed) throw StateError('The download connection is closed.');
    return headers;
  }

  /// GET a protocol path and hand back its JSON object, or null.
  Future<Map<String, dynamic>?> _getJson(String path, {Map<String, dynamic>? queryParameters, Duration? timeout});

  /// [_getJson] plus the protocol error code of a failed answer, or null when
  /// there was none (offline, transport failure, or success).
  Future<({Map<String, dynamic>? json, String? errorCode})> _getJsonDetailed(
    String path, {
    Map<String, dynamic>? queryParameters,
    Duration? timeout,
    AbortController? abort,
  });

  /// POST a protocol path with a JSON body and hand back its JSON object. A
  /// failed write throws; only offline mode answers null.
  Future<Map<String, dynamic>?> _postJson(String path, Map<String, dynamic> body);

  /// Send a request that answers with JSON, nothing, or 202/204. Retries once
  /// on a 401 and throws on anything else outside 2xx. The playback part uses
  /// it for the transcode-session calls.
  Future<Map<String, dynamic>?> _adminSend(String method, String path, {Map<String, dynamic>? body});

  /// One item by id. The playback part needs it to turn watch-state rows back
  /// into items, and the browse part already implements it.
  Future<MediaItem?> fetchItem(String id);
}
