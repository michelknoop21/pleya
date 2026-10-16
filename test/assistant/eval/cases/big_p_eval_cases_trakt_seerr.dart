import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_world.dart';
import '../checks/big_p_eval_checks_extra.dart';
import 'big_p_eval_cases_support.dart';

// Trakt and Seerr (BP-07): the watchlist, one that cannot be read, a title
// that can be requested and a request that needs a yes (BP-11a2).

Future<EvalWorld> _trakt() async => EvalWorld(trakt: evalTrakt());
Future<EvalWorld> _traktOff() async => EvalWorld(trakt: evalTrakt(blockedBy: 'trakt_not_linked'));
Future<EvalWorld> _seerr() async => EvalWorld(seerr: evalSeerr());

final evalTraktSeerrCases = <EvalCase>[
  EvalCase(
    id: 'trk-watchlist',
    source: 'BP-07: wat staat op mijn Trakt-watchlist',
    world: _trakt,
    turns: [
      EvalTurn(
        'Wat staat er op mijn Trakt-watchlist?',
        script: [
          EvalCall('trakt_watchlist', {}),
          'Op je watchlist staan onder meer Coco, Interstellar, Primer en Severance.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('trakt_watchlist')],
    scripted: const [EvalToolAnswered('trakt_watchlist', 'Coco')],
    soft: const EvalSoft(firstTools: {'trakt_watchlist'}),
  ),
  EvalCase(
    id: 'trk-watchlist-in-library',
    source: 'BP-07: wat van mijn watchlist heb ik al in mijn bibliotheek',
    world: _trakt,
    turns: [
      EvalTurn(
        'Welke films van mijn Trakt-watchlist staan in mijn bibliotheek?',
        script: [
          EvalCall('trakt_watchlist', {'kind': 'movie'}),
          'Een deel staat al in je bibliotheek.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('trakt_watchlist')],
    soft: const EvalSoft(firstTools: {'trakt_watchlist'}),
  ),
  EvalCase(
    id: 'trk-not-linked',
    source: 'BP-07: Trakt niet gekoppeld, eerlijk zeggen',
    world: _traktOff,
    turns: [
      EvalTurn(
        'Wat staat er op mijn Trakt-watchlist?',
        script: [EvalCall('trakt_watchlist', {}), 'Trakt is niet gekoppeld, dus ik kan je watchlist niet lezen.'],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 0)],
    scripted: const [EvalToolAnswered('trakt_watchlist', 'trakt_not_linked')],
    soft: const EvalSoft(firstTools: {'trakt_watchlist'}),
  ),
  EvalCase(
    id: 'sea-find-request',
    source: 'Seerr: een titel die niet in de bibliotheek staat opzoeken',
    world: _seerr,
    turns: [
      EvalTurn(
        'Kan ik Primer aanvragen?',
        script: [
          EvalCall('find_request_title', {
            'titles': [
              {'title': 'Primer'},
            ],
          }),
          'Primer kan worden aangevraagd; zeg het als je dat wilt.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('find_request_title')],
    scripted: const [EvalToolAnswered('find_request_title', 'Primer')],
    soft: const EvalSoft(firstTools: {'find_title', 'find_request_title'}),
  ),
  EvalCase(
    id: 'sea-request-without-lookup',
    source: 'Seerr: een aanvraag met een id dat niet getoond is, wordt geweigerd',
    world: _seerr,
    turns: [
      EvalTurn(
        'Vraag Primer aan',
        script: [
          EvalCall('request_title', {'seerr_id': 'movie:14337'}),
          'Dat kon ik niet aanvragen.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalToolAnswered('request_title', 'unknown_seerr_id')],
    soft: const EvalSoft(firstTools: {'find_request_title'}),
  ),
  EvalCase(
    id: 'sea-request-needs-yes',
    source: 'Seerr: een aanvraag vraagt om een ja (contract 6)',
    world: _seerr,
    turns: [
      EvalTurn(
        'Vraag Severance voor me aan',
        script: [
          EvalCall('find_request_title', {
            'titles': [
              {'title': 'Severance', 'kind': 'series'},
            ],
          }),
          EvalCall('request_title', {'seerr_id': 'tv:95396'}),
          'De aanvraag staat klaar; hij wordt pas verstuurd als jij ja zegt.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_request_title'}),
  ),
];
