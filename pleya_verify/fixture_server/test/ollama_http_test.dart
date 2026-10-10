import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:pleya_verify_fixture_server/http_adapter.dart';
import 'package:pleya_verify_fixture_server/pleya_fake_server.dart';
import 'package:test/test.dart';

void main() {
  late FixtureHttpServer adapter;
  late http.Client client;

  setUp(() async {
    adapter = FixtureHttpServer(server: PleyaFakeServer(), controlToken: 'fixture-control');
    await adapter.start();
    client = http.Client();
  });
  tearDown(() async {
    client.close();
    await adapter.stop();
  });

  Future<http.Response> post(String path, Map<String, Object?> body) => client.post(
    Uri.parse('http://127.0.0.1:${adapter.port}$path'),
    headers: {'content-type': 'application/json'},
    body: jsonEncode(body),
  );
  Future<Map<String, dynamic>> chat(
    String prompt,
    List<String> tools, {
    List<Map<String, Object?>> replies = const [],
  }) async {
    final response = await post('/v1/chat/completions', {
      'model': 'pleya-verify',
      'stream': false,
      'messages': [
        {'role': 'user', 'content': prompt},
        ...replies,
      ],
      'tools': [
        for (final name in tools)
          {
            'type': 'function',
            'function': {'name': name},
          },
      ],
    });
    expect(response.statusCode, 200);
    return (jsonDecode(response.body)['choices'][0]['message'] as Map).cast<String, dynamic>();
  }

  test('create_user is called with the server id the offered tool allows, never a password', () async {
    final response = await post('/v1/chat/completions', {
      'model': 'pleya-verify',
      'messages': [
        {'role': 'user', 'content': 'Maak gebruiker Robin aan.'},
      ],
      'tools': [
        {
          'type': 'function',
          'function': {
            'name': 'create_user',
            'parameters': {
              'properties': {
                'server_id': {
                  'type': 'string',
                  'enum': ['srv-1'],
                },
              },
            },
          },
        },
      ],
    });
    expect(response.statusCode, 200);
    final call = jsonDecode(response.body)['choices'][0]['message']['tool_calls'][0]['function'] as Map;
    expect(call['name'], 'create_user');
    expect(jsonDecode(call['arguments'] as String), {'server_id': 'srv-1', 'name': 'Robin', 'all_libraries': true});

    final withoutTool = await post('/v1/chat/completions', {
      'model': 'pleya-verify',
      'messages': [
        {'role': 'user', 'content': 'Maak gebruiker Robin aan.'},
      ],
      'tools': const <Object>[],
    });
    expect(withoutTool.statusCode, 400);
  });

  test('existing local settings and preload endpoints serve the fake model', () async {
    final tags = await client.get(Uri.parse('http://127.0.0.1:${adapter.port}/api/tags'));
    expect(tags.statusCode, 200);
    expect(jsonDecode(tags.body)['models'][0]['name'], 'pleya-verify');
    final show = await post('/api/show', {'model': 'pleya-verify'});
    expect(show.statusCode, 200);
    expect(jsonDecode(show.body)['capabilities'], contains('tools'));
    final preload = await post('/api/generate', {
      'model': 'pleya-verify',
      'prompt': '',
      'stream': false,
      'keep_alive': '10m',
    });
    expect(preload.statusCode, 200);
    expect(jsonDecode(preload.body)['done'], true);
  });

  test('root routes both real catalog searches in one exclusive split call', () async {
    final message = await chat('Zoek Aurora en zoek Basalt.', ['split_tasks', 'find_title']);
    final calls = message['tool_calls'] as List;
    expect(calls, hasLength(1));
    expect(calls.single['function']['name'], 'split_tasks');
    expect(jsonDecode(calls.single['function']['arguments'])['tasks'], [
      {'title': 'Aurora zoeken', 'intent': 'search', 'prompt': 'Zoek Aurora.'},
      {'title': 'Basalt zoeken', 'intent': 'search', 'prompt': 'Zoek Basalt.'},
    ]);
  });

  test('the space prompts call one discovery tool, then answer in text', () async {
    final discover = await chat('Ontdek ruimtefilms.', ['discover_request_titles']);
    expect(discover['tool_calls'][0]['function']['name'], 'discover_request_titles');
    final trending = await chat('Wat is er trending?', ['trending_titles']);
    expect(trending['tool_calls'][0]['function']['name'], 'trending_titles');
    expect(jsonDecode(trending['tool_calls'][0]['function']['arguments']), {'kind': 'all'});
    final reply = await chat(
      'Wat is er trending?',
      ['trending_titles'],
      replies: [
        {'role': 'tool', 'content': '{}'},
      ],
    );
    expect(reply['tool_calls'], isNull);
    expect(reply['content'], 'Dit is er populair.');
  });

  test('the TMDB stand-in is served behind /tmdb on the fixture port', () async {
    final url = Uri.parse('http://127.0.0.1:${adapter.port}/tmdb/3/trending/tv/week?api_key=verify-tmdb-key');
    final response = await client.get(url);
    expect(response.statusCode, 200);
    expect(jsonDecode(response.body)['results'].first['name'], 'Driftwood');
  });

  test('concurrent child transcripts remain independent and deterministic', () async {
    final messages = await Future.wait([
      chat('Zoek Basalt.', ['find_title']),
      chat('Zoek Aurora.', ['find_title']),
      chat('Zoek Aurora.', ['find_title']),
    ]);
    Map<String, dynamic> args(Map<String, dynamic> message) =>
        jsonDecode(message['tool_calls'][0]['function']['arguments']) as Map<String, dynamic>;
    expect(args(messages[0])['candidates'], [
      {'title': 'Basalt', 'year': 2022, 'kind': 'movie'},
    ]);
    expect(args(messages[1])['candidates'], [
      {'title': 'Aurora', 'year': 2021, 'kind': 'movie'},
    ]);
    expect(messages[1], messages[2]);
    expect(messages[1]['tool_calls'][0]['function']['name'], 'find_title');
  });

  test('real tool responses close the child without fabricated results', () async {
    final message = await chat(
      'Zoek Aurora.',
      ['find_title'],
      replies: [
        {
          'role': 'tool',
          'tool_call_id': 'find-aurora',
          'content': jsonEncode({
            'matches': [
              {'title': 'Aurora'},
            ],
          }),
        },
      ],
    );
    expect(message['tool_calls'], isNull);
    expect(message['content'], 'Aurora gevonden.');
    final failed = await chat(
      'Zoek Aurora.',
      ['find_title'],
      replies: [
        {'role': 'tool', 'tool_call_id': 'find-aurora', 'content': '{"error":"not_allowed"}'},
      ],
    );
    expect(failed['content'], 'Dat lukte niet.');
  });

  test('unsupported transcripts and unoffered tools fail instead of acting', () async {
    for (final prompt in ['unknown', 'Zoek Aurora en zoek Basalt.', 'Zoek Aurora.']) {
      final response = await post('/v1/chat/completions', {
        'model': 'pleya-verify',
        'messages': [
          {'role': 'user', 'content': prompt},
        ],
        'tools': [],
      });
      expect(response.statusCode, 400);
    }
    final unknown = await client.get(Uri.parse('http://127.0.0.1:${adapter.port}/api/unknown'));
    expect(unknown.statusCode, 404);
    final info = await client.get(Uri.parse('http://127.0.0.1:${adapter.port}/pleya/v1/info'));
    expect(info.statusCode, 200);
  });

  Future<http.Response> control(String op, Map<String, Object?> body) => client.post(
    Uri.parse('http://127.0.0.1:${adapter.port}/__verify/$op'),
    headers: {'authorization': 'Bearer fixture-control', 'content-type': 'application/json'},
    body: jsonEncode(body),
  );

  test('latency hold blocks only Aurora until released, with Basalt already complete', () async {
    expect((await control('latency', {'ollama_hold_aurora': true})).statusCode, 200);
    var auroraDone = false;
    final aurora = chat('Zoek Aurora.', ['find_title']).then((message) {
      auroraDone = true;
      return message;
    });
    final basalt = await chat('Zoek Basalt.', ['find_title']);
    expect(basalt['tool_calls'][0]['id'], 'find-basalt');
    expect(auroraDone, isFalse);
    expect((await control('latency', {'ollama_hold_aurora': false})).statusCode, 200);
    expect((await aurora.timeout(const Duration(seconds: 2)))['tool_calls'][0]['id'], 'find-aurora');
  });

  test('hold flag rejects invalid values without changing the model', () async {
    for (final value in ['true', 1, null]) {
      final result = await control('latency', {'ollama_hold_aurora': value});
      expect(result.statusCode, 400);
      expect(jsonDecode(result.body)['error'], 'ollama_hold_aurora must be a bool');
    }
    expect((await chat('Zoek Aurora.', ['find_title']))['tool_calls'][0]['id'], 'find-aurora');
  });

  test('reset releases all held responses and the following question is unheld', () async {
    await control('latency', {'ollama_hold_aurora': true});
    var completed = 0;
    final held = List.generate(
      2,
      (_) => chat('Zoek Aurora.', ['find_title']).then((message) {
        completed++;
        return message;
      }),
    );
    await chat('Zoek Basalt.', ['find_title']);
    expect(completed, 0);
    await control('reset', {});
    expect(await Future.wait(held).timeout(const Duration(seconds: 2)), hasLength(2));
    expect((await chat('Zoek Aurora.', ['find_title']))['tool_calls'][0]['id'], 'find-aurora');
  });

  test('stop drains held responses before closing and does not retain the hold', () async {
    await control('latency', {'ollama_hold_aurora': true});
    var auroraDone = false;
    final held = chat('Zoek Aurora.', ['find_title']).then((message) {
      auroraDone = true;
      return message;
    });
    await chat('Zoek Basalt.', ['find_title']);
    expect(auroraDone, isFalse);
    await adapter.stop().timeout(const Duration(seconds: 2));
    expect((await held)['tool_calls'][0]['id'], 'find-aurora');
    await adapter.start();
    expect((await chat('Zoek Aurora.', ['find_title']))['tool_calls'][0]['id'], 'find-aurora');
  });

  test('existing fixture evidence records model paths and reset clears them', () async {
    await chat('Zoek Aurora.', ['find_title']);
    final uri = Uri.parse('http://127.0.0.1:${adapter.port}/__verify/requests');
    final recorded = await client.get(uri, headers: {'authorization': 'Bearer fixture-control'});
    expect(jsonDecode(recorded.body)['requests'], contains('/v1/chat/completions'));
    expect(recorded.body, isNot(contains('Zoek Aurora')));
    await client.post(
      Uri.parse('http://127.0.0.1:${adapter.port}/__verify/reset'),
      headers: {'authorization': 'Bearer fixture-control'},
    );
    final reset = await client.get(uri, headers: {'authorization': 'Bearer fixture-control'});
    expect(jsonDecode(reset.body)['requests'], isEmpty);
  });
}
