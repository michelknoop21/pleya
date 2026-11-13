import 'package:flutter_test/flutter_test.dart';

import 'big_p_eval_cases.dart';
import 'big_p_eval_checks.dart';
import 'big_p_eval_runner.dart';
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
  test('a task whose card was refused fails its state check', () async {
    for (final id in ['task-home-row-yes', 'task-request-yes', 'task-forget-yes']) {
      final c = _case(id);
      expect(evalViolations(c, await _run(c)), isEmpty, reason: '$id as written');
      final refused = evalViolations(c, await _run(_flip(c, EvalConfirm.no)));
      expect(refused.any((v) => v.startsWith('state:')), isTrue, reason: '$id refused: $refused');
    }
  });

  test('a refused task that is carried out anyway fails state-unchanged', () async {
    for (final id in ['task-home-row-no', 'task-request-no']) {
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
