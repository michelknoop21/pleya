import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import '../../models/tautulli/tautulli_activity.dart';
import '../../models/tautulli/tautulli_models.dart';
import '../../utils/app_logger.dart';
import '../../utils/log_redaction_manager.dart';
import '../../utils/media_server_http_client.dart';
import 'tautulli_constants.dart';
import 'tautulli_session.dart';

/// Typed Tautulli error so the UI can tell a wrong token from an unreachable
/// host and say something useful instead of "something went wrong".
///
/// [isNotTautulli] and [isMalformed] reach the user as the same sentence on
/// purpose, but they stay apart here and in the log, because they send you to
/// different places: the first means whatever answered was not Tautulli at all
/// (a proxy, an SSO login page, the wrong address), the second means it spoke
/// JSON that this client does not recognise (another API on that path, or a
/// version that moved the envelope).
class TautulliException implements Exception {
  final String message;
  final bool isAuth;
  final bool isNetwork;
  final bool isNotTautulli;
  final bool isMalformed;

  /// Set only when the failure *is* the HTTP status, so the UI can name the
  /// code instead of guessing at a cause.
  final int? statusCode;

  const TautulliException(
    this.message, {
    this.isAuth = false,
    this.isNetwork = false,
    this.isNotTautulli = false,
    this.isMalformed = false,
    this.statusCode,
  });

  factory TautulliException.auth() => const TautulliException('Invalid apikey', isAuth: true);
  factory TautulliException.network(String m) => TautulliException(m, isNetwork: true);
  factory TautulliException.notTautulli() => const TautulliException('not a Tautulli response', isNotTautulli: true);
  factory TautulliException.malformed() => const TautulliException('unrecognised response shape', isMalformed: true);

  /// A status code that carried no usable envelope. 401 and 403 are the two
  /// that mean the credential rather than the server, whatever the body says.
  factory TautulliException.http(int statusCode) =>
      TautulliException('HTTP $statusCode', statusCode: statusCode, isAuth: statusCode == 401 || statusCode == 403);

  @override
  String toString() => message;
}

/// HTTP client for one Tautulli instance.
///
/// Tautulli speaks a single endpoint: `GET /api/v2?apikey=…&cmd=…`. Everything
/// is a GET and every response is wrapped in `{"response": {"result",
/// "message", "data"}}`. What the status code means varies: a bad command comes
/// back as HTTP 200 with `result: "error"`, a rejected key as HTTP 400 with the
/// same envelope. So the envelope is read before the status code, and whether
/// the body is JSON at all is read before either, because on a reverse-proxied
/// instance the thing that answers is often not Tautulli.
///
/// Contracts measured against v2.17.2; see `test/fixtures/tautulli/README.md`.
class TautulliClient {
  TautulliClient(this._session, {http.Client? httpClient})
    : _http = MediaServerHttpClient(
        client: httpClient,
        baseUrl: TautulliConstants.normalizeBaseUrl(_session.baseUrl),
        connectTimeout: TautulliConstants.requestTimeout,
        receiveTimeout: TautulliConstants.requestTimeout,
      ) {
    // Same as the Plex and Jellyfin clients do, and it was the one backend that
    // did not: the key rides in the query string of every request, so without
    // this a log holds it verbatim. The name-based rule in LogRedactionManager
    // catches `apikey=` on its own now; this is the second layer, for wherever
    // the value turns up without its parameter name.
    LogRedactionManager.registerServer(_session.baseUrl, _session.token);
  }

  final TautulliSession _session;
  final MediaServerHttpClient _http;

  TautulliSession get session => _session;

  void dispose() => _http.close();

  // ---------------------------------------------------------------------------
  // Transport
  // ---------------------------------------------------------------------------

  /// Run [cmd] and return its `data`, or throw a [TautulliException].
  ///
  /// [app] must be true for a device token: `api2.py` only consults the mobile
  /// device table when `app=1` is present, so leaving it off makes a perfectly
  /// valid device token look like a wrong key.
  Future<Object?> _call(String cmd, {Map<String, dynamic> params = const {}, Duration? timeout}) async {
    final query = <String, dynamic>{
      'apikey': _session.token,
      'cmd': cmd,
      if (_session.isDeviceToken) 'app': 1,
      ...params,
    };

    final MediaServerResponse resp;
    try {
      resp = await _http.get(TautulliConstants.apiPath, queryParameters: query, timeout: timeout);
    } catch (e) {
      throw _fail(cmd, TautulliException.network(e.toString()));
    }

    // One boundary around everything that interprets the answer. The old one
    // stopped at the transport, which left the decode and the casts behind it
    // as the single way out of here that produced neither a TautulliException
    // nor a log line: an HTML page answered with HTTP 200 threw a
    // FormatException straight past the settings screen, which showed its
    // generic "connecting failed" and recorded nothing at all.
    try {
      return _interpret(cmd, resp);
    } on TautulliException {
      rethrow; // _fail already logged it.
    } catch (e, st) {
      throw _fail(cmd, TautulliException.malformed(), detail: _responseDetail(resp), cause: e, stackTrace: st);
    }
  }

  /// Classify one response: decode first, then the envelope, then the status.
  ///
  /// Both halves of that order were bought the hard way. Reading the status
  /// first hides the envelope, and since Tautulli rejects a key with HTTP 400
  /// rather than the 200 this client assumed, [TautulliException.isAuth] was
  /// never set for the most common failure there is: someone pasting an API key
  /// into device mode got the string `HTTP 400` instead of the sentence telling
  /// them which field to use. Reading the envelope without first asking whether
  /// the body was JSON is the opposite mistake, and it would land a broken
  /// gateway on the user as "this is not Tautulli", sending them off to check an
  /// address that was right all along.
  Object? _interpret(String cmd, MediaServerResponse resp) {
    final decoded = _decodeJson(resp.data);

    if (decoded == null) {
      if (!_isSuccess(resp.statusCode)) throw _fail(cmd, TautulliException.http(resp.statusCode));
      throw _fail(cmd, TautulliException.notTautulli(), detail: _responseDetail(resp));
    }

    final envelope = decoded is Map ? decoded['response'] : null;
    if (envelope is Map) {
      if (envelope['result'] == 'success') return envelope['data'];
      // Tautulli answers some errors with `message: ""` rather than by leaving
      // it out, and an empty string reaches the settings screen as a blank
      // error line, after which the Test button looks like it did nothing.
      final reported = envelope['message']?.toString().trim() ?? '';
      final msg = reported.isEmpty ? 'Unknown error' : reported;
      if (isAuthMessage(msg)) throw _fail(cmd, TautulliException.auth());
      throw _fail(cmd, TautulliException(msg));
    }

    if (!_isSuccess(resp.statusCode)) throw _fail(cmd, TautulliException.http(resp.statusCode));
    throw _fail(cmd, TautulliException.malformed(), detail: _responseDetail(resp));
  }

  /// Does this message mean the credential was rejected?
  ///
  /// Tautulli's own wording is exactly `Invalid apikey`, measured, so that one
  /// matches exactly and the rest are the variants proxies and older builds
  /// produce. The rule this replaces was `contains('apikey')`, which promotes
  /// any message that merely names the parameter into an authentication
  /// failure, and being wrong in that direction costs the user an afternoon of
  /// regenerating tokens that were never the problem.
  @visibleForTesting
  static bool isAuthMessage(String message) {
    final m = message.trim().toLowerCase();
    if (m == 'invalid apikey') return true;
    return const ['invalid api key', 'apikey is invalid', 'unauthorized', 'authentication'].any(m.contains);
  }

  static bool _isSuccess(int statusCode) => statusCode >= 200 && statusCode < 300;

  /// The parsed body, or null when the response was not JSON at all.
  ///
  /// [MediaServerHttpClient] only parses when the content type says so, which
  /// leaves two shapes to handle: an already-decoded value, and the raw String
  /// a proxy hands back with `text/html`. Tautulli behind a stripped-header
  /// proxy also sends JSON without the content type, so the String is worth a
  /// parse attempt rather than an immediate verdict.
  static Object? _decodeJson(Object? data) {
    if (data is! String) return data;
    final trimmed = data.trim();
    if (trimmed.isEmpty) return null;
    try {
      return json.decode(trimmed);
    } on FormatException {
      return null;
    }
  }

  /// One line naming what came back instead, for the two cases where the body
  /// itself is the evidence.
  ///
  /// Cut to [_bodyPrefixLength] before it is logged rather than after, and put
  /// through [LogRedactionManager] after that. A Tautulli token is not normally
  /// part of a response body, but "normally" is not something a redaction rule
  /// gets to depend on.
  static String _responseDetail(MediaServerResponse resp) {
    final contentType = _headerValue(resp.headers, 'content-type') ?? 'none';
    String raw;
    try {
      raw = resp.data is String ? resp.data as String : json.encode(resp.data);
    } catch (_) {
      raw = resp.data.toString();
    }
    final collapsed = raw.replaceAll(RegExp(r'\s+'), ' ').trim();
    final prefix = collapsed.length > _bodyPrefixLength ? '${collapsed.substring(0, _bodyPrefixLength)}…' : collapsed;
    return 'contentType=$contentType; bodyPrefix="${LogRedactionManager.redact(prefix)}"';
  }

  static const int _bodyPrefixLength = 80;

  static String? _headerValue(Map<String, String> headers, String name) {
    final lower = name.toLowerCase();
    for (final entry in headers.entries) {
      if (entry.key.toLowerCase() == lower) return entry.value;
    }
    return null;
  }

  /// Log the reason, then hand the exception back to be thrown.
  ///
  /// Not every Tautulli failure shows up in the status code, so an uploaded log
  /// used to show a row of successful-looking requests and no hint why the user
  /// kept retrying. The command and the message are enough to tell a wrong key
  /// from an unreachable host; the token is never part of it, and neither is the
  /// URL, because the key rides along in its query string.
  ///
  /// The two body-shape failures log at warning level: they are the ones you go
  /// looking for in someone else's log, and a log without debug logging turned
  /// on keeps nothing below info.
  TautulliException _fail(String cmd, TautulliException e, {String? detail, Object? cause, StackTrace? stackTrace}) {
    final tags = [
      if (e.isAuth) 'auth',
      if (e.isNetwork) 'network',
      if (e.isNotTautulli) 'not-tautulli',
      if (e.isMalformed) 'malformed',
    ];
    final line =
        'Tautulli $cmd failed: ${e.message}${tags.isEmpty ? '' : ' (${tags.join(', ')})'}'
        '${detail == null ? '' : '\n  $detail'}';
    if (cause != null) {
      appLogger.e(line, error: cause, stackTrace: stackTrace);
    } else if (e.isNotTautulli || e.isMalformed) {
      appLogger.w(line);
    } else {
      appLogger.d(line);
    }
    return e;
  }

  List<Map<String, dynamic>> _rows(Object? data) =>
      data is List ? data.whereType<Map<String, dynamic>>().toList() : const [];

  // ---------------------------------------------------------------------------
  // Pairing and identity
  // ---------------------------------------------------------------------------

  /// Exchange a freshly generated device token for a registered one.
  ///
  /// The admin creates the token in Tautulli (Settings > Tautulli Remote App)
  /// and it stays valid for five minutes. After this call Tautulli stores the
  /// same string as a permanent device token, which is what we keep; the admin
  /// can revoke that one device without touching the master API key.
  ///
  /// Returns the server info Tautulli reports back, so pairing can show which
  /// server was reached before anything is saved.
  Future<Map<String, dynamic>> registerDevice({required String deviceId, required String deviceName}) async {
    final data = await _call(
      'register_device',
      params: {'device_id': deviceId, 'device_name': deviceName, 'platform': 'Pleya', 'friendly_name': deviceName},
    );
    return data is Map<String, dynamic> ? data : const {};
  }

  /// Cheap round-trip that proves both reachability and the token.
  Future<String?> serverFriendlyName() async {
    final data = await _call('get_server_friendly_name');
    return data is String ? data : data?.toString();
  }

  /// The Plex server this instance monitors: `pms_identifier`, `pms_name` and
  /// friends.
  ///
  /// Pairing needs the identifier, and `register_device` only reports it in
  /// device mode, so an apiKey pairing asks for it here. Rating keys are
  /// per-server, so without it a session cannot be resolved against the right
  /// Plex server.
  Future<Map<String, dynamic>> serverInfo() async {
    final data = await _call('get_server_info');
    return data is Map<String, dynamic> ? data : const {};
  }

  Future<String?> version() async {
    final data = await _call('get_tautulli_info');
    return data is Map ? data['tautulli_version']?.toString() : null;
  }

  // ---------------------------------------------------------------------------
  // Reads
  // ---------------------------------------------------------------------------

  /// Per-user totals for one title. Accepts a movie or a show rating key; for a
  /// show Tautulli aggregates across every episode.
  ///
  /// Counts abandoned plays too, so treat the result as "has watched in this",
  /// not "has finished it". [watchersOf] is the stricter question.
  Future<List<TautulliItemUserStat>> itemUserStats(String ratingKey) async {
    final data = await _call('get_item_user_stats', params: {'rating_key': ratingKey});
    return _rows(data).map(TautulliItemUserStat.tryFromJson).nonNulls.toList();
  }

  /// Everyone Tautulli says actually watched [ratingKey] through, newest first.
  ///
  /// Built from history rather than from [itemUserStats] because only history
  /// carries `watched_status`; there is no server-side filter for it, so the
  /// filtering happens here. Meant for movies, where the row count is small.
  Future<List<TautulliHistoryEntry>> watchersOf(String ratingKey, {int limit = 100}) async {
    // Grouped on purpose: this asks "who watched this", so five consecutive
    // plays by one person should cost one row out of the budget, not five.
    final page = await history(ratingKey: ratingKey, length: limit, grouping: true);
    final seen = <int>{};
    return [
      for (final e in page.entries)
        if (e.isWatched && e.userId != null && seen.add(e.userId!)) e,
    ];
  }

  /// Raw playback history. Filter by item ([ratingKey]), by series
  /// ([grandparentRatingKey]) or by person ([userId]).
  ///
  /// [after] and [before] are `YYYY-MM-DD` and both *inclusive*, which is what
  /// Tautulli's own docs say ("History after and including the date"). They are
  /// the time cursor; [start] stays a pagination offset and is never a date.
  ///
  /// [grouping] defaults to off. Tautulli's default groups consecutive plays of
  /// the same item into one synthetic row carrying `group_count`/`group_ids`,
  /// which makes `row_id` unstable and therefore useless as an idempotency key.
  /// [includeActivity] defaults to off so a session still in progress does not
  /// arrive as history.
  Future<TautulliHistoryPage> history({
    String? ratingKey,
    String? grandparentRatingKey,
    int? userId,
    int length = 25,
    int start = 0,
    bool grouping = false,
    bool includeActivity = false,
    String? orderColumn,
    String? orderDir,
    String? after,
    String? before,
  }) async {
    final data = await _call(
      'get_history',
      params: {
        'rating_key': ?ratingKey,
        'grandparent_rating_key': ?grandparentRatingKey,
        'user_id': ?userId,
        'length': length,
        'start': start,
        'grouping': grouping ? 1 : 0,
        'include_activity': includeActivity ? 1 : 0,
        'order_column': ?orderColumn,
        'order_dir': ?orderDir,
        'after': ?after,
        'before': ?before,
      },
    );
    return data is Map<String, dynamic> ? TautulliHistoryPage.fromJson(data) : TautulliHistoryPage.empty;
  }

  /// Everyone Tautulli knows about, with the avatars the Plex Media Server does
  /// not provide.
  Future<List<TautulliUser>> users() async {
    final data = await _call('get_users');
    return _rows(data).map(TautulliUser.tryFromJson).nonNulls.toList();
  }

  /// Everything playing on the server right now.
  ///
  /// Polled while a surface is watching it, so it runs on the shorter
  /// [TautulliConstants.activityTimeout] rather than the default: a poll that
  /// outlives its own interval would stack requests on a slow instance.
  ///
  /// The response is large (247 fields per stream on the measured server), and
  /// most of it is library metadata the app already has. [TautulliStream] keeps
  /// the streaming half and drops the addresses.
  Future<TautulliActivity> activity() async {
    final data = await _call('get_activity', timeout: TautulliConstants.activityTimeout);
    return data is Map<String, dynamic> ? TautulliActivity.fromJson(data) : TautulliActivity.empty;
  }

  /// Plays and seconds for a title per window; `query_days: 0` is all time.
  Future<List<TautulliWatchTimeStat>> itemWatchTimeStats(String ratingKey) async {
    final data = await _call('get_item_watch_time_stats', params: {'rating_key': ratingKey});
    return _rows(data).map(TautulliWatchTimeStat.fromJson).toList();
  }

  /// True when the instance answers and accepts the token.
  Future<bool> ping() async {
    try {
      await serverFriendlyName();
      return true;
    } on TautulliException {
      // _call already logged the reason.
      return false;
    }
  }
}
