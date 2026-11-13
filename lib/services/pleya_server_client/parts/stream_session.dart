part of '../../pleya_server_client.dart';

/// A stream session as the native player holds it: the non-secret id for the
/// URL and the secret for the cookie (DEC-051).
typedef _PleyaStreamSession = ({String id, String secret});

/// What the native player opens a Pleya stream with.
typedef _PleyaPlayerCredential = ({
  String sessionId,
  Map<String, String> headers,
  String? subtitleToken,
  void Function() hold,
  void Function() release,
});

/// The credential mpv gets for a Pleya stream.
///
/// mpv receives its headers once, at open, and replays them on every reconnect
/// and seek for as long as the film runs. An access token lives fifteen
/// minutes, so a reconnect after that came back 401 and the buffer ran dry
/// (Apple TV, build 462). A stream session does not age while it is used: the
/// server slides it on every request. mpv gets the non-secret id in the URL,
/// the secret as a `Cookie` header, and no bearer at all, because the server
/// checks a bearer before `ss` and refuses an expired one without looking at
/// the session.
///
/// `/subtitles` takes no stream session, and mpv sends one set of headers for
/// everything it opens. Sidecar URLs therefore carry a stream token of the same
/// version, the protocol's credential for a player that cannot set a header per
/// request; mpv reads them once, right after open, well inside its lifetime.
mixin _PleyaServerStreamSessionMethods on _PleyaServerRequests {
  MediaServerHttpClient get _http;

  /// How often a held session is used while nothing else uses it, such as a
  /// long pause. Well below the smallest `stream_session_ttl` a server
  /// accepts (five minutes), so one missed tick does not end a paused film.
  static const Duration _streamSessionKeepAlive = Duration(minutes: 2);

  static final RegExp _streamSessionIdPattern = RegExp(r'^[A-Za-z0-9-]+$');

  /// Sessions by version id. They stay after playback so a reopen reuses its
  /// slot: a user has eight, and the protocol has no route to end one.
  final Map<String, _PleyaStreamSession> _streamSessions = {};

  /// The keep-alives of the results a player holds, so closing ends them.
  final Set<Timer> _streamSessionKeepAlives = {};

  /// A session being opened per version, so two overlapping starts share one
  /// slot instead of leaving the first one orphaned.
  final Map<String, Future<_PleyaStreamSession?>> _openingStreamSessions = {};

  String _streamUrl(String versionId) =>
      '${connection.baseUrl}$pleyaProtocolPrefix/stream/${Uri.encodeComponent(versionId)}';

  /// The credential for playing [versionId], or null to keep the bearer
  /// header: the server has no stream sessions, or one could not be opened. A
  /// sidecar [subtitles] list needs its stream token as well.
  ///
  /// Its keep-alive belongs to this one result: the player starts it with
  /// `hold` when it takes the result and ends it with `release` when the
  /// result leaves it. No ordering between results is needed, so a commit that
  /// arrives late or a result that is never taken cannot leak one.
  Future<_PleyaPlayerCredential?> _playerStreamCredential(String versionId, {required bool subtitles}) async {
    if (!wireCapabilities.streamSessions || isOfflineMode) return null;
    final session = await _streamSession(versionId);
    if (session == null) return null;
    String? subtitleToken;
    if (subtitles) {
      subtitleToken = await _streamToken(versionId);
      if (subtitleToken == null) return null;
    }
    Timer? keepAlive;
    var released = false;
    return (
      sessionId: session.id,
      headers: {'Cookie': '${_streamCookieName(session.id)}=${session.secret}'},
      subtitleToken: subtitleToken,
      hold: () {
        if (_closed || released || keepAlive != null) return;
        keepAlive = _keepStreamSessionAlive(versionId, session);
      },
      release: () {
        released = true;
        final timer = keepAlive;
        if (timer == null) return;
        timer.cancel();
        _streamSessionKeepAlives.remove(timer);
      },
    );
  }

  /// A session for [versionId] that is alive now, or null.
  Future<_PleyaStreamSession?> _streamSession(String versionId) =>
      _openingStreamSessions[versionId] ??= _openStreamSession(versionId).whenComplete(() {
        _openingStreamSessions.remove(versionId);
      });

  Future<_PleyaStreamSession?> _openStreamSession(String versionId) async {
    final cached = _streamSessions[versionId];
    if (cached != null && _isOk(await _touchStreamSession(versionId, cached))) return cached;
    _streamSessions.remove(versionId);
    try {
      Future<MediaServerResponse> open() async => _http.post(
        '/auth/stream-session',
        body: jsonEncode({'version_id': versionId}),
        headers: await _session.authHeaders(),
        timeout: MediaServerTimeouts.interactive,
      );
      var response = await open();
      if (response.statusCode == 401) {
        _session.invalidateAccessToken();
        response = await open();
      }
      throwIfHttpError(response);
      final id = PleyaStreamSession.fromJson(response.data as Map<String, dynamic>).streamSessionId;
      // Both halves end up in a header line mpv sends verbatim, so neither may
      // carry a separator.
      final secret = _streamSessionIdPattern.hasMatch(id)
          ? RegExp(
              '(?:^|[,;]\\s*)${_streamCookieName(id)}=([^;,\\s]+)',
            ).firstMatch(response.headers['set-cookie'] ?? '')
          : null;
      if (secret == null) {
        appLogger.w('PleyaServerClient: stream session answer had no usable cookie');
        return null;
      }
      return _streamSessions[versionId] = (id: id, secret: secret.group(1)!);
    } catch (e) {
      appLogger.d('PleyaServerClient: no stream session, the player keeps the bearer header', error: e);
      return null;
    }
  }

  /// Use [session] once, the way the player would, and answer the status; the
  /// server slides the session on a 2xx. Null is a transport failure.
  Future<int?> _touchStreamSession(String versionId, _PleyaStreamSession session) async {
    try {
      final uri = Uri.parse(_streamUrl(versionId)).replace(queryParameters: {'ss': session.id});
      final request = http.Request('HEAD', uri)
        ..headers['Cookie'] = '${_streamCookieName(session.id)}=${session.secret}';
      final response = await _http.inner.send(request).timeout(MediaServerTimeouts.interactive);
      await response.stream.drain<void>();
      return response.statusCode;
    } catch (e) {
      appLogger.d('PleyaServerClient: stream session check failed', error: e);
      return null;
    }
  }

  static bool _isOk(int? status) => status != null && status >= 200 && status < 300;

  /// Answers after which asking again changes nothing. A 5xx or 429 from a
  /// restarting server or its proxy is not one of them.
  static const Set<int> _refusals = {401, 403, 404, 410};

  Timer _keepStreamSessionAlive(String versionId, _PleyaStreamSession session) {
    final timer = Timer.periodic(_streamSessionKeepAlive, (tick) async {
      final status = await _touchStreamSession(versionId, session);
      // Refused: the session or the right to the title is gone, and asking
      // again changes nothing. A transport failure is worth the next tick.
      if (_refusals.contains(status)) {
        tick.cancel();
        _streamSessionKeepAlives.remove(tick);
      }
    });
    _streamSessionKeepAlives.add(timer);
    return timer;
  }

  void _releaseAllStreamSessions() {
    for (final timer in _streamSessionKeepAlives) {
      timer.cancel();
    }
    _streamSessionKeepAlives.clear();
  }

  /// A stream token for [versionId], or null. A failed mint is "no token", not
  /// an error the caller has to handle (`_postJson` throws on failure).
  Future<String?> _streamToken(String versionId) async {
    try {
      final json = await _postJson('/auth/stream-token', {'version_id': versionId});
      return json == null ? null : PleyaStreamToken.fromJson(json).streamToken;
    } catch (e) {
      appLogger.d('PleyaServerClient: stream token mint failed', error: e);
      return null;
    }
  }

  static String _streamCookieName(String sessionId) => 'pleya_ss_$sessionId';
}
