import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:pleya/assistant/assistant_provider.dart';

http.Response _json(Object body, {int status = 200}) =>
    http.Response(jsonEncode(body), status, headers: const {'content-type': 'application/json'});

void main() {
  test('Ollama offers only models whose /api/show lists tools', () async {
    final seen = <String>[];
    final client = AssistantModelClient(
      const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://ollama.lan:11434/'),
      httpClient: MockClient((r) async {
        seen.add('${r.method} ${r.url.path}');
        if (r.url.path == '/api/tags') {
          return _json({
            'models': [
              {'name': 'qwen3:8b'},
              {'name': 'llava:7b'},
            ],
          });
        }
        final model = (jsonDecode(r.body) as Map)['model'];
        return _json({
          'capabilities': model == 'qwen3:8b' ? ['completion', 'tools'] : ['completion', 'vision'],
        });
      }),
    );
    expect(await client.toolModels(), ['qwen3:8b']);
    expect(seen, ['GET /api/tags', 'POST /api/show', 'POST /api/show']);
  });

  test('Ollama Cloud uses the same discovery with a bearer key', () async {
    final auth = <String?>[];
    final client = AssistantModelClient(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.ollamaCloud,
        baseUrl: AssistantProviderConfig.ollamaCloudUrl,
        apiKey: 'sk-cloud',
      ),
      httpClient: MockClient((r) async {
        auth.add(r.headers['authorization']);
        expect(r.url.host, 'ollama.com');
        if (r.url.path == '/api/tags') {
          return _json({
            'models': [
              {'name': 'gpt-oss:120b'},
            ],
          });
        }
        return _json({
          'capabilities': ['completion', 'tools', 'thinking'],
        });
      }),
    );
    expect(await client.toolModels(), ['gpt-oss:120b']);
    expect(auth.toSet(), {'Bearer sk-cloud'});
  });

  test('OpenRouter asks the server for tool-capable models only', () async {
    Uri? asked;
    final client = AssistantModelClient(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.openRouter,
        baseUrl: AssistantProviderConfig.openRouterUrl,
        apiKey: 'sk-or',
      ),
      httpClient: MockClient((r) async {
        asked = r.url;
        return _json({
          'data': [
            {'id': 'b/model'},
            {'id': 'a/model'},
          ],
        });
      }),
    );
    expect(await client.toolModels(), ['a/model', 'b/model']);
    expect(asked!.path, '/api/v1/models');
    expect(asked!.queryParameters, {'supported_parameters': 'tools'});
  });

  test('a rejected key is unauthorized, not an empty model list', () async {
    final client = AssistantModelClient(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.openRouter,
        baseUrl: AssistantProviderConfig.openRouterUrl,
        apiKey: 'bad',
      ),
      httpClient: MockClient((_) async => http.Response('{}', 401)),
    );
    await expectLater(
      client.toolModels(),
      throwsA(isA<AssistantModelException>().having((e) => e.error, 'error', AssistantModelError.unauthorized)),
    );
  });

  test('OpenRouter 404 about tool use maps to toolsUnsupported', () async {
    final client = AssistantModelClient(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.openRouter,
        baseUrl: AssistantProviderConfig.openRouterUrl,
        apiKey: 'k',
        model: 'm',
      ),
      httpClient: MockClient(
        (_) async => http.Response('{"error":{"message":"No endpoints found that support tool use"}}', 404),
      ),
    );
    await expectLater(
      client.chat(const [], const [{}]),
      throwsA(isA<AssistantModelException>().having((e) => e.error, 'error', AssistantModelError.toolsUnsupported)),
    );
  });

  test('a tool call without an id still gets one, and object arguments become JSON text', () async {
    final client = AssistantModelClient(
      const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o:11434', model: 'm'),
      httpClient: MockClient(
        (_) async => _json({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': null,
                'tool_calls': [
                  {
                    'function': {
                      'name': 'list_servers',
                      'arguments': {'a': 1},
                    },
                  },
                ],
              },
            },
          ],
        }),
      ),
    );
    final reply = await client.chat(const [], const []);
    expect(reply.toolCalls.single.id, 'call_0');
    expect(jsonDecode(reply.toolCalls.single.arguments), {'a': 1});
    expect((reply.message['tool_calls'] as List).single['id'], 'call_0');
  });

  test('config round-trips without losing the secrets', () {
    const config = AssistantProviderConfig(
      kind: AssistantProviderKind.ollamaServer,
      baseUrl: 'http://o:11434',
      model: 'qwen3:8b',
      headerName: 'X-Proxy-Key',
      headerValue: 'p',
    );
    final back = AssistantProviderConfig.fromJson(config.toJson())!;
    expect(back.toJson(), config.toJson());
    expect(back.isComplete, isTrue);
    expect(
      const AssistantProviderConfig(kind: AssistantProviderKind.openRouter, baseUrl: 'x', model: 'm').isComplete,
      isFalse,
    );
  });
}
