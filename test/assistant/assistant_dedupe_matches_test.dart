import 'package:flutter_test/flutter_test.dart';

import 'eval/big_p_eval_cases.dart';
import 'eval/big_p_eval_checks.dart';
import 'eval/big_p_eval_runner.dart';

// One card per title across a search grid and a title lookup in the same ask
// (BP-12, disc-keyword on glm-5.3-flash: Jurassic Park shown twice).

Future<List<String>> _cards(List<Object> script) async {
  final c = EvalCase(
    id: 'dedupe',
    source: 'test',
    hard: const [],
    turns: [EvalTurn('Zoek iets met dinosaurussen', script: script)],
  );
  final meter = EvalMeter();
  final o = await runEvalCase(c, modelFor: (i) => evalScriptedModel(c.turns[i].script, meter), meter: meter);
  return [for (final card in evalCards(o.turns.single.result)) card.title];
}

const _search = EvalCall('search_catalog', {'text': 'Jurassic'});
const _find = EvalCall('find_title', {
  'subject': true,
  'variants': ['dinosaurs', 'dinosaurussen'],
  'candidates': [
    {'title': 'Jurassic Park', 'year': 1993, 'kind': 'movie'},
  ],
});

void main() {
  test('a grid first and a title lookup after it show the title once', () async {
    expect(await _cards([_search, _find, 'Dit vond ik.']), ['Jurassic Park']);
  });

  test('a title lookup first and a grid after it show the title once', () async {
    expect(await _cards([_find, _search, 'Dit vond ik.']), ['Jurassic Park']);
  });

  test('each alone still shows its card', () async {
    expect(await _cards([_search, 'Dit vond ik.']), ['Jurassic Park']);
    expect(await _cards([_find, 'Dit vond ik.']), ['Jurassic Park']);
  });
}
