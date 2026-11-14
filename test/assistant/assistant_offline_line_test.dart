import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_run.dart';

import 'eval/big_p_eval_cases.dart';
import 'eval/big_p_eval_checks.dart';
import 'eval/big_p_eval_runner.dart';
import 'eval/big_p_eval_world.dart';

// A search that left out an offline server is a partial result (DEC-142).
// When the model's answer does not name the server, Pleya adds its own line
// (BP-12, found by adm-search-with-offline-server on gemma4:31b, 3 of 3).

Future<String> _answer(String modelText, {bool offline = true, bool second = false}) async {
  final c = EvalCase(
    id: 'offline-line',
    source: 'test',
    world: () async => EvalWorld(offlineServer: offline, secondOfflineServer: second),
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

  // Code review of 14 November 2026: a substring match took any mention of
  // the name for a word about its being offline.
  test('a server named like an ordinary word is not named by using that word', () {
    expect(assistantNamesOffline('Films voor vanavond: Heat en Alien.', 'Films'), isFalse);
    expect(assistantNamesOffline('Films is offline, daar kon ik niet zoeken.', 'Films'), isTrue);
    expect(assistantNamesOffline('De server Plexbak is niet bereikbaar.', 'Plex'), isFalse);
    expect(assistantNamesOffline('Plex: niet bereikbaar.\nDe rest werkte.', 'Plex'), isTrue);
  });

  test('two offline servers where the answer names one: the other still gets its line', () async {
    final text = await _answer('Uit zolder: Heat. Bovenkamer is offline, daar kon ik niet zoeken.', second: true);
    expect(text, contains('kelder is offline, daar kon ik niet zoeken.'));
    expect(text, isNot(contains('bovenkamer is offline')), reason: 'the answer already named it');
  });

  test('an answer that only uses the server\'s name as a word still gets the line', () async {
    final text = await _answer('Uit kelder en zolder samen raad ik Heat aan.');
    expect(text, contains('kelder is offline, daar kon ik niet zoeken.'));
  });
}
