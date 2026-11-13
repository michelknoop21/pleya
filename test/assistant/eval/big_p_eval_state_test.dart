import 'package:flutter_test/flutter_test.dart';

import 'big_p_eval_cases.dart';
import 'big_p_eval_checks.dart';
import 'big_p_eval_runner.dart';
import 'checks/big_p_eval_checks_extra.dart';
import 'checks/big_p_eval_checks_state.dart';

// The state checks grade the eval world, not the model's words (BP-12).
// Each test is a negative control: the same case with the user's answer
// turned around must fail its state check.

EvalCase _case(String id) => bigPEvalCases.firstWhere((c) => c.id == id);

EvalCase _flip(EvalCase c, EvalConfirm answer) => EvalCase(
  id: c.id,
  source: c.source,
  world: c.world,
  hard: c.hard,
  turns: [for (final t in c.turns) EvalTurn(t.prompt, script: t.script, confirm: answer)],
);

Future<EvalOutcome> _run(EvalCase c) {
  final meter = EvalMeter();
  return runEvalCase(c, modelFor: (i) => evalScriptedModel(c.turns[i].script, meter), meter: meter);
}

void main() {
  stepLimitTests();
  homeRowTests();
  test('a task whose card was refused fails its state check', () async {
    for (final id in [
      'task-home-row-yes',
      'task-request-yes',
      'task-forget-yes',
      'task-cancel-request-yes',
      'task-home-row-rename-yes',
      'task-home-row-remove-yes',
    ]) {
      final c = _case(id);
      expect(evalViolations(c, await _run(c)), isEmpty, reason: '$id as written');
      final refused = evalViolations(c, await _run(_flip(c, EvalConfirm.no)));
      expect(refused.any((v) => v.startsWith('state:')), isTrue, reason: '$id refused: $refused');
    }
  });

  test('a refused task that is carried out anyway fails state-unchanged', () async {
    for (final id in [
      'task-home-row-no',
      'task-request-no',
      'task-cancel-request-no',
      'task-home-row-rename-no',
      'task-home-row-remove-no',
    ]) {
      final c = _case(id);
      expect(evalViolations(c, await _run(c)), isEmpty, reason: '$id as written');
      final done = evalViolations(c, await _run(_flip(c, EvalConfirm.yes)));
      expect(done.any((v) => v.startsWith('state-unchanged:')), isTrue, reason: '$id carried out: $done');
    }
  });

  test('a forgotten fact that stays fails, and a kept fact that goes fails', () async {
    final keep = _case('task-forget-no');
    final gone = evalViolations(keep, await _run(_flip(keep, EvalConfirm.yes)));
    expect(gone.any((v) => v.startsWith('state:')), isTrue, reason: '$gone');
  });

  test('after a sent request the card says requested; after a refused one it still offers it', () async {
    String status(Map record) =>
        ((((record['turns'] as List).last as Map)['displays'] as List).first as Map)['cards'][0]['status'] as String;
    final yes = _case('task-request-yes');
    expect(status(evalRecord(yes, await _run(yes), model: 's', attempt: 1)), 'requested');
    final no = _case('task-request-no');
    expect(status(evalRecord(no, await _run(no), model: 's', attempt: 1)), 'not_requested');
  });

  test('the record carries what the user sees and the world after the turn', () async {
    final c = _case('task-request-yes');
    final record = evalRecord(c, await _run(c), model: 'scripted', attempt: 1);
    final turn = (record['turns']! as List).single as Map;
    expect((record['confirm_cards']! as List).single, containsPair('yes', true));
    expect((turn['actions'] as List).single, containsPair('kind', 'requestTitle'));
    expect((turn['state_after'] as Map)['requests'], ['tv:95396']);
    expect(turn['answer_shown'], isNotEmpty);
    expect(const EvalStateUnchanged().id, 'state-unchanged');
  });
}

// A run that hits the step limit never answered: what its searches turned up
// on the way was not chosen by anyone. In the live run "a film with Bruce
// Willis" ended in "too many steps" above ten unrelated films (BP-12).
void homeRowTests() {
  test('a Home row is only accepted by a ref this run listed', () async {
    final base = _case('task-home-row-remove-yes');
    final c = EvalCase(
      id: 'home-row-unknown-ref',
      source: 'rij zonder lijst: geweigerd',
      world: base.world,
      hard: const [EvalStateUnchanged()],
      turns: [
        EvalTurn(
          'Haal de rij Kerstfilms weg',
          confirm: EvalConfirm.yes,
          script: [
            EvalCall('remove_home_row', {'row_id': 'r2'}),
            EvalCall('rename_home_row', {'row_id': 'row-2', 'title': 'X'}),
            'Dat lukte niet.',
          ],
        ),
      ],
    );
    final outcome = await _run(c);
    expect(evalViolations(c, outcome), isEmpty);
    final turn = (evalRecord(c, outcome, model: 's', attempt: 1)['turns'] as List).single as Map;
    expect((turn['tool_results'] as List).every((r) => '$r'.contains('unknown_row_id')), isTrue, reason: '$turn');
    expect(turn['actions'], isEmpty);
  });
}

void stepLimitTests() {
  test('a run that ends on the step limit shows no cards from its searches', () async {
    final c = EvalCase(
      id: 'step-limit-no-cards',
      source: 'stappenlimiet: geen kaarten van onderweg',
      hard: const [EvalCardCount(max: 0)],
      turns: [
        EvalTurn(
          'Zoek een film met Bruce Willis',
          script: [
            for (var i = 0; i < 8; i++) EvalCall('search_catalog', {'kind': 'movie', 'limit': 5, 'offset': i * 5}),
          ],
        ),
      ],
    );
    final outcome = await _run(c);
    final record = evalRecord(c, outcome, model: 's', attempt: 1);
    expect(((record['turns'] as List).single as Map)['end'], 'stepLimit');
    expect(evalViolations(c, outcome), isEmpty);
  });
}
