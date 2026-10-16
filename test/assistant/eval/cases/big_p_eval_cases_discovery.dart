import 'package:pleya/media/media_kind.dart';

import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import 'big_p_eval_cases_support.dart';

// Finding films and series in the library: natural phrasings of the start
// questions, a title that is there and one that is not, an asked count, an
// English question and an empty search (BP-11a2).

final evalDiscoveryCases = <EvalCase>[
  EvalCase(
    id: 'disc-natural-tonight',
    source: 'natuurlijke variant van de startvraag: iets leuks voor vanavond',
    turns: [
      EvalTurn(
        'heb je nog iets leuks voor vanavond?',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'unwatched': true, 'limit': 3}),
          'Dit staat klaar in je bibliotheek en je hebt het nog niet gezien.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'my_watching', 'search_catalog', 'find_media'}),
  ),
  EvalCase(
    id: 'disc-series-unwatched',
    source: 'startvraag: welke series heb ik nog niet gezien',
    turns: [
      EvalTurn(
        'Welke series heb ik nog niet gezien?',
        script: [
          EvalCall('search_catalog', {'kind': 'show', 'unwatched': true, 'limit': 6}),
          'Deze series heb je nog niet gestart.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.show)],
    scripted: const [EvalMinCards(3)],
    soft: const EvalSoft(firstTools: {'search_catalog'}),
  ),
  EvalCase(
    id: 'disc-title-in-library',
    source: 'startvraag: staat deze titel in mijn bibliotheek',
    turns: [
      EvalTurn(
        'Staat Coco in mijn bibliotheek?',
        script: [
          EvalCall('find_title', evalFindArgs(['Coco'])),
          'Ja, «Coco» (2017) staat op je server zolder.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 2)],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'find_title', 'find_media', 'search_catalog'}),
  ),
  EvalCase(
    id: 'disc-title-not-in-library',
    source: 'startvraag: titel die er niet is, zonder te verzinnen',
    turns: [
      EvalTurn(
        'Heb ik Primer?',
        script: [
          EvalCall('find_title', evalFindArgs(['Primer'])),
          'Primer staat niet in je bibliotheek.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 1)],
    soft: const EvalSoft(firstTools: {'find_title', 'find_media'}),
  ),
  EvalCase(
    id: 'disc-keyword',
    source: 'startvraag: zoek op een onderwerp',
    turns: [
      EvalTurn(
        'Zoek iets met dinosaurussen',
        script: [
          EvalCall('search_catalog', {'text': 'Jurassic'}),
          'Dit vond ik over dinosaurussen.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'find_title'}),
  ),
  EvalCase(
    id: 'disc-asked-count-two',
    source: 'startvraag met een aantal: precies twee',
    turns: [
      EvalTurn(
        'Geef me precies twee films die ik nog niet gezien heb',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'unwatched': true, 'limit': 2}),
          'Hier zijn er twee.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.movie), const EvalNotSeen(), const EvalCardCount(max: 2)],
    scripted: const [EvalMinCards(2)],
    soft: const EvalSoft(firstTools: {'search_catalog'}, suggestions: 2),
  ),
  EvalCase(
    id: 'disc-english',
    source: 'Engelse vraag: antwoord in dezelfde taal',
    turns: [
      EvalTurn(
        'Find me a good movie for tonight',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'unwatched': true, 'limit': 3}),
          'Here are three movies from your library that you have not seen.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'my_watching', 'search_catalog'}, language: 'en'),
  ),
  EvalCase(
    id: 'disc-empty-honest',
    source: 'startvraag zonder resultaat: eerlijk zeggen, niets verzinnen',
    turns: [
      EvalTurn(
        'Zoek een film met Bruce Willis',
        script: [
          EvalCall('search_catalog', {'person': 'Bruce Willis', 'kind': 'movie'}),
          'Daar vind ik niets van in je bibliotheek.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 0)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'find_media', 'find_title'}),
  ),
];
