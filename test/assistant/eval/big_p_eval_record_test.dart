import 'package:flutter_test/flutter_test.dart';

import 'big_p_eval_cases.dart';
import 'big_p_eval_runner.dart';

// The record schema the A/B report reads (BP-11a2): every run says which
// checkout it came from and under which label.

void main() {
  test('a record names its checkout and carries the label slot', () async {
    final c = bigPEvalCases.firstWhere((c) => c.id == 'disc-natural-tonight');
    final meter = EvalMeter();
    final o = await runEvalCase(c, modelFor: (t) => evalScriptedModel(c.turns[t].script, meter), meter: meter);
    final record = evalRecord(c, o, model: 'scripted', attempt: 1);
    expect(record['git_sha'], allOf(isA<String>(), isNotEmpty), reason: 'a sha, +dirty, or unknown outside git');
    expect(record.containsKey('label'), isTrue);
    expect(record['case'], 'disc-natural-tonight');
    // The report reads these keys; a rename here must break this test first.
    for (final key in ['model', 'attempt', 'expect_fail', 'hard_ok', 'violations', 'turns', 'infra_error']) {
      expect(record.containsKey(key), isTrue, reason: key);
    }
    final turn = (record['turns']! as List).single as Map;
    for (final key in ['first_tool', 'first_tool_ok', 'latency_ms', 'tokens', 'end', 'provider_error', 'tool_trace']) {
      expect(turn.containsKey(key), isTrue, reason: key);
    }
  });
}
