import 'package:pleya/media/media_kind.dart';

import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../checks/big_p_eval_checks_extra.dart';
import 'big_p_eval_cases_support.dart';

// Recommendations and follow-ups: "those I saw, five others", a switch from
// films to series, a recent addition, a source that is not there (BP-11a2).

final evalRecommendCases = <EvalCase>[
  EvalCase(
    id: 'rec-what-would-i-like',
    source: 'startvraag: wat zou ik leuk vinden',
    personal: true,
    turns: [
      EvalTurn(
        'Wat zou ik leuk vinden?',
        script: [
          EvalCall('my_watching', {}),
          'Op basis van wat je keek: «The Office» (2005), «Sherlock» (2010) en «Brooklyn Nine-Nine» (2013).',
        ],
      ),
    ],
    hard: [...evalBase, const EvalNotSeen(), const EvalToolUsed('my_watching'), const EvalCardsMatchText()],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'my_watching'}),
  ),
  EvalCase(
    id: 'rec-seen-five-others',
    source: 'voorstel: die heb ik gezien, geef me er vijf andere',
    personal: true,
    turns: [
      EvalTurn(
        'Geef me een paar series voor vanavond',
        script: [
          EvalCall('my_watching', {'kind': 'show'}),
          'Probeer «The Office» (2005), «Sherlock» (2010) of «Brooklyn Nine-Nine» (2013).',
        ],
      ),
      EvalTurn(
        'die heb ik al gezien, geef me er vijf andere',
        script: [
          EvalCall('search_catalog', {'kind': 'show', 'unwatched': true, 'limit': 5, 'sort': 'title'}),
          'Dit zijn vijf andere series.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalNotSeen(), const EvalNotRepeated(), const EvalCardCount(max: 5, turn: 1)],
    scripted: const [EvalMinCards(1), EvalMinCards(3, turn: 1)],
    soft: const EvalSoft(firstTools: {'my_watching', 'search_catalog'}, suggestions: 5),
  ),
  EvalCase(
    id: 'rec-switch-to-series',
    source: 'voorstel: en nu een serie',
    turns: [
      EvalTurn(
        'Een film voor vanavond',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'unwatched': true, 'limit': 3}),
          'Drie films.',
        ],
      ),
      EvalTurn(
        'en nu liever een serie',
        script: [
          EvalCall('search_catalog', {'kind': 'show', 'unwatched': true, 'limit': 3}),
          'Drie series.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.show, fromTurn: 1), const EvalNotRepeated()],
    scripted: const [EvalMinCards(1), EvalMinCards(1, turn: 1)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'my_watching'}),
  ),
  EvalCase(
    id: 'rec-light-after-dinner',
    source: 'natuurlijke formulering: iets lichts na het eten',
    personal: true,
    turns: [
      EvalTurn(
        'iets luchtigs voor na het eten',
        script: [
          EvalCall('my_watching', {'kind': 'show'}),
          'Probeer «The Office» (2005).',
        ],
      ),
    ],
    hard: [...evalBase, const EvalNotSeen(), const EvalKindAsked(MediaKind.show)],
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'my_watching', 'search_catalog'}),
  ),
  EvalCase(
    id: 'rec-recently-added',
    source: 'startvraag: wat is er nieuw in mijn bibliotheek',
    turns: [
      EvalTurn(
        'Wat is er onlangs aan mijn bibliotheek toegevoegd?',
        script: [
          EvalCall('search_catalog', {'sort': 'added', 'limit': 5}),
          'Dit is het nieuwste in je bibliotheek.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'search_catalog'}),
  ),
  EvalCase(
    id: 'rec-five-unseen-series',
    source: 'startvraag met aantal: vijf series die ik nog niet zag',
    personal: true,
    turns: [
      EvalTurn(
        'Geef me vijf series die ik nog niet gezien heb',
        script: [
          EvalCall('search_catalog', {'kind': 'show', 'unwatched': true, 'limit': 5}),
          'Vijf series die je nog niet zag.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalKindAsked(MediaKind.show), const EvalNotSeen(), const EvalCardCount(max: 5)],
    scripted: const [EvalMinCards(3)],
    soft: const EvalSoft(firstTools: {'search_catalog'}, suggestions: 5),
  ),
  EvalCase(
    id: 'rec-trending-no-source',
    source: 'populair zonder bron: eerlijk zeggen dat het niet kan',
    turns: [
      EvalTurn(
        'Wat is er op dit moment populair?',
        script: [
          EvalCall('trending_titles', {'kind': 'all'}),
          'Ik kan nu niet zien wat populair is, daar is geen bron voor gekoppeld.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 0)],
    scripted: const [EvalToolAnswered('trending_titles', 'no_source')],
    soft: const EvalSoft(firstTools: {'trending_titles', 'search_catalog'}),
  ),
];
