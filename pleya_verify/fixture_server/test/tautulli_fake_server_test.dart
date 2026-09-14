import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/tautulli_fake_server.dart';
import 'package:test/test.dart';

Future<http.Response> _get(TautulliFakeServer server, Map<String, String> query) {
  final uri = Uri.parse('http://fixture/tautulli/api/v2').replace(queryParameters: query);
  return server.handle(http.Request('GET', uri));
}

void main() {
  test('a wrong apikey answers the exact "Invalid apikey" message', () async {
    final server = TautulliFakeServer(apiKey: 'the-real-key');

    final response = await _get(server, {'apikey': 'wrong', 'cmd': 'get_server_friendly_name'});

    expect(response.statusCode, 400);
    final envelope = jsonDecode(response.body)['response'];
    expect(envelope['result'], 'error');
    expect(envelope['message'], 'Invalid apikey');
  });

  test('the three pairing commands answer with the right key', () async {
    final server = TautulliFakeServer(apiKey: 'verify-key')
      ..serverName = 'My NAS'
      ..pmsIdentifier = 'pms-123';

    final name = await _get(server, {'apikey': 'verify-key', 'cmd': 'get_server_friendly_name'});
    expect(jsonDecode(name.body)['response']['data'], 'My NAS');

    final info = await _get(server, {'apikey': 'verify-key', 'cmd': 'get_server_info'});
    expect(jsonDecode(info.body)['response']['data'], {'pms_name': 'My NAS', 'pms_identifier': 'pms-123'});

    final version = await _get(server, {'apikey': 'verify-key', 'cmd': 'get_tautulli_info'});
    expect(jsonDecode(version.body)['response']['data']['tautulli_version'], isA<String>());
  });

  test('get_activity reports a seeded session with real counters', () async {
    final server = TautulliFakeServer(apiKey: 'verify-key');
    server.addSession(sessionKey: '1', user: 'verify-viewer', title: 'Aurora Drift');

    final response = await _get(server, {'apikey': 'verify-key', 'cmd': 'get_activity'});
    final data = jsonDecode(response.body)['response']['data'] as Map<String, dynamic>;

    expect(data['sessions'], hasLength(1));
    expect(data['sessions'][0]['title'], 'Aurora Drift');
    expect(data['stream_count'], '1');
    expect(data['stream_count_direct_play'], 1);
  });

  test('reset clears every session', () async {
    final server = TautulliFakeServer(apiKey: 'verify-key');
    server.addSession(sessionKey: '1', user: 'verify-viewer', title: 'Aurora Drift');

    server.reset();

    expect(server.sessions, isEmpty);
  });
}
