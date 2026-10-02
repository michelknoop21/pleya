import 'dart:convert';
import 'dart:io';

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

  test('base URLs as provider docs print them reach the same endpoints', () {
    expect(normaliseBaseUrl('https://ollama.com/v1/'), 'https://ollama.com');
    expect(normaliseBaseUrl('https://ollama.com/api'), 'https://ollama.com');
    expect(normaliseBaseUrl('http://nas.lan:11434'), 'http://nas.lan:11434');
    expect(normaliseBaseUrl('https://openrouter.ai/api/v1'), 'https://openrouter.ai/api');
    expect(normaliseBaseUrl('https://openrouter.ai/api'), 'https://openrouter.ai/api');
  });

  test('a proxy header must be a token name and a single-line value', () {
    expect(isValidProxyHeader('X-Proxy-Key', 'abc'), isTrue);
    expect(isValidProxyHeader('Bad Header', 'abc'), isFalse);
    expect(isValidProxyHeader('X-Key', 'a\r\nInjected: 1'), isFalse);
  });

  test('only the real no-tools messages count as unsupported', () async {
    AssistantModelClient client(String body) => AssistantModelClient(
      const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o:11434', model: 'm'),
      httpClient: MockClient((_) async => http.Response(body, 400)),
    );
    await expectLater(
      client('{"error":"registry.ollama.ai/library/gemma does not support tools"}').chat(const [], const [{}]),
      throwsA(isA<AssistantModelException>().having((e) => e.error, 'error', AssistantModelError.toolsUnsupported)),
    );
    await expectLater(
      client('{"error":"invalid tool call arguments"}').chat(const [], const [{}]),
      throwsA(isA<AssistantModelException>().having((e) => e.error, 'error', AssistantModelError.badResponse)),
    );
  });

  test('the assistant message goes back with provider fields intact', () async {
    final client = AssistantModelClient(
      const AssistantProviderConfig(
        kind: AssistantProviderKind.openRouter,
        baseUrl: AssistantProviderConfig.openRouterUrl,
        apiKey: 'k',
        model: 'm',
      ),
      httpClient: MockClient(
        (_) async => _json({
          'choices': [
            {
              'message': {
                'role': 'assistant',
                'content': '',
                'reasoning_details': [
                  {'type': 'reasoning.encrypted', 'data': 'x'},
                ],
                'tool_calls': [
                  {
                    'id': 'or_1',
                    'type': 'function',
                    'index': 0,
                    'function': {'name': 'list_servers', 'arguments': '{}'},
                  },
                ],
              },
            },
          ],
        }),
      ),
    );
    final reply = await client.chat(const [], const []);
    expect(reply.message['reasoning_details'], isNotNull);
    expect(((reply.message['tool_calls'] as List).single as Map)['index'], 0);
    expect(((reply.message['tool_calls'] as List).single as Map)['id'], 'or_1');
  });

  test('a TLS failure is unreachable, not a crash', () async {
    final client = AssistantModelClient(
      const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'https://nas:11434', model: 'm'),
      httpClient: MockClient((_) async => throw const HandshakeException('bad certificate')),
    );
    await expectLater(
      client.chat(const [], const []),
      throwsA(isA<AssistantModelException>().having((e) => e.error, 'error', AssistantModelError.unreachable)),
    );
  });

  test('when every model lookup fails the user sees an error, not an empty list', () async {
    final client = AssistantModelClient(
      const AssistantProviderConfig(kind: AssistantProviderKind.ollamaServer, baseUrl: 'http://o:11434'),
      httpClient: MockClient((r) async {
        if (r.url.path == '/api/tags') {
          return _json({
            'models': [
              {'name': 'a'},
              {'name': 'b'},
            ],
          });
        }
        return http.Response('blocked', 405);
      }),
    );
    await expectLater(client.toolModels(), throwsA(isA<AssistantModelException>()));
  });
}
