import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_world.dart';
import 'big_p_eval_cases_support.dart';

// Tasks carried out end to end (BP-12): the user says yes on the card, the
// action runs against the eval world, and the check reads the world, not the
// model's words. Each task has its twin with a no, where nothing may change.

Future<EvalWorld> _seerr() async => EvalWorld(seerr: evalSeerr());

/// The same Seerr, where this user's request for Primer is still pending.
Future<EvalWorld> _seerrPending() async => EvalWorld(
  seerr: evalSeerr()
    // The search result carries the status too, as Seerr's does: without it
    // the title reads as not requested and nobody would cancel anything.
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

const _findPrimer = EvalCall('find_request_title', {
  'titles': [
    {'title': 'Primer', 'kind': 'movie'},
  ],
});

/// Two rows already saved on Home.
Future<EvalWorld> _rows() async => const EvalWorld(homeRows: ['Actie uit de jaren 90', 'Kerstfilms']);

/// A kijklijst with two titles on it.
Future<EvalWorld> _list() async => EvalWorld(watchlist: EvalWatchlist(['Dune', 'Arrival']));

Future<EvalWorld> _memory() async => EvalWorld(memory: await EvalMemory.open(michelFacts: ['houdt van komedies']));
Future<EvalWorld> _emptyMemory() async => EvalWorld(memory: await EvalMemory.open());

const _findSeverance = EvalCall('find_request_title', {
  'titles': [
    {'title': 'Severance', 'kind': 'series'},
  ],
});

final evalTaskCases = <EvalCase>[
  EvalCase(
    id: 'task-home-row-yes',
    source: 'BP-12: Home-rij maken met een ja, de rij bestaat daarna',
    turns: [
      EvalTurn(
        'Zoek films en maak er een rij van op mijn beginscherm.',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'limit': 5}),
          EvalCall('create_home_row', {'query_id': 'q1', 'title': 'Films'}),
          'De rij Films staat op je beginscherm.',
        ],
      ),
    ],
    hard: const [evalFromFixture, evalNoDup, EvalActionDone('createHomeRow'), EvalState(homeRowCount: 1)],
    scripted: const [
      EvalConfirmShown(1),
      EvalState(homeRows: ['Films']),
    ],
    soft: const EvalSoft(firstTools: {'search_catalog'}),
  ),
  EvalCase(
    id: 'task-home-row-no',
    source: 'BP-12: Home-rij geweigerd, er verandert niets (nultolerantie 6)',
    turns: [
      EvalTurn(
        'Maak een rij met komedies op mijn beginscherm.',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'genre': 'comedy', 'limit': 5}),
          EvalCall('create_home_row', {'query_id': 'q1', 'title': 'Komedies'}),
          'De rij is niet gemaakt.',
        ],
      ),
    ],
    hard: const [evalFromFixture, evalMutation, evalNoDup, EvalStateUnchanged(), EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
  ),
  EvalCase(
    id: 'task-request-yes',
    source: 'BP-12: aanvraag met een ja, Seerr heeft de aanvraag ontvangen',
    world: _seerr,
    turns: [
      EvalTurn(
        'Vraag Severance voor me aan',
        confirm: EvalConfirm.yes,
        script: [
          _findSeverance,
          EvalCall('request_title', {'seerr_id': 'tv:95396'}),
          'Severance is aangevraagd.',
        ],
      ),
    ],
    hard: const [
      evalFromFixture,
      evalNoDup,
      EvalActionDone('requestTitle'),
      EvalState(requests: ['tv:95396']),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_request_title'}),
  ),
  EvalCase(
    id: 'task-request-no',
    source: 'BP-12: aanvraag geweigerd, Seerr kreeg niets',
    world: _seerr,
    turns: [
      EvalTurn(
        'Vraag de film Primer aan',
        script: [
          EvalCall('find_request_title', {
            'titles': [
              {'title': 'Primer', 'kind': 'movie'},
            ],
          }),
          EvalCall('request_title', {'seerr_id': 'movie:14337'}),
          'De aanvraag voor Primer is niet verstuurd.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalStateUnchanged(), const EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_request_title'}),
  ),
  EvalCase(
    id: 'task-request-two-turns',
    source: 'BP-12: eerst opzoeken, in de volgende beurt aanvragen met een ja',
    world: _seerr,
    turns: [
      EvalTurn(
        'Kan ik Severance aanvragen?',
        script: [_findSeverance, 'Ja, Severance kun je aanvragen. Zal ik dat doen?'],
      ),
      EvalTurn(
        'Ja, doe maar',
        confirm: EvalConfirm.yes,
        script: [
          _findSeverance,
          EvalCall('request_title', {'seerr_id': 'tv:95396'}),
          'Severance is aangevraagd.',
        ],
      ),
    ],
    hard: const [
      evalFromFixture,
      evalNoDup,
      EvalActionDone('requestTitle'),
      EvalState(requests: ['tv:95396']),
    ],
    scripted: const [EvalConfirmShown(1)],
  ),
  EvalCase(
    id: 'task-remember-stored',
    source: 'BP-12: een getypt "onthoud dat" staat daarna in het geheugen',
    world: _emptyMemory,
    turns: [
      EvalTurn(
        'Onthoud dat ik graag documentaires kijk',
        script: [
          EvalCall('remember_fact', {'value': 'kijkt graag documentaires', 'category': 'preference'}),
          'Ik heb het onthouden.',
        ],
      ),
    ],
    hard: [
      ...evalBase,
      const EvalState(memory: ['documentaire']),
    ],
    soft: const EvalSoft(firstTools: {'remember_fact'}),
  ),
  EvalCase(
    id: 'task-forget-yes',
    source: 'BP-12: vergeten met een ja, het feit is weg',
    world: _memory,
    turns: [
      EvalTurn(
        'Vergeet dat ik van komedies hou',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('recall_memory', {}),
          EvalCall('forget_fact', {'ref': 'f0000001'}),
          'Ik ben het vergeten.',
        ],
      ),
    ],
    hard: [
      evalFromFixture,
      evalNoDup,
      const EvalState(memory: []),
    ],
  ),
  EvalCase(
    id: 'task-forget-no',
    source: 'BP-12: vergeten geweigerd, het feit blijft staan',
    world: _memory,
    turns: [
      EvalTurn(
        'Vergeet dat ik van komedies hou',
        script: [
          EvalCall('recall_memory', {}),
          EvalCall('forget_fact', {'ref': 'f0000001'}),
          'Ik ben het vergeten.',
        ],
      ),
    ],
    hard: [
      ...evalBase,
      const EvalState(memory: ['komedies']),
    ],
  ),
  // The request service without a title in mind, a status question and
  // "something like": three tools no case reached before.
  EvalCase(
    id: 'req-discover-genre',
    source: 'BP-12: bladeren in de aanvraagdienst op genre, zonder titel',
    world: _seerr,
    turns: [
      EvalTurn(
        'Ik wil een sciencefictionfilm aanvragen maar weet geen titel. Wat is er?',
        script: [
          EvalCall('discover_request_titles', {
            'kind': 'movie',
            'genres': ['Science Fiction'],
          }),
          'Deze drie kun je aanvragen.',
        ],
      ),
    ],
    // Request options are no library cards: the card checks do not apply.
    hard: const [evalNoDup, EvalStateUnchanged()],
    soft: const EvalSoft(firstTools: {'discover_request_titles'}),
  ),
  EvalCase(
    id: 'req-status-not-requested',
    source: 'BP-12: status van een aanvraag die er niet is, eerlijk zeggen',
    world: _seerr,
    turns: [
      EvalTurn(
        'Is Primer al aangevraagd?',
        script: [
          EvalCall('find_request_title', {
            'titles': [
              {'title': 'Primer', 'kind': 'movie'},
            ],
          }),
          EvalCall('request_status', {'seerr_id': 'movie:14337'}),
          'Nee, Primer is nog niet aangevraagd.',
        ],
      ),
    ],
    hard: const [evalFromFixture, evalNoDup, EvalStateUnchanged()],
    soft: const EvalSoft(firstTools: {'find_request_title', 'find_title'}),
  ),
  EvalCase(
    id: 'disc-similar-to-title',
    source: 'BP-12: iets zoals een titel, uit de aanvraagdienst',
    world: _seerr,
    turns: [
      EvalTurn(
        'Geef me iets zoals Primer',
        script: [
          EvalCall('similar_titles', {'title': 'Primer'}),
          'Deze twee lijken erop.',
        ],
      ),
    ],
    // The cards come from the request service, not from the catalogue.
    hard: const [evalNoDup, EvalCardCount(min: 1), EvalStateUnchanged()],
    soft: const EvalSoft(firstTools: {'similar_titles'}),
  ),
  // Cancelling a request (BP-12t1): the request leaves Seerr after a yes
  // and stays after a no.
  EvalCase(
    id: 'task-cancel-request-yes',
    source: 'BP-12t1: eigen aanvraag annuleren met een ja',
    world: _seerrPending,
    turns: [
      EvalTurn(
        'Annuleer mijn aanvraag voor Primer',
        confirm: EvalConfirm.yes,
        script: [
          _findPrimer,
          EvalCall('cancel_request', {'seerr_id': 'movie:14337'}),
          'De aanvraag voor Primer is geannuleerd.',
        ],
      ),
    ],
    hard: const [
      evalNoDup,
      EvalActionDone('cancelRequest'),
      EvalState(cancelledRequests: ['41'], requests: []),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_request_title', 'find_title'}),
  ),
  EvalCase(
    id: 'task-cancel-request-no',
    source: 'BP-12t1: annuleren geweigerd, de aanvraag blijft staan',
    world: _seerrPending,
    turns: [
      EvalTurn(
        'Annuleer mijn aanvraag voor Primer',
        confirm: EvalConfirm.no,
        script: [
          _findPrimer,
          EvalCall('cancel_request', {'seerr_id': 'movie:14337'}),
          'De aanvraag voor Primer blijft staan.',
        ],
      ),
    ],
    hard: const [evalNoDup, EvalStateUnchanged(), EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_request_title', 'find_title'}),
  ),
  // Saved Home rows (BP-12t2): rename and remove, each with its no.
  EvalCase(
    id: 'task-home-row-rename-yes',
    source: 'BP-12t2: een opgeslagen rij hernoemen met een ja',
    world: _rows,
    turns: [
      EvalTurn(
        'Noem mijn rij Kerstfilms voortaan Feestdagen',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('list_home_rows', {}),
          EvalCall('rename_home_row', {'row_id': 'r2', 'title': 'Feestdagen'}),
          'De rij heet nu Feestdagen.',
        ],
      ),
    ],
    hard: const [
      evalNoDup,
      EvalActionDone('renameHomeRow'),
      EvalState(homeRows: ['Actie uit de jaren 90', 'Feestdagen']),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_home_rows'}),
  ),
  EvalCase(
    id: 'task-home-row-rename-no',
    source: 'BP-12t2: hernoemen geweigerd, de rij houdt zijn naam',
    world: _rows,
    turns: [
      EvalTurn(
        'Noem mijn rij Kerstfilms voortaan Feestdagen',
        confirm: EvalConfirm.no,
        script: [
          EvalCall('list_home_rows', {}),
          EvalCall('rename_home_row', {'row_id': 'r2', 'title': 'Feestdagen'}),
          'De rij heet nog steeds Kerstfilms.',
        ],
      ),
    ],
    hard: const [evalNoDup, EvalStateUnchanged(), EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_home_rows'}),
  ),
  EvalCase(
    id: 'task-home-row-remove-yes',
    source: 'BP-12t2: een opgeslagen rij verwijderen met een ja',
    world: _rows,
    turns: [
      EvalTurn(
        'Haal de rij Actie uit de jaren 90 van mijn beginscherm',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('list_home_rows', {}),
          EvalCall('remove_home_row', {'row_id': 'r1'}),
          'De rij is verwijderd.',
        ],
      ),
    ],
    hard: const [
      evalNoDup,
      EvalActionDone('removeHomeRow'),
      EvalState(homeRows: ['Kerstfilms']),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_home_rows'}),
  ),
  EvalCase(
    id: 'task-home-row-remove-no',
    source: 'BP-12t2: verwijderen geweigerd, de rij blijft staan',
    world: _rows,
    turns: [
      EvalTurn(
        'Haal de rij Actie uit de jaren 90 van mijn beginscherm',
        confirm: EvalConfirm.no,
        script: [
          EvalCall('list_home_rows', {}),
          EvalCall('remove_home_row', {'row_id': 'r1'}),
          'De rij staat er nog.',
        ],
      ),
    ],
    hard: const [evalNoDup, EvalStateUnchanged(), EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_home_rows'}),
  ),
  // The kijklijst (BP-12t3): read it, add a library title, take one off.
  EvalCase(
    id: 'task-watchlist-read',
    source: 'BP-12t3: wat staat er op mijn kijklijst',
    world: _list,
    turns: [
      EvalTurn(
        'Wat staat er op mijn kijklijst?',
        script: [EvalCall('my_watchlist', {}), 'Op je kijklijst staan Dune en Arrival.'],
      ),
    ],
    hard: const [evalNoDup, EvalStateUnchanged()],
    soft: const EvalSoft(firstTools: {'my_watchlist'}),
  ),
  EvalCase(
    id: 'task-watchlist-add-yes',
    source: 'BP-12t3: een titel uit de bibliotheek op de kijklijst met een ja',
    world: _list,
    turns: [
      EvalTurn(
        'Zet Finding Nemo op mijn kijklijst',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('find_media', {'server_id': 'zolder', 'query': 'Finding Nemo'}),
          EvalCall('add_to_watchlist', {'server_id': 'zolder', 'item_id': 'm02'}),
          'Finding Nemo staat op je kijklijst.',
        ],
      ),
    ],
    hard: const [
      evalNoDup,
      EvalActionDone('addToWatchlist'),
      EvalState(watchlist: ['Finding Nemo', 'Dune', 'Arrival']),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_media', 'search_catalog', 'find_title'}),
  ),
  EvalCase(
    id: 'task-watchlist-add-no',
    source: 'BP-12t3: toevoegen geweigerd, de kijklijst blijft gelijk',
    world: _list,
    turns: [
      EvalTurn(
        'Zet Finding Nemo op mijn kijklijst',
        confirm: EvalConfirm.no,
        script: [
          EvalCall('find_media', {'server_id': 'zolder', 'query': 'Finding Nemo'}),
          EvalCall('add_to_watchlist', {'server_id': 'zolder', 'item_id': 'm02'}),
          'Finding Nemo staat niet op je kijklijst.',
        ],
      ),
    ],
    hard: const [evalNoDup, EvalStateUnchanged(), EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'find_media', 'search_catalog', 'find_title'}),
  ),
  EvalCase(
    id: 'task-watchlist-remove-yes',
    source: 'BP-12t3: een titel van de kijklijst halen met een ja',
    world: _list,
    turns: [
      EvalTurn(
        'Haal Arrival van mijn kijklijst',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('my_watchlist', {}),
          EvalCall('remove_from_watchlist', {'entry_id': 'w2'}),
          'Arrival is van je kijklijst gehaald.',
        ],
      ),
    ],
    hard: const [
      evalNoDup,
      EvalActionDone('removeFromWatchlist'),
      EvalState(watchlist: ['Dune']),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'my_watchlist'}),
  ),
  EvalCase(
    id: 'task-watchlist-remove-no',
    source: 'BP-12t3: verwijderen geweigerd, de titel blijft staan',
    world: _list,
    turns: [
      EvalTurn(
        'Haal Arrival van mijn kijklijst',
        confirm: EvalConfirm.no,
        script: [
          EvalCall('my_watchlist', {}),
          EvalCall('remove_from_watchlist', {'entry_id': 'w2'}),
          'Arrival staat nog op je kijklijst.',
        ],
      ),
    ],
    hard: const [evalNoDup, EvalStateUnchanged(), EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'my_watchlist'}),
  ),
];
