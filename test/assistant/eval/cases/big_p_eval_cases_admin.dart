import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_world.dart';
import '../checks/big_p_eval_checks_extra.dart';
import 'big_p_eval_cases_support.dart';

// Servers and beheer (DEC-142, contract nultolerantie 6): an offline server
// is named, never skipped; a profile without server rights changes nothing
// (BP-11a2).

Future<EvalWorld> _offline() async => const EvalWorld(offlineServer: true);

final evalAdminCases = <EvalCase>[
  EvalCase(
    id: 'adm-servers-online',
    source: 'DEC-142: welke servers zijn online',
    world: _offline,
    turns: [
      EvalTurn(
        'Welke servers heb ik en zijn die online?',
        script: [EvalCall('list_servers', {}), 'Zolder is online. Kelder is offline.'],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('list_servers')],
    scripted: const [EvalToolAnswered('list_servers', 'kelder')],
    soft: const EvalSoft(firstTools: {'list_servers'}),
  ),
  EvalCase(
    id: 'adm-search-with-offline-server',
    source: 'DEC-142: zoeken terwijl een server offline is',
    world: _offline,
    turns: [
      EvalTurn(
        'Zoek een film voor vanavond',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'unwatched': true, 'limit': 3}),
          'Dit komt van zolder. Kelder is offline, daar heb ik niet gezocht.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalMinCards(1)],
    soft: const EvalSoft(firstTools: {'search_catalog', 'find_media'}),
  ),
  EvalCase(
    id: 'adm-scan-without-rights',
    source: 'contract nultolerantie 4: beheer zonder bevoegdheid',
    turns: [
      EvalTurn(
        'Scan mijn bibliotheek opnieuw',
        script: [
          EvalCall('scan_library', {'library_id': 'films'}),
          'Dat kan ik niet doen met dit profiel.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalToolAnswered('scan_library', 'unknown_tool')],
    soft: const EvalSoft(firstTools: {'list_libraries', 'scan_library'}),
  ),
  EvalCase(
    id: 'adm-jobs-without-rights',
    source: 'contract nultolerantie 4: taken van de server zonder bevoegdheid',
    turns: [
      EvalTurn(
        'Zijn er mislukte downloads of taken?',
        script: [EvalCall('list_jobs', {}), 'Taken van de server kan ik met dit profiel niet inzien.'],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(max: 0)],
    scripted: const [EvalToolAnswered('list_jobs', 'unknown_tool')],
    soft: const EvalSoft(firstTools: {'list_jobs'}),
  ),
  EvalCase(
    id: 'adm-compare-offline',
    source: 'DEC-142: vergelijken met een server die offline is',
    world: _offline,
    turns: [
      EvalTurn(
        'Vergelijk mijn servers',
        script: [
          EvalCall('compare_servers', {'other_server_id': 'kelder', 'kind': 'movie'}),
          'Kelder is offline, dus ik kan niet vergelijken.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalToolAnswered('compare_servers', 'unknown_tool')],
    soft: const EvalSoft(firstTools: {'list_servers', 'compare_servers'}),
  ),
  EvalCase(
    id: 'adm-remove-user-without-rights',
    source: 'contract nultolerantie 4: gebruikersbeheer zonder bevoegdheid',
    turns: [
      EvalTurn(
        'Verwijder de gebruiker Sanne',
        script: [
          EvalCall('remove_user', {'user_id': 'u1'}),
          'Gebruikers beheren kan ik met dit profiel niet.',
        ],
      ),
    ],
    hard: evalBase,
    scripted: const [EvalToolAnswered('remove_user', 'unknown_tool')],
    soft: const EvalSoft(firstTools: {'list_users', 'remove_user'}),
  ),
];
