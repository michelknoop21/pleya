import 'package:flutter_test/flutter_test.dart';

import 'eval/big_p_eval_cases.dart';
import 'eval/big_p_eval_runner.dart';

// A subject search that only read plot summaries and found nothing tells the
// model how to go on (BP-12, disc-keyword: gemma4:31b answered "nothing with
// dinosaurs" with Jurassic Park in the library, 5 of 6 runs).

Future<String> _lastFindAnswer(Map<String, Object?> args) async {
  final c = EvalCase(
    id: 'subject-hint',
    source: 'test',
    hard: const [],
    turns: [
      EvalTurn('Zoek iets met dinosaurussen', script: [EvalCall('find_title', args), 'Niets gevonden.']),
    ],
  );
  final meter = EvalMeter();
  final o = await runEvalCase(c, modelFor: (i) => evalScriptedModel(c.turns[i].script, meter), meter: meter);
  return o.turns.single.toolResults.single.content;
}

void main() {
  test('no match on a subject without candidates carries the hint', () async {
    final answer = await _lastFindAnswer({
      'subject': true,
      'variants': ['dinosaurs', 'dinosaurussen'],
    });
    expect(answer, contains('"matches":[]'));
    expect(answer, contains('"hint"'));
  });

  test('with candidates the library title is found and no hint is needed', () async {
    final answer = await _lastFindAnswer({
      'subject': true,
      'variants': ['dinosaurs', 'dinosaurussen'],
      'candidates': [
        {'title': 'Jurassic Park', 'year': 1993, 'kind': 'movie'},
      ],
    });
    expect(answer, contains('Jurassic Park'));
    expect(answer, isNot(contains('"hint"')));
  });

  test('a search for one specific title gets no hint', () async {
    final answer = await _lastFindAnswer({
      'variants': ['een film die niet bestaat xyz'],
    });
    expect(answer, isNot(contains('"hint"')));
  });
}
