import 'dart:convert';

import 'package:http/http.dart' as http;

import '../../models/tautulli/tautulli_activity.dart';
import '../../models/tautulli/tautulli_models.dart';
import '../../utils/app_logger.dart';
import '../../utils/media_server_http_client.dart';
import 'tautulli_constants.dart';
import 'tautulli_session.dart';

/// Typed Tautulli error so the UI can tell a wrong token from an unreachable
/// host and say something useful instead of "something went wrong".
class TautulliException implements Exception {
  final String message;
  final bool isAuth;
  final bool isNetwork;

  const TautulliException(this.message, {this.isAuth = false, this.isNetwork = false});

  factory TautulliException.auth() => const TautulliException('Invalid apikey', isAuth: true);
  factory TautulliException.network(String m) => TautulliException(m, isNetwork: true);

  @override
  String toString() => message;
}

/// HTTP client for one Tautulli instance.
///
/// Tautulli speaks a single endpoint: `GET /api/v2?apikey=…&cmd=…`. Everything
/// is a GET, every response is wrapped in `{"response": {"result", "message",
/// "data"}}`, and a failure arrives as HTTP 200 with `result: "error"`, so the
/// envelope has to be inspected rather than the status code.
///
/// Contracts measured against v2.17.2; see `test/fixtures/tautulli/README.md`.
class TautulliClient {
  TautulliClient(this._session, {http.Client? httpClient})
    : _http = MediaServerHttpClient(
        client: httpClient,
        baseUrl: TautulliConstants.normalizeBaseUrl(_session.baseUrl),
        connectTimeout: TautulliConstants.requestTimeout,
        receiveTimeout: TautulliConstants.requestTimeout,
      );

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

    if (resp.statusCode == 401) throw _fail(cmd, TautulliException.auth());
    if (resp.statusCode != 200) throw _fail(cmd, TautulliException('HTTP ${resp.statusCode}'));

    final body = resp.data is String ? json.decode(resp.data as String) : resp.data;
    if (body is! Map) throw _fail(cmd, const TautulliException('Unexpected response'));
    final envelope = body['response'];
    if (envelope is! Map) throw _fail(cmd, const TautulliException('Unexpected response'));

    if (envelope['result'] != 'success') {
      // Tautulli answers some errors with `message: ""` rather than by leaving
      // it out, and an empty string reaches the settings screen as a blank
      // error line, after which the Test button looks like it did nothing.
      final reported = envelope['message']?.toString().trim() ?? '';
      final msg = reported.isEmpty ? 'Unknown error' : reported;
      // Tautulli answers a bad key with HTTP 200 + this exact message.
      if (msg.toLowerCase().contains('apikey')) throw _fail(cmd, TautulliException.auth());
      throw _fail(cmd, TautulliException(msg));
    }
    return envelope['data'];
  }

  /// Log the reason, then hand the exception back to be thrown.
  ///
  /// Every Tautulli failure arrives as HTTP 200, so an uploaded log used to
  /// show a row of successful-looking requests and no hint why the user kept
  /// retrying. The command and the message are enough to tell a wrong key from
  /// an unreachable host; the token is never part of it, and neither is the
  /// URL, because the key rides along in its query string.
  TautulliException _fail(String cmd, TautulliException e) {
    appLogger.d('Tautulli $cmd failed: ${e.message}${e.isAuth ? ' (auth)' : ''}${e.isNetwork ? ' (network)' : ''}');
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
    final page = await history(ratingKey: ratingKey, length: limit);
    final seen = <int>{};
    return [
      for (final e in page.entries)
        if (e.isWatched && e.userId != null && seen.add(e.userId!)) e,
    ];
  }

  /// Raw playback history. Filter by item ([ratingKey]), by series
  /// ([grandparentRatingKey]) or by person ([userId]).
  Future<TautulliHistoryPage> history({
    String? ratingKey,
    String? grandparentRatingKey,
    int? userId,
    int length = 25,
    int start = 0,
  }) async {
    final data = await _call(
      'get_history',
      params: {
        'rating_key': ?ratingKey,
        'grandparent_rating_key': ?grandparentRatingKey,
        'user_id': ?userId,
        'length': length,
        'start': start,
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
