import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/big_p_eval_judge.dart';

// The judge tool (BP-12) with a fake judge model: what it shows the judge,
// how it reads a verdict, and how agreement with a person is counted.

Map<String, Object?> _record({required bool yes, List<Object?> actions = const []}) => {
  'case': 'task-request-yes',
  'model': 'm',
  'attempt': 1,
  'hard_ok': true,
  'infra_error': false,
  'confirm_cards': [
    {'turn': 0, 'kind': 'requestTitle', 'subject': 'Severance', 'items': <String>[], 'yes': yes},
  ],
  'state_before': {'requests': <String>[]},
  'turns': [
    {
      'prompt': 'Vraag Severance voor me aan',
      'tool_results': ['find_request_title -> {"options":[{"title":"Severance"}]}'],
      'displays': [
        {
          'type': 'request_options',
          'cards': [
            {'title': 'Severance', 'year': 2022, 'kind': 'series'},
          ],
        },
      ],
      'actions': actions,
      'state_after': {
        'requests': yes ? ['tv:95396'] : <String>[],
      },
      'answer_shown': 'Severance is aangevraagd.',
      'lead_shown': 'Severance is aangevraagd.',
    },
  ],
};

void main() {
  test('the evidence tells the judge what the user answered and what Pleya did', () {
    final refused = evalEvidence(_record(yes: false));
    expect(refused, contains('the user answered NO'));
    expect(refused, contains('Actions carried out by Pleya: none'));
    expect(refused, contains('Severance (2022) [series]'));
    final done = evalEvidence(
      _record(
        yes: true,
        actions: [
          {'kind': 'requestTitle'},
        ],
      ),
    );
    expect(done, contains('the user answered YES'));
    expect(done, contains('"tv:95396"'));
  });

  test('a verdict is pass, fail or unknown; anything else is unknown', () {
    expect(evalParseVerdict('{"verdict":"fail","reason":"x"}').verdict, 'fail');
    expect(evalParseVerdict('Sure!\n```json\n{"verdict": "PASS", "reason": "ok"}\n```').verdict, 'pass');
    expect(evalParseVerdict('{"verdict":"maybe"}').verdict, 'unknown');
    expect(evalParseVerdict('I think it passes').verdict, 'unknown');
  });

  test('each criterion gets its own call, and a judge error is unknown, not pass', () async {
    final prompts = <String>[];
    final judged = await evalJudgeRecord(_record(yes: false), (prompt) async {
      prompts.add(prompt);
      if (prompt.contains('Criterion "tone"')) throw const HttpException('down');
      // A judge that reads the evidence: a claimed success after a NO fails.
      final fail = prompt.contains('Criterion "grounded"') && prompt.contains('answered NO');
      return jsonEncode({'verdict': fail ? 'fail' : 'pass', 'reason': 'r'});
    }, judge: 'fake');
    expect(prompts, hasLength(evalCriteria.length));
    final v = judged['verdicts']! as Map;
    expect((v['grounded'] as Map)['verdict'], 'fail');
    expect((v['tone'] as Map)['verdict'], 'unknown');
    expect((v['answers'] as Map)['verdict'], 'pass');
  });

  test('agreement counts only labelled rows and shows the fails the judge missed', () {
    Map<String, Object?> row(String judge, String? human) => {
      'verdicts': {
        for (final c in evalCriteria) c.id: {'verdict': judge, 'reason': ''},
      },
      'human': {for (final c in evalCriteria) c.id: human},
    };
    final table = evalAgreement([row('pass', 'pass'), row('pass', 'fail'), row('fail', 'fail'), row('pass', null)]);
    expect(table, contains('| grounded | 3 | 2 | 1 van 2 | 1 van 1 |'));
  });

  test('the CLI judges a file with a given judge and writes verdicts and a sample', () async {
    final dir = Directory.systemTemp.createTempSync('judge');
    addTearDown(() => dir.deleteSync(recursive: true));
    final input = File('${dir.path}/runs.jsonl')
      ..writeAsStringSync(
        '${jsonEncode(_record(yes: true))}\n${jsonEncode({..._record(yes: false), 'infra_error': true})}\n',
      );
    final code = await evalJudgeMain([
      '--in',
      input.path,
      '--sample',
      '5',
      '--labels',
      '${dir.path}/labels.jsonl',
    ], ask: (_) async => '{"verdict":"pass","reason":"ok"}');
    expect(code, 0);
    final out = File('${dir.path}/runs.judged.jsonl').readAsLinesSync();
    expect(out, hasLength(1), reason: 'the provider-error run is left out');
    final label = jsonDecode(File('${dir.path}/labels.jsonl').readAsLinesSync().single) as Map;
    expect((label['human'] as Map).keys, [for (final c in evalCriteria) c.id]);
    expect(label['evidence'], contains('Vraag Severance'));
  });
}
