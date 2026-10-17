import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_world.dart';
import '../checks/big_p_eval_checks_extra.dart';
import 'big_p_eval_cases_support.dart';

// Servers and beheer (DEC-142): an offline server is named, never skipped; a profile without server rights changes nothing
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
    // The search result marks the offline server (servers_offline, BP-11e),
    // so the answer can name it without reading list_servers first.
    source: 'DEC-142: zoeken terwijl een server offline is, de server wordt genoemd',
    world: _offline,
    turns: [
      EvalTurn(
        'Zoek een film voor vanavond',
        script: [
          EvalCall('search_catalog', {'kind': 'movie', 'unwatched': true, 'limit': 3}),
          'Dit komt van zolder. Kelder is offline, daar kon ik niet zoeken.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalCardCount(min: 1), const EvalAnswerNames('kelder')],
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
    hard: [...evalBase, const EvalCardCount(max: 0)],
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
    id: 'adm-server-reachable',
    source: 'DEC-142: is een bepaalde server bereikbaar',
    world: _offline,
    turns: [
      EvalTurn(
        'Kan ik bij mijn server kelder?',
        script: [EvalCall('list_servers', {}), 'Kelder is offline, dus nu niet.'],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('list_servers'), const EvalAnswerNames('kelder')],
    scripted: const [EvalToolAnswered('list_servers', '"online":false')],
    soft: const EvalSoft(firstTools: {'list_servers'}),
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
    hard: [...evalBase, const EvalCardCount(max: 0)],
    scripted: const [EvalToolAnswered('remove_user', 'unknown_tool')],
    soft: const EvalSoft(firstTools: {'list_users', 'remove_user'}),
  ),
];
