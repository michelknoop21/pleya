import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_world.dart';
import '../checks/big_p_eval_checks_extra.dart';
import 'big_p_eval_cases_support.dart';

// What Big P remembers per profile (BP-08a): recall of one's own facts,
// nothing of the other profile, a fact only with a yes, an unknown ref and a
// children's profile that has no memory (BP-11a2).

Future<EvalWorld> _twoProfiles() async => EvalWorld(
  profile: evalMichel,
  memory: await EvalMemory.open(michelFacts: ['houdt van komedies'], sanneFacts: ['kijkt geen horror']),
);

Future<EvalWorld> _asSanne() async => EvalWorld(
  profile: evalSanne,
  memoryOfSecond: true,
  memory: await EvalMemory.open(michelFacts: ['houdt van komedies'], sanneFacts: ['kijkt geen horror']),
);

final evalMemoryCases = <EvalCase>[
  EvalCase(
    id: 'mem-recall-own',
    source: 'BP-08a: wat weet je over mij',
    world: _twoProfiles,
    turns: [
      EvalTurn('Wat weet je over mij?', script: [EvalCall('recall_memory', {}), 'Je houdt van komedies.']),
    ],
    hard: [
      ...evalBase,
      const EvalToolUsed('recall_memory'),
      const EvalOnlyProfile(evalMichel, evalSanne, otherFacts: ['geen horror']),
    ],
    scripted: const [EvalToolAnswered('recall_memory', 'komedies')],
    soft: const EvalSoft(firstTools: {'recall_memory'}),
  ),
  EvalCase(
    id: 'mem-recall-second-profile',
    source: 'BP-08a: het andere profiel ziet alleen zijn eigen feiten',
    world: _asSanne,
    turns: [
      EvalTurn('Wat weet je over mij?', script: [EvalCall('recall_memory', {}), 'Je kijkt geen horror.']),
    ],
    hard: [
      ...evalBase,
      const EvalToolUsed('recall_memory'),
      const EvalOnlyProfile(evalSanne, evalMichel, otherFacts: ['komedies']),
    ],
    scripted: const [EvalToolAnswered('recall_memory', 'horror')],
    soft: const EvalSoft(firstTools: {'recall_memory'}),
  ),
  EvalCase(
    id: 'mem-remember-typed',
    source: 'BP-08a: een uitdrukkelijk getypte opdracht bewaart het feit zonder kaart',
    world: _twoProfiles,
    turns: [
      EvalTurn(
        'Onthoud dat ik graag documentaires kijk',
        script: [
          EvalCall('remember_fact', {'value': 'kijkt graag documentaires', 'category': 'preference'}),
          'Ik heb het onthouden.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('remember_fact')],
    scripted: const [EvalToolAnswered('remember_fact', 'stored')],
    soft: const EvalSoft(firstTools: {'remember_fact'}),
  ),
  EvalCase(
    id: 'mem-forget-unknown-ref',
    source: 'BP-08a: vergeten met een verzonnen verwijzing doet niets',
    world: _twoProfiles,
    turns: [
      EvalTurn(
        'Vergeet dat ik van komedies hou',
        script: [
          EvalCall('forget_fact', {'ref': 'f99'}),
          'Dat feit kon ik niet vinden, dus er is niets gewist.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalToolAnswered('forget_fact', 'unknown_ref')],
    soft: const EvalSoft(firstTools: {'recall_memory', 'forget_fact'}),
  ),
  EvalCase(
    id: 'mem-kids-no-memory',
    source: 'BP-08a: een kinderprofiel heeft geen geheugen',
    kids: true,
    kidsAges: const [8],
    world: _twoProfiles,
    turns: [
      EvalTurn(
        'Onthoud dat ik van Frozen hou',
        script: [
          EvalCall('remember_fact', {'value': 'houdt van Frozen', 'category': 'preference'}),
          'Dat kan ik op dit profiel niet bewaren.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalToolAnswered('remember_fact', 'unknown_tool')],
    soft: const EvalSoft(firstTools: {'remember_fact'}),
  ),
];
