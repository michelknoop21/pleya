/**
 * Elke foutcode die Opslag en Scans en taken van de server kunnen krijgen, als
 * een zin met een uitweg (S10.3).
 *
 * De routes en hun codes uit `openapi.yaml`:
 *
 * - `POST /storage/roots/recheck`: `auth.user_not_found` (404), 401-codes,
 *   `server.internal`. Zonder jobrunner geeft de server `server.internal`.
 * - `GET /scans`, `GET /jobs`: `library.cursor_invalid` (400), plus dezelfde.
 * - `POST /jobs/{id}/cancel`: `library.not_found` (404, de server gebruikt die
 *   code ook voor een onbekende job), `job.not_cancellable` met
 *   `details.reason = finished` (409).
 * - `POST /jobs/{id}/retry`: `library.not_found`, `job.not_cancellable` met
 *   `details.reason = duplicate_in_flight` (409).
 * - `POST /libraries/{id}/scan` (Alles scannen): `library.not_found`,
 *   `library.scan_in_progress`.
 * - Overal: `server.database_unavailable`, `storage.unavailable`,
 *   `storage.full` en de verlopen sessie.
 *
 * Wat hier niet specifiek is valt door naar `libraryProblem`, dat de rest
 * (database, intern met verzoeknummer, geen beheerder, verlopen sessie, en
 * transportfouten) al als zin met uitweg kent.
 */
import { ApiError } from '../api/errors';
import { t } from '../i18n';
import { libraryProblem, type LibraryProblem } from './libraryErrors';

/**
 * `name` is wat de bezoeker zag toen hij klikte: de titel van de taak of van
 * de bibliotheek. Zo noemt de zin het ding waar het om ging.
 */
export function opsProblem(error: unknown, name: string): LibraryProblem {
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'library.cursor_invalid':
        return { code: error.code, message: t('admin.ops.err.cursor'), wayOut: 'reload' };
      case 'library.not_found':
        return { code: error.code, message: t('admin.ops.err.jobGone', { name }), wayOut: 'reload' };
      case 'job.not_cancellable': {
        const reason = error.details['reason'];
        const key =
          reason === 'finished'
            ? 'admin.ops.err.finished'
            : reason === 'duplicate_in_flight'
              ? 'admin.ops.err.duplicate'
              : 'admin.ops.err.notCancellable';
        return { code: error.code, message: t(key, { name }), wayOut: 'reload' };
      }
      case 'storage.unavailable':
        return { code: error.code, message: t('admin.ops.err.unavailable'), wayOut: 'retry' };
    }
  }
  return libraryProblem(error, name);
}
