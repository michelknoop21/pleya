import 'package:flutter_test/flutter_test.dart';

import 'eval/big_p_eval_cases.dart';
import 'eval/big_p_eval_checks.dart';
import 'eval/big_p_eval_runner.dart';
import 'eval/big_p_eval_world.dart';

// A search that left out an offline server is a partial result (DEC-142).
// When the model's answer does not name the server, Pleya adds its own line
// (BP-12, found by adm-search-with-offline-server on gemma4:31b, 3 of 3).

Future<String> _answer(String modelText, {bool offline = true}) async {
  final c = EvalCase(
    id: 'offline-line',
    source: 'test',
    world: () async => EvalWorld(offlineServer: offline),
    hard: const [],
    turns: [
      EvalTurn(
        'Zoek een film voor vanavond',
        script: [
          const EvalCall('search_catalog', {'kind': 'movie', 'limit': 3}),
          modelText,
        ],
      ),
    ],
  );
  final meter = EvalMeter();
  final EvalOutcome o = await runEvalCase(
    c,
    modelFor: (i) => evalScriptedModel(c.turns[i].script, meter),
    meter: meter,
  );
  return o.turns.single.result.text;
}

void main() {
  test('an answer that leaves out the offline server gets Pleya\'s own line', () async {
    final text = await _answer('Hier zijn een paar suggesties uit je bibliotheek.');
    expect(text, startsWith('Hier zijn een paar suggesties uit je bibliotheek.'));
    expect(text, contains('kelder is offline, daar kon ik niet zoeken.'));
  });

  test('an answer that names the server is left as it is', () async {
    const said = 'Dit komt van zolder. Kelder is offline, daar kon ik niet zoeken.';
    expect(await _answer(said), said);
  });

  test('without an offline server nothing is added', () async {
    const said = 'Hier zijn een paar suggesties uit je bibliotheek.';
    expect(await _answer(said, offline: false), said);
  });
}
