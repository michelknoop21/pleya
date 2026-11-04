/**
 * De foutcodes van de twee routes achter scherm 37, als zin met een uitweg.
 *
 * - `GET /transcode-sessions`: `auth.user_not_found` (404, geen beheerder),
 *   de 401-codes van een verlopen sessie, `server.internal`.
 * - `DELETE /transcode-sessions/{id}`: `library.not_found` (404, de server
 *   gebruikt die code ook voor een onbekende of al beëindigde sessie: dan is
 *   de lijst verouderd en is herladen de uitweg).
 *
 * De rest (database, intern met verzoeknummer, transport) kent
 * `libraryProblem` al; de stopcode krijgt zijn eigen zin uit `settingsProblem`.
 */
import { libraryProblem, type LibraryProblem } from '../libraryErrors';
import { settingsProblem } from '../settings/settingsErrors';

export type TranscodeAction = 'list' | 'stop';

export function transcodeProblem(error: unknown, action: TranscodeAction, name = ''): LibraryProblem {
  return action === 'stop' ? settingsProblem(error, 'transcode', name) : libraryProblem(error, name);
}
