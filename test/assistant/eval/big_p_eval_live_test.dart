@Tags(['live-model'])
library;

import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:pleya/assistant/assistant_provider.dart';

import 'big_p_eval_cases.dart';
import 'big_p_eval_runner.dart';

// The live runner of the Big P evaluation set (BP-11a): the same cases, the
// real AssistantRun with its system prompt and tool specs, against Ollama
// Cloud. Never in CI: dart_test.yaml skips the live-model tag. By hand:
//
//   vault-exec OLLAMA_CLOUD_API --env-var OLLAMA_CLOUD_API -- \
//     flutter test --tags live-model --run-skipped test/assistant/eval/big_p_eval_live_test.dart
//
// Every case runs three times per model; each run is one JSON line in
// build/big_p_eval/live-<stamp>.jsonl (ignored by version control). Only the summary goes into the
// roadmap. A hard violation in a case without expectFail fails the test; an
// expected failure is only recorded.

const _models = ['glm-5.3-flash', 'gemma4:31b'];
const _attempts = 3;

String? _key() {
  // Only this name: under `vault-exec <other credential>` another secret
  // arrives as VAULT_VALUE and must never go to Ollama Cloud as a bearer key.
  final key = Platform.environment['OLLAMA_CLOUD_API'];
  return key == null || key.trim().isEmpty ? null : key.trim();
}

/// Counts model calls and the `usage.total_tokens` the provider reports.
class _MeteredClient extends http.BaseClient {
  _MeteredClient(this.meter);
  final EvalMeter meter;
  final http.Client _inner = http.Client();

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) async {
    final response = await _inner.send(request);
    meter.calls++;
    if (request is http.Request) meter.observe(request.body);
    final bytes = await response.stream.toBytes();
    try {
      final usage = (jsonDecode(utf8.decode(bytes)) as Map)['usage'];
      if (usage is Map && usage['total_tokens'] is int) meter.tokens += usage['total_tokens'] as int;
    } catch (_) {
      // Not JSON (an error page): no tokens to count.
    }
    return http.StreamedResponse(
      Stream.value(bytes),
      response.statusCode,
      headers: response.headers,
      reasonPhrase: response.reasonPhrase,
      request: response.request,
    );
  }

  @override
  void close() => _inner.close();
}

void main() {
  final stamp = DateTime.now().toUtc().toIso8601String().replaceAll(RegExp(r'[:.]'), '-');

  setUpAll(() => HttpOverrides.global = null);

  for (final model in _models) {
    for (final c in bigPEvalCases) {
      test('$model ${c.id}', timeout: const Timeout(Duration(minutes: 15)), () async {
        final key = _key();
        if (key == null) {
          markTestSkipped(
            'No Ollama Cloud key: run through vault-exec OLLAMA_CLOUD_API --env-var OLLAMA_CLOUD_API -- flutter test ...',
          );
          return;
        }
        final failures = <String>[];
        for (var attempt = 1; attempt <= _attempts; attempt++) {
          final meter = EvalMeter();
          final client = AssistantModelClient(
            AssistantProviderConfig(
              kind: AssistantProviderKind.ollamaCloud,
              baseUrl: AssistantProviderConfig.ollamaCloudUrl,
              model: model,
              apiKey: key,
            ),
            httpClient: _MeteredClient(meter),
          );
          final outcome = await runEvalCase(c, modelFor: (_) => client, meter: meter);
          client.close();
          final record = evalRecord(c, outcome, model: model, attempt: attempt);
          evalWriteJsonl('live-$stamp', [record]);
          final violations = record['violations']! as List;
          if (c.expectFail == null && violations.isNotEmpty) failures.add('attempt $attempt: $violations');
        }
        expect(failures, isEmpty, reason: '$model ${c.id}');
      });
    }
  }
}
