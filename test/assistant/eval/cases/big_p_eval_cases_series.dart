import 'package:pleya/media/media_kind.dart';

import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../checks/big_p_eval_checks_extra.dart';
import 'big_p_eval_cases_support.dart';

// Series: continue watching, how far along, and the new-episode questions
// no source can answer. Those must come back as "I do not know", not as a
// status (BP-11a2).

final evalSeriesCases = <EvalCase>[
  EvalCase(
    id: 'ser-continue-watching',
    source: 'startvraag: verder kijken met een film',
    turns: [
      EvalTurn(
        'Welke film kan ik verder kijken?',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'in_progress': true, 'limit': 8}),
          'Hier ben je nog niet mee klaar.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.movie)],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'my_watching'}),
  ),
  EvalCase(
    id: 'ser-continue-shows-only',
    source: 'natuurlijke variant: welke serie ben ik aan het kijken',
    turns: [
      EvalTurn(
        'Welke serie ben ik nu aan het kijken?',
        script: [
          EvalCall('search_catalog', {'kind': 'show', 'in_progress': true, 'limit': 8}),
          'Deze series heb je gestart.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.show)],
    scripted: const [EvalMinCards(2)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'my_watching'}),
  ),
  EvalCase(
    id: 'ser-new-episodes-no-source',
    source: 'voorstel: nieuwe afleveringen, geen bron',
    turns: [
      EvalTurn(
        'Zijn er nieuwe afleveringen van Bluey?',
        script: [
          EvalCall('find_title', evalFindArgs(['Bluey'])),
          'Bluey staat in je bibliotheek, maar of er nieuwe afleveringen zijn weet ik niet: daar heb ik geen bron voor.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalHonestMissing()],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'find_title', 'search_catalog'}),
  ),
  EvalCase(
    id: 'ser-next-season-no-source',
    source: 'voorstel: wanneer komt het volgende seizoen, geen bron',
    turns: [
      EvalTurn(
        'Wanneer komt het volgende seizoen van The Bear?',
        script: [
          EvalCall('find_title', evalFindArgs(['The Bear'])),
          'Dat weet ik niet. Ik zie alleen wat in je bibliotheek staat, niet wanneer er een nieuw seizoen komt.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalHonestMissing()],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'find_title', 'search_catalog'}),
  ),
  EvalCase(
    id: 'ser-finished-show',
    source: 'voorstel: heb ik deze serie al uit',
    turns: [
      EvalTurn(
        'Heb ik Friends al helemaal gezien?',
        script: [
          EvalCall('find_title', evalFindArgs(['Friends'])),
          'Volgens je bibliotheek heb je alle afleveringen van «Friends» (1994) gezien.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 2)],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'find_title', 'search_catalog'}),
  ),
  EvalCase(
    id: 'ser-how-far',
    source: 'voorstel: hoe ver ben ik in een serie',
    turns: [
      EvalTurn(
        'Hoe ver ben ik met How I Met Your Mother?',
        script: [
          EvalCall('find_title', evalFindArgs(['How I Met Your Mother'])),
          'Je bent begonnen aan «How I Met Your Mother» (2005).',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 2)],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'find_title', 'search_catalog'}),
  ),
  EvalCase(
    id: 'ser-short-series',
    source: 'natuurlijke formulering: een serie voor tussendoor',
    turns: [
      EvalTurn(
        'een serie voor tussendoor die ik nog niet ken',
        script: [
          EvalCall('search_catalog', {'kind': 'show', 'unwatched': true, 'limit': 3}),
          'Drie series om mee te beginnen.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.show), const EvalNotSeen()],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'my_watching'}),
  ),
];
