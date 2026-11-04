/**
 * Elke foutcode van de routes achter de schermen Media, Metadata, Netwerk,
 * Beveiliging en Diagnostiek, als een zin met een uitweg (S10.5).
 *
 * De routes en hun codes uit `openapi.yaml` en de handlers in
 * `pleya_server/internal/api/handlers_settings.go`, `handlers_server_admin.go`
 * en `handlers_transcode.go`:
 *
 * - `PATCH /settings`: `settings.invalid_value` (400) met `details.field` en,
 *   als er een grens is, `details.minimum` en `details.maximum`. Er is dan niets
 *   gewijzigd, ook niet aan de sleutels die wel klopten.
 * - `POST /server/rotate-signing-key`: `server.confirm_mismatch` (409).
 * - `DELETE /transcode-sessions/{id}`: `library.not_found` (404, de server
 *   gebruikt die code ook voor een onbekende sessie).
 * - `DELETE /sessions/{id}`: `auth.session_not_found` (404).
 * - Overal: `auth.user_not_found` (404, geen beheerder), `server.internal` met
 *   verzoeknummer, `server.database_unavailable`, `storage.full` en de
 *   401-codes van een verlopen sessie. Die vallen door naar `libraryProblem`.
 */
import { ApiError } from '../../api/errors';
import { t } from '../../i18n';
import { libraryProblem, type LibraryProblem } from '../libraryErrors';
import { SETTING_FIELD_LABELS } from './settings';

export type SettingsContext = 'settings' | 'rotate' | 'transcode' | 'session';

function fieldLabel(field: unknown): string {
  const key = typeof field === 'string' ? SETTING_FIELD_LABELS[field] : undefined;
  return key ? t(key) : typeof field === 'string' && field !== '' ? field : t('admin.set.err.unknownField');
}

export function settingsProblem(
  error: unknown,
  context: SettingsContext = 'settings',
  name = ''
): LibraryProblem {
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'settings.invalid_value': {
        const { field, minimum, maximum } = error.details;
        const label = fieldLabel(field);
        const bounded = typeof minimum === 'string' && typeof maximum === 'string';
        return {
          code: error.code,
          message: bounded
            ? t('admin.set.err.invalidRange', { field: label, min: minimum, max: maximum })
            : t('admin.set.err.invalid', { field: label }),
          wayOut: 'none'
        };
      }
      case 'server.confirm_mismatch':
        return { code: error.code, message: t('admin.set.err.rotateMismatch'), wayOut: 'none' };
      case 'library.not_found':
        if (context === 'transcode') {
          return { code: error.code, message: t('admin.set.err.transcodeGone', { name }), wayOut: 'reload' };
        }
        break;
      case 'auth.session_not_found':
        return { code: error.code, message: t('admin.set.err.sessionGone', { name }), wayOut: 'reload' };
    }
  }
  return libraryProblem(error, name);
}
