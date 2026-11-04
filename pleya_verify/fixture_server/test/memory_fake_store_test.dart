import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/named_fixtures.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

void main() {
  const fact = {
    'id': '11111111-1111-4111-8111-111111111111',
    'category': 'preference',
    'value': 'Houdt van ruimtefilms',
    'source': 'settings_manual',
  };
  late PleyaFakeServer server;
  Future<http.Response> request(String method, String path, {String? token, Object? body}) {
    final request = http.Request(method, Uri.parse('http://fixture/pleya/v1$path'));
    if (token != null) request.headers['Authorization'] = 'Bearer $token';
    if (body != null) request.body = jsonEncode(body);
    return server.handle(request);
  }

  Map<String, dynamic> object(http.Response response) => jsonDecode(response.body) as Map<String, dynamic>;
  Future<String> login(String username) async =>
      object(await request('POST', '/auth/login', body: {'username': username, 'password': 'password'}))['access_token']
          as String;
  Future<Map<String, dynamic>> snapshot(String token) async =>
      object(await request('GET', '/users/me/memory', token: token));
  Future<http.Response> replace(String token, Map<String, dynamic> base, List<Map<String, String>> facts) => request(
    'PUT',
    '/users/me/memory',
    token: token,
    body: {'epoch': base['epoch'], 'base_revision': base['revision'], 'facts': facts},
  );

  setUp(() {
    server = PleyaFakeServer();
    expect(applyNamedFixture(server, 'memory.sync.v1'), isTrue);
    server.addMemoryAccount(username: 'one', password: 'password');
    server.addMemoryAccount(username: 'two', password: 'password');
  });

  test('two sessions of the same account share memory; another account does not', () async {
    final first = await login('one');
    final second = await login('one');
    final other = await login('two');
    final base = await snapshot(first);
    final response = await replace(first, base, [fact]);
    expect(response.statusCode, 200);
    expect(response.headers['cache-control'], 'no-store');
    expect((await snapshot(second))['facts'], [containsPair('value', fact['value'])]);
    expect((await snapshot(other))['facts'], isEmpty);
    expect((await request('GET', '/users/me', token: first)).statusCode, 200);
  });

  test('stale revision and deleted id cannot resurrect an old fact', () async {
    final token = await login('one');
    final first = await snapshot(token);
    final added = object(await replace(token, first, [fact]));
    expect((await replace(token, first, [])).statusCode, 409);
    final removed = object(await replace(token, added, []));
    final stale = await replace(token, removed, [fact]);
    expect(stale.statusCode, 409);
    expect(object(stale)['error'], containsPair('code', 'memory.deleted'));
    expect((await snapshot(token))['facts'], isEmpty);
  });

  test('clear rotates epoch so pending new facts on an offline device are refused', () async {
    final token = await login('one');
    final base = await snapshot(token);
    final cleared = object(
      await request(
        'POST',
        '/users/me/memory/clear',
        token: token,
        body: {'epoch': base['epoch'], 'base_revision': base['revision']},
      ),
    );
    expect(cleared['epoch'], isNot(base['epoch']));
    final stale = await replace(token, base, [fact]);
    expect(object(stale)['error'], containsPair('code', 'memory.epoch_changed'));
  });

  test('restricted role, forged fields, oversized and duplicate facts are refused', () async {
    final token = await login('one');
    final base = await snapshot(token);
    final duplicate = {...fact, 'id': '22222222-2222-4222-8222-222222222222'};
    expect(object(await replace(token, base, [fact, duplicate]))['error'], containsPair('code', 'memory.duplicate'));
    final forged = await request(
      'PUT',
      '/users/me/memory',
      token: token,
      body: {'epoch': base['epoch'], 'base_revision': 0, 'facts': [], 'user_id': 'two'},
    );
    expect(forged.statusCode, 400);
    final household = {...fact, 'category': 'household'};
    expect((await replace(token, base, [household])).statusCode, 400);
    final oversized = http.Request('PUT', Uri.parse('http://fixture/pleya/v1/users/me/memory'))
      ..headers['Authorization'] = 'Bearer $token'
      ..body = ' ' * (256 * 1024 + 1);
    expect((await server.handle(oversized)).statusCode, 413);
    server.setMemoryRole('one', 'restricted');
    expect((await request('GET', '/users/me/memory', token: token)).statusCode, 403);
    expect((await replace(token, base, [fact])).statusCode, 403);
  });

  test('the capability and routes stay absent for old fixtures', () async {
    server = PleyaFakeServer();
    final info = object(await request('GET', '/info'));
    expect((info['capabilities'] as Map).containsKey('assistant_memory'), isFalse);
    expect((await request('GET', '/users/me/memory', token: 'at-0')).statusCode, 404);
  });
}
