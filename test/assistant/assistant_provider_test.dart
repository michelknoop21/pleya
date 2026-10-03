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

  group('model details', () {
    const server = AssistantProviderConfig(
      kind: AssistantProviderKind.ollamaServer,
      baseUrl: 'http://ollama.lan:11434',
      model: 'qwen3:8b',
    );

    test('Ollama: tags carry size, date, parameters; newest first; only tool models', () async {
      final client = AssistantModelClient(
        server,
        httpClient: MockClient((r) async {
          if (r.url.path == '/api/tags') {
            return _json({
              'models': [
                {
                  'name': 'llama3.1:8b',
                  'size': 4920753328,
                  'modified_at': '2026-08-01T10:00:00Z',
                  'details': {'family': 'llama', 'parameter_size': '8.0B', 'quantization_level': 'Q4_K_M'},
                },
                {'name': 'qwen3:8b', 'modified_at': '2026-09-30T10:00:00Z'},
                {'name': 'llava:7b', 'modified_at': '2026-10-01T10:00:00Z'},
              ],
            });
          }
          final model = (jsonDecode(r.body) as Map)['model'];
          return _json({
            'capabilities': model == 'llava:7b' ? ['completion'] : ['completion', 'tools'],
          });
        }),
      );
      final models = await client.models();
      expect(models.map((m) => m.id), ['qwen3:8b', 'llama3.1:8b']);
      final llama = models.last;
      expect(llama.sizeBytes, 4920753328);
      expect(llama.parameterSize, '8.0B');
      expect(llama.quantization, 'Q4_K_M');
      expect(llama.family, 'llama');
      expect(llama.modifiedAt, DateTime.utc(2026, 8, 1, 10));
      expect(llama.priceClass, isNull);
      expect(await client.toolModels(), ['llama3.1:8b', 'qwen3:8b']);
    });

    test('OpenRouter: name, context, price class; newest first', () async {
      final client = AssistantModelClient(
        const AssistantProviderConfig(
          kind: AssistantProviderKind.openRouter,
          baseUrl: AssistantProviderConfig.openRouterUrl,
          apiKey: 'sk-or',
        ),
        httpClient: MockClient(
          (r) async => _json({
            'data': [
              {
                'id': 'openai/gpt-x',
                'name': 'OpenAI: GPT X',
                'created': 1700000000,
                'context_length': 128000,
                'pricing': {'prompt': '0.0000025', 'completion': '0.00001'},
              },
              {
                'id': 'meta/llama:free',
                'created': 1750000000,
                'context_length': 32768,
                'pricing': {'prompt': '0', 'completion': '0'},
              },
              {
                'id': 'x/cheap',
                'created': 1600000000,
                'pricing': {'prompt': '0.0000001', 'completion': '0.0000002'},
              },
              {
                'id': 'x/dear',
                'created': 1600000001,
                'pricing': {'prompt': '0.000015', 'completion': '0.00006'},
              },
            ],
          }),
        ),
      );
      final models = await client.models();
      expect(models.map((m) => m.id), ['meta/llama:free', 'openai/gpt-x', 'x/dear', 'x/cheap']);
      expect(models.map((m) => m.priceClass), [
        AssistantPriceClass.free,
        AssistantPriceClass.medium,
        AssistantPriceClass.high,
        AssistantPriceClass.low,
      ]);
      expect(models[1].name, 'OpenAI: GPT X');
      expect(models[1].contextLength, 128000);
      expect(models[1].vendor, 'openai');
      expect(models[0].name, 'meta/llama:free');
    });

    test('pull streams progress lines and ends on success', () async {
      late Map<String, Object?> body;
      final client = AssistantModelClient(
        server,
        httpClient: MockClient((r) async {
          expect(r.url.path, '/api/pull');
          body = (jsonDecode(r.body) as Map).cast<String, Object?>();
          return http.Response(
            [
              '{"status":"pulling manifest"}',
              '{"status":"pulling abc","digest":"sha256:abc","total":200,"completed":50}',
              '{"status":"pulling abc","digest":"sha256:abc","total":200,"completed":200}',
              '{"status":"verifying sha256 digest"}',
              '{"status":"success"}',
            ].join('\n'),
            200,
            headers: const {'content-type': 'application/x-ndjson'},
          );
        }),
      );
      final lines = await client.pullModel('qwen3:8b').toList();
      expect(body, {'model': 'qwen3:8b', 'stream': true});
      expect(lines.map((p) => p.status).first, 'pulling manifest');
      expect(lines.map((p) => p.fraction), [null, 0.25, 1.0, null, null]);
      expect(lines.last.isSuccess, isTrue);
    });

    test('pull: an error line becomes AssistantPullException after the progress before it', () async {
      final client = AssistantModelClient(
        server,
        httpClient: MockClient(
          (_) async => http.Response(
            '{"status":"pulling manifest"}\n{"error":"pull model manifest: file does not exist"}\n',
            200,
          ),
        ),
      );
      final seen = <String>[];
      await expectLater(
        client.pullModel('gone:1b').map((p) => seen.add(p.status)).drain<void>(),
        throwsA(isA<AssistantPullException>().having((e) => e.message, 'message', contains('does not exist'))),
      );
      expect(seen, ['pulling manifest']);
    });

    test('pull: a non-2xx answer with an error body is a pull error too', () async {
      final client = AssistantModelClient(
        server,
        httpClient: MockClient((_) async => _json({'error': 'no space left on device'}, status: 500)),
      );
      await expectLater(client.pullModel('qwen3:8b').toList(), throwsA(isA<AssistantPullException>()));
    });

    test('preload sends the model and keep_alive and no prompt', () async {
      late Map<String, Object?> body;
      final client = AssistantModelClient(
        server,
        httpClient: MockClient((r) async {
          expect(r.url.path, '/api/generate');
          body = (jsonDecode(r.body) as Map).cast<String, Object?>();
          return _json({'model': 'qwen3:8b', 'done': true});
        }),
      );
      await client.preload();
      expect(body, {'model': 'qwen3:8b', 'keep_alive': '10m'});
    });

    test('chat marks a vanished model on Ollama 404 and OpenRouter 400', () async {
      for (final (status, text) in [
        (404, '{"error":{"message":"model \\"qwen3:8b\\" not found, try pulling it first"}}'),
        (400, '{"error":{"message":"foo/bar is not a valid model ID","code":400}}'),
      ]) {
        final client = AssistantModelClient(server, httpClient: MockClient((_) async => http.Response(text, status)));
        expect(client.modelMissing, isFalse);
        await expectLater(client.chat(const [], const []), throwsA(isA<AssistantModelException>()));
        expect(client.modelMissing, isTrue, reason: text);
      }
      final other = AssistantModelClient(server, httpClient: MockClient((_) async => http.Response('nope', 500)));
      await expectLater(other.chat(const [], const []), throwsA(isA<AssistantModelException>()));
      expect(other.modelMissing, isFalse);
    });

    test('webSearch: unset follows the kind, an explicit choice round-trips', () {
      final local = AssistantProviderConfig.fromJson({'kind': 'ollamaServer', 'baseUrl': 'http://x'})!;
      expect(local.webSearch, isFalse, reason: 'local stays local');
      expect(local.webSearchChoice, isNull);
      expect(local.toJson().containsKey('webSearch'), isFalse);
      expect(AssistantProviderConfig.fromJson({'kind': 'ollamaCloud'})!.webSearch, isTrue);
      expect(AssistantProviderConfig.fromJson({'kind': 'openRouter'})!.webSearch, isTrue);
      final saved = AssistantProviderConfig.fromJson(
        local.copyWith(webSearch: true, ollamaWebKey: 'ok-web').toJson().cast<String, Object?>(),
      )!;
      expect(saved.webSearch, isTrue);
      expect(saved.ollamaWebKey, 'ok-web');
      final off = AssistantProviderConfig.fromJson({'kind': 'openRouter', 'webSearch': false})!;
      expect(off.webSearch, isFalse);
    });
  });
}
