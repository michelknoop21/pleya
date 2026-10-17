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
    expect(evalTitles.where((t) => t.certs.isEmpty && t.allowedFor(6, 'NL')), isNotEmpty);
    expect(evalTitles.where((t) => t.certs.isEmpty && !t.allowedFor(17, 'NL')), isNotEmpty);
    expect(evalTitles.where((t) => t.certs.containsKey('US') && !t.certs.containsKey('NL')), isNotEmpty);
    expect(evalTitles.where((t) => t.seen == EvalSeen.watched), isNotEmpty);
    expect(evalTitles.where((t) => t.seen == EvalSeen.inProgress), isNotEmpty);
    expect(evalTitles.firstWhere((t) => t.title == 'The Bear').item.isWatched, isTrue);
    expect(evalTitles.firstWhere((t) => t.title == 'How I Met Your Mother').item.isPartiallyWatched, isTrue);
  });

  test('the tip score sees a question and more titles than cards, and passes a statement', () async {
    final tip = bigPEvalCases.firstWhere((c) => c.id == 'adult-tip-statement');
    final meter = EvalMeter();
    final bad = await runEvalCase(tip, modelFor: (t) => evalScriptedModel(tip.turns[t].script, meter), meter: meter);
    final r = bad.turns.single.result;
    expect(evalAsksQuestion(r.text), isTrue);
    // Since BP-10 (#361) the shown text follows the cards, so the sentences
    // that named a title without a card are gone. The check still counts
    // titles when it is handed text that was not trimmed.
    expect(evalNamed(r.text).length, 1, reason: 'the shown text names only the card');
    expect(
      evalNamed('Hoe klinkt «The Office» (2005)? Of «Sherlock» (2010), of «Brooklyn Nine-Nine» (2013)?').length,
      3,
    );
    expect(evalCards(r).length, 1, reason: 'one asked tip caps the cards');
    expect(evalTipOk(r), isFalse);

    final good = bigPEvalCases.firstWhere((c) => c.id == 'adult-three-tips');
    final ok = await runEvalCase(good, modelFor: (t) => evalScriptedModel(good.turns[t].script, meter), meter: meter);
    expect(evalTipOk(ok.turns.single.result), isTrue);
    expect(evalAsksQuestion('Kijk «Sherlock» (2010). Het is een stelling.'), isFalse);
  });

  test('the checks see a bad title in a card and in prose, and leave short words alone', () {
    expect(evalNamed('Kijk Jurassic Park of «Up» (2009), ga up.').map((n) => n.fixture?.title), [
      'Jurassic Park',
      'Up',
    ]);
    expect(evalNamed('Kijk «Nachtwacht Express» (2019).').single.fixture, isNull);
    expect(evalTitle('Gremlins')!.allowedFor(3, 'NL'), isFalse);
    expect(evalTitle('Dribbel')!.allowedFor(6, 'NL'), isTrue, reason: 'unrated with a family genre, from 6');
    expect(evalTitle('Dribbel')!.allowedFor(3, 'NL'), isFalse, reason: 'unrated never passes under 6');
    expect(evalTitle('Zomer aan Zee')!.allowedFor(17, 'NL'), isFalse, reason: 'unrated, no family genre');
    expect(evalTitle('Night at the Museum')!.allowedFor(6, 'NL'), isFalse, reason: 'US PG counts as 8');
  });

  // Every card check is vacuous on an empty result, so the fixture has to
  // hand out real, actionable cards on each read path the cases use.
  group('the fixture server hands out actionable cards', () {
    Future<AssistantToolResult> run(String tool, Map<String, Object?> args) async {
      final t = assistantTools.firstWhere((t) => t.name == tool);
      return await t.run(evalContext(kids: false), ServerId('zolder'), args) as AssistantToolResult;
    }

    test('search_catalog by text', () async {
      final out = await run('search_catalog', {'text': 'Toy', 'kind': 'movie'});
      expect('${out.data}', contains('Toy Story'));
    });

    test('search_catalog on the paged library read: movies and series, with watch state', () async {
      for (final kind in ['movie', 'show']) {
        final out = await run('search_catalog', {'kind': kind, 'limit': 20});
        final grid = out.display! as AssistantMediaGrid;
        expect(grid.entries, hasLength(greaterThan(5)), reason: kind);
        expect(grid.entries.every((e) => e.item.serverId == 'zolder'), isTrue, reason: kind);
      }
      final unwatched = await run('search_catalog', {'kind': 'show', 'unwatched': true, 'limit': 50});
      final titles = [for (final e in (unwatched.display! as AssistantMediaGrid).entries) e.item.title];
      expect(titles, isNot(contains('The Bear')), reason: 'a watched series is not unwatched');
      expect(titles, contains('Bluey'));
    });

    test('find_title: a library title is a card that can be opened', () async {
      final out = await run('find_title', {
        'candidates': [
          {'title': 'Toy Story'},
        ],
        'variants': ['Toy Story', 'toy story'],
      });
      final matches = (out.display! as AssistantTitleMatches).matches;
      expect(matches.where((m) => m.title == 'Toy Story' && m.targets.isNotEmpty), isNotEmpty);
    });
  });

  for (final c in bigPEvalCases) {
    test('${c.id} (${c.source})', () async {
      final meter = EvalMeter();
      final o = await runEvalCase(c, modelFor: (turn) => evalScriptedModel(c.turns[turn].script, meter), meter: meter);
      final violations = evalViolations(c, o);
      // The case did what it claims, marked or not.
      expect([for (final h in c.scripted) ...h.check(o)], isEmpty, reason: 'scripted checks of ${c.id}');
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
        for (final prefix in c.expectViolations) {
          expect(
            violations.where((v) => v.startsWith(prefix)),
            isNotEmpty,
            reason: '${c.id} ($marker) should still fail on "$prefix"; got $violations',
          );
        }
      } else {
        expect(violations, isEmpty, reason: violations.join('\n'));
      }
    });
  }
}
