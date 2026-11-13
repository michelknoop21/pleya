import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_world.dart';
import 'big_p_eval_cases_support.dart';

// Tasks carried out end to end (BP-12): the user says yes on the card, the
// action runs against the eval world, and the check reads the world, not the
// model's words. Each task has its twin with a no, where nothing may change.

Future<EvalWorld> _seerr() async => EvalWorld(seerr: evalSeerr());
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
];
