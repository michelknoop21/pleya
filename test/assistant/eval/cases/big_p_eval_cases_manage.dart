import '../big_p_eval_cases.dart';
import '../big_p_eval_checks.dart';
import '../big_p_eval_fixtures.dart';
import '../big_p_eval_world.dart';
import 'big_p_eval_cases_support.dart';

// Beheer end to end (BP-12): the asking profile administers the server, so
// the admin tools have a path that succeeds. Each change is read back from
// the server's state; each refused card leaves it as it was.

Future<EvalWorld> _admin() async => EvalWorld(admin: EvalAdminState());

const _users = EvalCall('list_users', {'server_id': 'zolder'});
const _jobs = EvalCall('list_jobs', {'server_id': 'zolder'});
const _libs = EvalCall('list_libraries', {'server_id': 'zolder'});

final evalManageCases = <EvalCase>[
  EvalCase(
    id: 'man-libraries',
    source: 'BP-12: welke bibliotheken heb ik',
    world: _admin,
    turns: [
      EvalTurn('Welke bibliotheken heb ik?', script: [_libs, 'Je hebt twee bibliotheken op zolder: films en series.']),
    ],
    hard: [...evalBase, const EvalToolUsed('list_libraries'), const EvalStateUnchanged()],
    scripted: const [EvalToolAnswered('list_libraries', 'series')],
    soft: const EvalSoft(firstTools: {'list_libraries', 'list_servers'}),
  ),
  EvalCase(
    id: 'man-scan-library',
    source: 'BP-12: een bibliotheek scannen als beheerder, de scan is gestart',
    world: _admin,
    turns: [
      EvalTurn(
        'Scan mijn filmbibliotheek op nieuwe bestanden',
        confirm: EvalConfirm.yes,
        script: [
          _libs,
          EvalCall('scan_library', {'server_id': 'zolder', 'library_id': 'films'}),
          'De scan van films is gestart.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalActionDone('scanLibrary'),
      const EvalState(
        admin: {
          'scans': ['films'],
        },
      ),
    ],
    soft: const EvalSoft(firstTools: {'list_libraries'}),
  ),
  EvalCase(
    id: 'man-jobs',
    source: 'BP-12: welke taken lopen er op de server',
    world: _admin,
    turns: [
      EvalTurn(
        'Welke taken lopen er op mijn server?',
        script: [_jobs, 'Er loopt een scan van Films (40 procent). Ondertitels ophalen is mislukt door een time-out.'],
      ),
    ],
    hard: [...evalBase, const EvalToolUsed('list_jobs'), const EvalStateUnchanged()],
    scripted: const [EvalToolAnswered('list_jobs', 'time-out')],
    soft: const EvalSoft(firstTools: {'list_jobs'}),
  ),
  EvalCase(
    id: 'man-cancel-job-yes',
    source: 'BP-12: een lopende taak stoppen met een ja',
    world: _admin,
    turns: [
      EvalTurn(
        'Stop de scan die nu loopt',
        confirm: EvalConfirm.yes,
        script: [
          _jobs,
          EvalCall('cancel_job', {'server_id': 'zolder', 'job_id': 'j1'}),
          'De scan is gestopt.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalActionDone('cancelJob'),
      const EvalState(
        admin: {
          'cancelled_jobs': ['j1'],
        },
      ),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_jobs'}),
  ),
  EvalCase(
    id: 'man-cancel-job-no',
    source: 'BP-12: een taak stoppen geweigerd, de taak loopt door',
    world: _admin,
    turns: [
      EvalTurn(
        'Stop de scan die nu loopt',
        script: [
          _jobs,
          EvalCall('cancel_job', {'server_id': 'zolder', 'job_id': 'j1'}),
          'De scan loopt nog; er is niets gestopt.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalStateUnchanged(), const EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
  ),
  EvalCase(
    id: 'man-retry-job',
    source: 'BP-12: een mislukte taak opnieuw starten',
    world: _admin,
    turns: [
      EvalTurn(
        'Het ophalen van ondertitels is mislukt, probeer het opnieuw',
        confirm: EvalConfirm.yes,
        script: [
          _jobs,
          EvalCall('retry_job', {'server_id': 'zolder', 'job_id': 'j2'}),
          'Ondertitels ophalen is opnieuw gestart.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalState(
        admin: {
          'retried_jobs': ['j2'],
        },
      ),
    ],
    soft: const EvalSoft(firstTools: {'list_jobs'}),
  ),
  EvalCase(
    id: 'man-users',
    source: 'BP-12: wie heeft toegang tot mijn server',
    world: _admin,
    turns: [
      EvalTurn(
        'Wie heeft er toegang tot mijn server?',
        script: [_users, 'Michel, Sanne en Oma. Sanne ziet alleen films.'],
      ),
    ],
    hard: [
      ...evalBase,
      const EvalToolUsed('list_users'),
      const EvalAnswerNames('Sanne'),
      const EvalAnswerNames('Oma'),
      const EvalStateUnchanged(),
    ],
    scripted: const [EvalToolAnswered('list_users', 'Sanne')],
    soft: const EvalSoft(firstTools: {'list_users'}),
  ),
  EvalCase(
    id: 'man-create-user-yes',
    source: 'BP-12: een gebruiker aanmaken met toegang tot één bibliotheek',
    world: _admin,
    turns: [
      EvalTurn(
        'Maak een gebruiker Opa aan die alleen films mag zien',
        confirm: EvalConfirm.yes,
        script: [
          _libs,
          EvalCall('create_user', {
            'server_id': 'zolder',
            'name': 'Opa',
            'library_ids': ['films'],
          }),
          'Opa is aangemaakt en ziet alleen films.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalActionDone('createUser'),
      const EvalState(
        admin: {
          'users': {'Michel': 'all', 'Sanne': 'films', 'Oma': 'films,series', 'Opa': 'films'},
        },
      ),
    ],
    scripted: const [EvalConfirmShown(1)],
  ),
  EvalCase(
    id: 'man-user-access-yes',
    source: 'BP-12: bibliotheektoegang van een gebruiker wijzigen',
    world: _admin,
    turns: [
      EvalTurn(
        'Geef Sanne ook toegang tot de series',
        confirm: EvalConfirm.yes,
        script: [
          _users,
          _libs,
          EvalCall('set_user_library_access', {
            'server_id': 'zolder',
            'user_id': 'u2',
            'library_ids': ['films', 'series'],
          }),
          'Sanne ziet nu films en series.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalActionDone('setLibraryAccess'),
      const EvalState(
        admin: {
          'users': {'Michel': 'all', 'Sanne': 'films,series', 'Oma': 'films,series'},
        },
      ),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_users'}),
  ),
  EvalCase(
    id: 'man-remove-user-yes',
    source: 'BP-12: een gebruiker verwijderen met een ja',
    world: _admin,
    turns: [
      EvalTurn(
        'Verwijder de gebruiker Oma van mijn server',
        confirm: EvalConfirm.yes,
        script: [
          _users,
          EvalCall('remove_user', {'server_id': 'zolder', 'user_id': 'u3'}),
          'Oma is verwijderd.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalActionDone('removeUser'),
      const EvalState(
        admin: {
          'users': {'Michel': 'all', 'Sanne': 'films'},
        },
      ),
    ],
    scripted: const [EvalConfirmShown(1)],
    soft: const EvalSoft(firstTools: {'list_users'}),
  ),
  EvalCase(
    id: 'man-remove-user-no',
    source: 'BP-12: een gebruiker verwijderen geweigerd, de gebruiker blijft (nultolerantie 6)',
    world: _admin,
    turns: [
      EvalTurn(
        'Verwijder de gebruiker Oma van mijn server',
        script: [
          _users,
          EvalCall('remove_user', {'server_id': 'zolder', 'user_id': 'u3'}),
          'Oma is niet verwijderd.',
        ],
      ),
    ],
    hard: [...evalBase, const EvalStateUnchanged(), const EvalNoFalseSuccess()],
    scripted: const [EvalConfirmShown(1)],
  ),
  EvalCase(
    id: 'man-refresh-metadata',
    source: 'BP-12: metadata van één titel verversen',
    world: _admin,
    turns: [
      EvalTurn(
        'Ververs de metadata van Inception',
        confirm: EvalConfirm.yes,
        script: [
          EvalCall('find_media', {'server_id': 'zolder', 'query': 'Inception'}),
          EvalCall('refresh_metadata', {'server_id': 'zolder', 'item_id': 'm12'}),
          'De metadata van Inception wordt ververst.',
        ],
      ),
    ],
    hard: [
      ...evalNoMut,
      const EvalActionDone('refreshMetadata'),
      const EvalState(
        admin: {
          'refreshed': ['m12'],
        },
      ),
    ],
    soft: const EvalSoft(firstTools: {'find_media'}),
  ),
];
