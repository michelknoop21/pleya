import 'dart:convert';

import 'package:http/http.dart' as http;

/// A Tautulli routing kernel, good enough for the four commands the app
/// actually calls when pairing (`get_server_friendly_name`,
/// `get_server_info`, `get_tautulli_info`) and polling
/// (`get_activity`) — see `lib/services/tautulli/tautulli_client.dart`.
///
/// Tautulli's entire API is one endpoint (`GET /api/v2?apikey=&cmd=`), with
/// every response wrapped in `{"response": {"result", "message", "data"}}`
/// (`tautulli_client.dart:59-65`). apiKey mode only — device-token pairing
/// (`register_device`) is unnecessary complexity Pleya Verify does not need
/// to fake, since apiKey is the smaller of the two auth modes to automate.
class TautulliFakeServer {
  TautulliFakeServer({this.apiKey = 'verify-tautulli-key'});

  final String apiKey;

  String serverName = 'Verify NAS';
  String pmsIdentifier = 'verify-pms-1';
  String tautulliVersion = '2.17.2';
  final List<Map<String, dynamic>> sessions = [];

  void reset() {
    sessions.clear();
  }

  Future<http.Response> handle(http.Request request) async {
    final query = request.url.queryParameters;
    if (query['apikey'] != apiKey) {
      return _envelope(result: 'error', message: 'Invalid apikey', status: 400);
    }

    switch (query['cmd']) {
      case 'get_server_friendly_name':
        return _envelope(data: serverName);
      case 'get_server_info':
        return _envelope(data: {'pms_name': serverName, 'pms_identifier': pmsIdentifier});
      case 'get_tautulli_info':
        return _envelope(data: {'tautulli_version': tautulliVersion});
      case 'get_activity':
        return _envelope(
          data: {
            'sessions': sessions,
            'stream_count': '${sessions.length}',
            'stream_count_direct_play': sessions.where((s) => s['transcode_decision'] == 'direct play').length,
            'stream_count_direct_stream': sessions.where((s) => s['transcode_decision'] == 'copy').length,
            'stream_count_transcode': sessions.where((s) => s['transcode_decision'] == 'transcode').length,
            'total_bandwidth': sessions.fold<int>(0, (sum, s) => sum + (s['bandwidth'] as int? ?? 0)),
            'lan_bandwidth': sessions.fold<int>(
              0,
              (sum, s) => sum + (s['location'] == 'lan' ? (s['bandwidth'] as int? ?? 0) : 0),
            ),
            'wan_bandwidth': sessions.fold<int>(
              0,
              (sum, s) => sum + (s['location'] == 'wan' ? (s['bandwidth'] as int? ?? 0) : 0),
            ),
          },
        );
      default:
        return _envelope(result: 'error', message: 'Unknown command', status: 404);
    }
  }

  /// Registers one active session, shaped per a real `get_activity` capture
  /// (`test/fixtures/tautulli/activity_movie_direct_play.json`).
  void addSession({
    required String sessionKey,
    required String user,
    required String title,
    String mediaType = 'movie',
    String? grandparentTitle,
    int? seasonNumber,
    int? episodeNumber,
    int progressPercent = 12,
    int viewOffsetMs = 600000,
    int durationMs = 5400000,
    String state = 'playing',
  }) {
    sessions.add({
      'session_key': sessionKey,
      'user': user,
      'friendly_name': user,
      'user_id': sessionKey.hashCode.abs() % 1000000,
      'media_type': mediaType,
      'title': title,
      'grandparent_title': grandparentTitle ?? '',
      'parent_media_index': seasonNumber,
      'media_index': episodeNumber,
      'year': 2024,
      'thumb': '',
      'art': '',
      'state': state,
      'progress_percent': progressPercent,
      'view_offset': viewOffsetMs,
      'duration': durationMs,
      'transcode_decision': 'direct play',
      'video_full_resolution': '1080p',
      'stream_video_full_resolution': '1080p',
      'video_codec': 'hevc',
      'stream_video_codec': 'hevc',
      'audio_codec': 'eac3',
      'stream_audio_codec': 'eac3',
      'transcode_hw_encoding': 0,
      'bandwidth': 8000,
      'location': 'lan',
      'player': 'Pleya',
      'product': 'Pleya',
      'platform': 'Flutter',
      'quality_profile': 'Original',
    });
  }

  http.Response _envelope({Object? data, String result = 'success', String? message, int status = 200}) =>
      http.Response(
        jsonEncode({
          'response': {'result': result, 'message': message ?? '', 'data': data},
        }),
        status,
        headers: const {'content-type': 'application/json'},
      );
}
