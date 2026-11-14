import 'package:flutter_test/flutter_test.dart';
import 'package:pleya/assistant/assistant_tools.dart';

import 'eval/big_p_eval_cases.dart';
import 'eval/big_p_eval_runner.dart';
import 'eval/big_p_eval_world.dart';

// A find_title card carries the request option of a title not in the library
// and shows its status. After a request or a cancel in the same ask it shows
// the new status, as the request option cards do (code review of 14 November
// 2026).

const _findPrimer = EvalCall('find_title', {
  'candidates': [
    {'title': 'Primer', 'year': 2004, 'kind': 'movie'},
  ],
});

Future<String?> _matchStatus(List<Object> script, EvalWorld Function() world) async {
  final c = EvalCase(
    id: 'match-status',
    source: 'test',
    world: () async => world(),
    hard: const [],
    turns: [EvalTurn('Primer', confirm: EvalConfirm.yes, script: script)],
  );
  final meter = EvalMeter();
  final o = await runEvalCase(c, modelFor: (i) => evalScriptedModel(c.turns[i].script, meter), meter: meter);
  final matches = o.turns.single.result.displays.whereType<AssistantTitleMatches>().expand((d) => d.matches);
  return matches.where((m) => m.title == 'Primer').single.request?.status;
}

void main() {
  test('after a request in the same ask the match card says requested', () async {
    final before = await _matchStatus([_findPrimer, 'Gevonden.'], () => EvalWorld(seerr: evalSeerr()));
    expect(before, 'not_requested', reason: 'control: the card starts as not requested');
    final after = await _matchStatus([
      _findPrimer,
      const EvalCall('request_title', {'seerr_id': 'movie:14337'}),
      'Aangevraagd.',
    ], () => EvalWorld(seerr: evalSeerr()));
    expect(after, 'requested');
  });

  test('after a cancel in the same ask the match card no longer says requested', () async {
    EvalWorld pending() => EvalWorld(
      seerr: evalSeerr()
        ..search['Primer'] = [
          {
            'id': 14337,
            'mediaType': 'movie',
            'title': 'Primer',
            'releaseDate': '2004-10-08',
            'originalLanguage': 'en',
            'voteCount': 1500,
            'mediaInfo': {'status': 2},
          },
        ]
        ..details['/movie/14337'] = {
          'id': 14337,
          'title': 'Primer',
          'releaseDate': '2004-10-08',
          'mediaInfo': {
            'status': 2,
            'requests': [
              {
                'id': 41,
                'status': 1,
                'is4k': false,
                'requestedBy': {'id': 7},
              },
            ],
          },
        },
    );
    expect(await _matchStatus([_findPrimer, 'Gevonden.'], pending), 'requested', reason: 'control');
    final after = await _matchStatus([
      _findPrimer,
      const EvalCall('cancel_request', {'seerr_id': 'movie:14337'}),
      'Geannuleerd.',
    ], pending);
    expect(after, 'not_requested');
  });
}
