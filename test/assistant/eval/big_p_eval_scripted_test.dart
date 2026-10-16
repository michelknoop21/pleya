import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';
import 'package:pleya/media/ids.dart';

import 'big_p_eval_cases.dart';
import 'big_p_eval_checks.dart';
import 'big_p_eval_fixtures.dart';
import 'big_p_eval_runner.dart';

// The CI runner of the Big P evaluation set (BP-11a): every case against a
// hostile scripted model. The hard checks prove that Pleya's code holds,
// whatever the model sends. A case marked expectFail documents a known bug:
// it passes while the bug is there and fails loudly once the violations are
// gone, so the fix has to remove the marker in the same change.

void main() {
  test('the fixture: about sixty titles, films and series, NL and US ratings, unrated with and without family', () {
    expect(evalTitles.length, inInclusiveRange(55, 65));
    expect({for (final t in evalTitles) t.id}, hasLength(evalTitles.length));
    expect(evalTitles.where((t) => t.isShow), hasLength(greaterThan(15)));
    expect(evalTitles.where((t) => t.certs.isEmpty && t.allowedFor(0, 'NL')), isNotEmpty);
    expect(evalTitles.where((t) => t.certs.isEmpty && !t.allowedFor(17, 'NL')), isNotEmpty);
    expect(evalTitles.where((t) => t.certs.keys.toSet().containsAll({'US'}) && !t.certs.containsKey('NL')), isNotEmpty);
    expect(evalTitles.where((t) => t.seen == EvalSeen.watched), isNotEmpty);
    expect(evalTitles.where((t) => t.seen == EvalSeen.inProgress), isNotEmpty);
    expect(evalTitles.firstWhere((t) => t.title == 'The Bear').item.isWatched, isTrue);
    expect(evalTitles.firstWhere((t) => t.title == 'How I Met Your Mother').item.isPartiallyWatched, isTrue);
  });

  test('the checks see a bad title in a card and in prose, and leave short words alone', () {
    expect(evalNamed('Kijk Jurassic Park of «Up» (2009), ga up.').map((n) => n.fixture?.title), [
      'Jurassic Park',
      'Up',
    ]);
    expect(evalNamed('Kijk «Nachtwacht Express» (2019).').single.fixture, isNull);
    expect(evalTitle('Gremlins')!.allowedFor(3, 'NL'), isFalse);
    expect(evalTitle('Dribbel')!.allowedFor(3, 'NL'), isTrue, reason: 'unrated with a family genre');
    expect(evalTitle('Zomer aan Zee')!.allowedFor(17, 'NL'), isFalse, reason: 'unrated, no family genre');
    expect(evalTitle('Night at the Museum')!.allowedFor(6, 'NL'), isFalse, reason: 'US PG counts as 8');
  });

  test('the fixture server serves search_catalog, so a live model gets real rows', () async {
    final ctx = evalContext(kids: false);
    final tool = assistantTools.firstWhere((t) => t.name == 'search_catalog');
    final out = await tool.run(ctx, ServerId('zolder'), {'text': 'Toy', 'kind': 'movie'});
    expect('${(out as AssistantToolResult).data}', contains('Toy Story'));
  });

  for (final c in bigPEvalCases) {
    test('${c.id} (${c.source})', () async {
      final meter = EvalMeter();
      final o = await runEvalCase(c, modelFor: (turn) => evalScriptedModel(c.turns[turn].script, meter), meter: meter);
      final violations = evalViolations(c, o);
      // BIG_P_EVAL_OUT=1 keeps the records, also of the expected failures.
      if (Platform.environment['BIG_P_EVAL_OUT'] == '1') {
        evalWriteJsonl('scripted', [evalRecord(c, o, model: 'scripted', attempt: 1)]);
      }
      expect(o.turns, hasLength(c.turns.length));
      if (c.expectFail case final marker?) {
        expect(
          violations,
          isNotEmpty,
          reason:
              '${c.id} is marked expectFail: $marker, but every hard check passed. '
              'The bug looks fixed: remove the marker so the case guards the fix.',
        );
        for (final id in c.expectViolations) {
          expect(
            violations.where((v) => v.startsWith('$id:')),
            isNotEmpty,
            reason: '${c.id} ($marker) should still fail on $id; got $violations',
          );
        }
      } else {
        expect(violations, isEmpty, reason: violations.join('\n'));
      }
    });
  }
}
