/**
 * Elke foutcode die de back-uproutes van de server kunnen geven, als een zin
 * met een uitweg (S25.6). De codes komen uit `openapi.yaml` (listBackups,
 * createBackup, verifyBackup, restoreBackup) en uit
 * `pleya_server/internal/api/handlers_backups.go`:
 *
 * - `server.backup_busy` (409): er wacht of loopt al een back-up of hersteltest.
 *   Herhaalbaar, dus de uitweg is wachten; de pagina ververst zelf.
 * - `server.backup_not_restorable` (409) met `details.reason`: `status` (de
 *   back-up is niet geslaagd), `schema_newer` (nieuwer dan deze server), `key`
 *   (de sleutel past niet op de geheimen) of `unreadable` (het bestand is stuk).
 * - `server.confirm_mismatch` (409): de zin klopt niet, met de juiste in
 *   `details.expected`. De pagina stuurt altijd de zin van de server, dus dit
 *   betekent dat de back-up inmiddels veranderd is.
 * - `server.maintenance` (503): de server is aan het terugzetten.
 * - `library.not_found` (404): de server gebruikt die code ook voor een
 *   onbekende back-up.
 * - `auth.user_not_found` (404): geen beheerder, of het onderdeel staat uit.
 * - `storage.full`, `server.database_unavailable`, `server.internal` en de
 *   401-codes van een verlopen sessie, zoals overal.
 *
 * Wat hier niet specifiek is valt door naar `libraryProblem`.
 */
import { ApiError } from '../../api/errors';
import { t, type MessageKey } from '../../i18n';
import { libraryProblem, type LibraryProblem } from '../libraryErrors';

export type BackupAction = 'list' | 'create' | 'verify' | 'restore';

const NOT_RESTORABLE: Record<string, MessageKey> = {
  status: 'admin.bak.err.notRestorable.status',
  schema_newer: 'admin.bak.err.notRestorable.schemaNewer',
  key: 'admin.bak.err.notRestorable.key',
  unreadable: 'admin.bak.err.notRestorable.unreadable'
};

export function backupProblem(error: unknown, action: BackupAction): LibraryProblem {
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'server.backup_busy':
        return { code: error.code, message: t('admin.bak.err.busy'), wayOut: 'reload' };
      case 'server.backup_not_restorable': {
        const reason = error.details['reason'];
        const key = (typeof reason === 'string' && NOT_RESTORABLE[reason]) || 'admin.bak.err.notRestorable.fallback';
        return { code: error.code, message: t(key), wayOut: reason === 'key' ? 'none' : 'reload' };
      }
      case 'server.confirm_mismatch':
        return { code: error.code, message: t('admin.bak.err.confirmMismatch'), wayOut: 'reload' };
      case 'server.maintenance':
        return { code: error.code, message: t('admin.bak.err.maintenance'), wayOut: 'reload' };
      case 'library.not_found':
        return { code: error.code, message: t('admin.bak.err.gone'), wayOut: 'reload' };
      case 'storage.full':
        return {
          code: error.code,
          message: t(action === 'create' ? 'admin.bak.err.fullCreate' : 'admin.bak.err.full'),
          wayOut: 'retry'
        };
    }
  }
  return libraryProblem(error, t('admin.bak.title'));
}
