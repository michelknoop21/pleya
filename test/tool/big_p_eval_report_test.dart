import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import '../../tool/big_p_eval_report.dart';

// The A/B report of the Big P evaluation set (BP-11a2), on two small runs
// with a known outcome (test/fixtures/big_p_eval): one case that holds in
// both, one that regresses, one that improves, one that turns flaky, one that
// keeps failing, a known bug, and a case only one side has.

const _base = 'test/fixtures/big_p_eval/report_base.jsonl';
const _cand = 'test/fixtures/big_p_eval/report_candidate.jsonl';

EvalDiff _diff({String? model}) =>
    EvalDiff(evalGroups(evalReadJsonl(_base), model: model), evalGroups(evalReadJsonl(_cand), model: model));

void main() {
  test('groups by case and model and counts a flaky group between pass and fail', () {
    final groups = evalGroups(evalReadJsonl(_cand));
    expect(groups, hasLength(7));
    expect(groups[(caseId: 'c-flaky', model: 'm2')]!.status, EvalGroupStatus.flaky);
    expect(groups[(caseId: 'c-flaky', model: 'm2')]!.passed, 2);
    expect(groups[(caseId: 'c-pass', model: 'm1')]!.status, EvalGroupStatus.pass);
    expect(groups[(caseId: 'c-regress', model: 'm1')]!.status, EvalGroupStatus.fail);
  });

  test('passed x/N skips the known bug; improved and regressed are the ranked changes', () {
    final d = _diff();
    expect(EvalDiff.score(d.base.values), (4, 6), reason: 'c-known is not counted');
    expect(EvalDiff.score(d.candidate.values), (3, 6));
    expect([for (final c in d.improved) c.candidate.caseId], ['c-improve']);
    expect(
      [for (final c in d.regressed) c.candidate.caseId],
      ['c-regress', 'c-flaky'],
      reason: 'sorted by model, pass to flaky counts',
    );
    expect([for (final g in d.onlyBase) g.caseId], ['c-gone']);
    expect([for (final g in d.onlyCandidate) g.caseId], ['c-new']);
  });

  test('a regression names its violation, first tool, latency and tokens', () {
    final change = _diff().regressed.firstWhere((c) => c.candidate.caseId == 'c-regress');
    expect(change.newViolations, {'max-age-5: turn 0 card «Saw»'});
    expect(change.candidate.firstTool, 'find_title');
    expect(change.candidate.firstToolOk, isFalse);
    expect(change.candidate.medianLatencyMs, 3200, reason: 'median of 3100, 3200, 3300');
    expect(change.candidate.medianTokens, 900);
    expect(change.base.medianLatencyMs, 1000);
  });

  test('the rendered report carries the numbers and the cases', () {
    final text = _diff().render();
    expect(text, contains('base base@aaa1111 -> candidate cand@bbb2222'));
    expect(text, contains('geslaagd   base 4/6   candidate 3/6'));
    expect(text, contains('verbeterd  1   regressies 2'));
    expect(text, contains('c-regress [m1]  pass 3/3 -> fail 0/3'));
    expect(text, contains('nieuw: max-age-5: turn 0 card «Saw»'));
    expect(text, contains('c-flaky [m2]  pass 3/3 -> flaky 2/3'));
    expect(text, contains('c-improve [m1]  fail 0/3 -> pass 3/3'));
    expect(text, contains('Blijft mislukt:'));
    expect(text, contains('ook in base: kind-movie: turn 0 card «The Bear» is a show'));
    expect(text, contains('c-known [m1]  BP-11d'));
    expect(text, contains('Alleen in candidate: c-new [m1]'));
    expect(text, contains('Alleen in base: c-gone [m1]'));
  });

  test('--model narrows both runs; --strict fails on a regression only', () {
    final m2 = _diff(model: 'm2');
    expect(m2.candidate.keys.map((k) => k.model).toSet(), {'m2'});
    expect(m2.regressed, hasLength(1));
    expect(evalReportMain(['--base', _base, '--candidate', _cand]), 0);
    expect(evalReportMain(['--base', _base, '--candidate', _cand, '--strict']), 1);
    expect(evalReportMain(['--base', _base, '--candidate', _base, '--strict']), 0, reason: 'a run against itself');
    expect(evalReportMain(['--base', _base]), 64);
  });

  test('--strict also fails on a candidate that is empty, filtered away or missing cases', () {
    final dir = Directory.systemTemp.createTempSync('bp_report');
    addTearDown(() => dir.deleteSync(recursive: true));
    final empty = File('${dir.path}/empty.jsonl')..writeAsStringSync('');
    expect(evalReportMain(['--base', _base, '--candidate', empty.path, '--strict']), 1);
    expect(evalReportMain(['--base', _base, '--candidate', _cand, '--model', 'typo', '--strict']), 1);
    // The candidate holds one record of the base: the rest is missing.
    final one = File('${dir.path}/one.jsonl')..writeAsStringSync(File(_base).readAsLinesSync().first);
    expect(evalReportMain(['--base', _base, '--candidate', one.path, '--strict']), 1);
    expect(_diff().incomplete, isTrue, reason: 'c-gone is missing from the candidate');
  });

  test('a known bug that gets worse is no regression, one that holds again is an improvement', () {
    EvalGroup group(bool ok, int attempts) => EvalGroup('k', 'm', [
      for (var i = 0; i < attempts; i++)
        {'case': 'k', 'model': 'm', 'expect_fail': 'BP-11d', 'hard_ok': i == 0 ? true : ok},
    ]);
    expect(EvalChange(group(true, 3), group(false, 3)).delta, 0, reason: 'flaky/fail stays known, never negative');
    final fixed = EvalChange(
      EvalGroup('k', 'm', [
        {'case': 'k', 'model': 'm', 'expect_fail': 'BP-11d', 'hard_ok': false},
      ]),
      EvalGroup('k', 'm', [
        {'case': 'k', 'model': 'm', 'expect_fail': 'BP-11d', 'hard_ok': true},
      ]),
    );
    expect(fixed.delta, greaterThan(0));
  });

  test('a case that is newly marked expect_fail in the candidate makes the comparison incomplete', () {
    EvalGroup group(bool known) => EvalGroup('x', 'm', [
      {'case': 'x', 'model': 'm', if (known) 'expect_fail': 'BP-11z', 'hard_ok': !known},
    ]);
    const key = (caseId: 'x', model: 'm');
    final diff = EvalDiff({key: group(false)}, {key: group(true)});
    expect(diff.newlyKnown, hasLength(1));
    expect(diff.incomplete, isTrue);
    expect(diff.render(), contains('Nieuw als bekende fout'));
  });

  test('bad input gives a usage or input exit code, not a stack trace', () {
    final dir = Directory.systemTemp.createTempSync('bp_report');
    addTearDown(() => dir.deleteSync(recursive: true));
    final junk = File('${dir.path}/junk.jsonl')..writeAsStringSync('not json\n');
    final noModel = File('${dir.path}/nomodel.jsonl')..writeAsStringSync('{"case":"a"}\n');
    expect(evalReportMain(['--base', _base, '--candidate']), 64);
    expect(evalReportMain(['--base', _base, '--candidate', '--strict']), 64);
    expect(evalReportMain(['--base', _base, '--candidate', '${dir.path}/missing.jsonl']), 66);
    expect(evalReportMain(['--base', _base, '--candidate', junk.path]), 65);
    expect(evalReportMain(['--base', _base, '--candidate', noModel.path]), 65);
  });

  test('the median of an even number of attempts is the mean of the middle two', () {
    final g = EvalGroup('c', 'm', [
      for (final ms in [1000, 5000])
        {
          'case': 'c',
          'model': 'm',
          'hard_ok': true,
          'turns': [
            {'latency_ms': ms, 'tokens': 10},
          ],
        },
    ]);
    expect(g.medianLatencyMs, 3000);
  });

  test('runs that ended in a provider error are left out and flagged, never scored', () {
    Map<String, Object?> rec(String c, bool ok, {bool infra = false}) => {
      'case': c,
      'model': 'm',
      'hard_ok': ok,
      'infra_error': infra,
    };
    final base = [rec('a', true), rec('a', true), rec('b', true)];
    final candidate = [rec('a', true), rec('a', false, infra: true), rec('b', false, infra: true)];
    final diff = EvalDiff(
      evalGroups(base),
      evalGroups(candidate),
      infraBase: evalInfraRuns(base),
      infraCandidate: evalInfraRuns(candidate),
    );
    expect(diff.candidate.keys.map((k) => k.caseId), ['a'], reason: 'b has no usable run');
    expect(diff.candidate.values.single.attempts, 1, reason: 'the provider error is not an attempt');
    expect(diff.regressed, isEmpty, reason: 'a provider error is no regression');
    expect(diff.incomplete, isTrue);
    expect(diff.render(), contains('Providerfout, niet meegeteld (candidate): 2 runs in 2 cases'));
  });
}
