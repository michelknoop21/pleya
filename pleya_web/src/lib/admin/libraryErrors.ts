/**
 * Elke foutcode die bibliotheekbeheer van de server kan krijgen, als een zin
 * met een uitweg (S10.2).
 *
 * De codes komen uit `openapi.yaml` (createLibrary, updateLibrary,
 * deleteLibrary, adoptLibrary, startScan) en uit de handlers in
 * `pleya_server/internal/api/handlers_admin_libraries.go`:
 *
 * - `storage.root_not_offered` (400): een root die niet (meer) vrij is, en ook
 *   een onleesbaar veld. De server gebruikt die ene code voor beide.
 * - `library.slug_taken`, `library.not_empty`, `library.config_managed`,
 *   `library.confirm_mismatch`, `library.not_config_managed`,
 *   `library.scan_in_progress` (409).
 * - `library.not_found` en `auth.user_not_found` (404).
 * - `server.internal`, `server.database_unavailable`, `storage.full` uit
 *   `writeInternal`, en de 401-codes van een verlopen sessie.
 *
 * Een code die hier niet staat valt terug op `describeError`, met opnieuw
 * proberen als uitweg: liever een algemene zin dan een lege melding.
 */
import { ApiError, TransportError, describeError } from '../api/errors';
import { t, type MessageKey } from '../i18n';

/** Wat de melding als knop of link aanbiedt. */
export type WayOut =
  | 'retry'
  | 'reload'
  | 'adopt'
  | 'storage'
  | 'activity'
  | 'list'
  | 'login'
  | 'home'
  | 'none';

export interface LibraryProblem {
  code: string;
  message: string;
  wayOut: WayOut;
}

const KNOWN: Record<string, { key: MessageKey; wayOut: WayOut }> = {
  'storage.root_not_offered': { key: 'admin.lib.err.rootNotOffered', wayOut: 'storage' },
  'library.slug_taken': { key: 'admin.lib.err.slugTaken', wayOut: 'none' },
  'library.not_empty': { key: 'admin.lib.err.notEmpty', wayOut: 'none' },
  'library.config_managed': { key: 'admin.lib.err.configManaged', wayOut: 'adopt' },
  'library.confirm_mismatch': { key: 'admin.lib.err.confirmMismatch', wayOut: 'reload' },
  'library.not_config_managed': { key: 'admin.lib.err.notConfigManaged', wayOut: 'reload' },
  'library.scan_in_progress': { key: 'admin.lib.err.scanInProgress', wayOut: 'activity' },
  'library.not_found': { key: 'admin.lib.err.notFound', wayOut: 'list' },
  'auth.user_not_found': { key: 'admin.lib.err.notAdmin', wayOut: 'home' },
  'server.database_unavailable': { key: 'admin.lib.err.database', wayOut: 'retry' },
  'storage.full': { key: 'admin.lib.err.storageFull', wayOut: 'retry' }
};

export function libraryProblem(error: unknown, name: string): LibraryProblem {
  if (error instanceof ApiError) {
    const known = KNOWN[error.code];
    if (known) return { code: error.code, message: t(known.key, { name }), wayOut: known.wayOut };
    if (error.code === 'server.internal') {
      const id = error.details['request_id'];
      return {
        code: error.code,
        message:
          typeof id === 'string' && id !== ''
            ? t('admin.lib.err.internalId', { id })
            : t('admin.lib.err.internal'),
        wayOut: 'retry'
      };
    }
    if (error.isAuthFailure) {
      return { code: error.code, message: describeError(error), wayOut: 'login' };
    }
    return { code: error.code, message: describeError(error), wayOut: 'retry' };
  }
  const code = error instanceof TransportError ? 'client.transport' : 'client.unknown';
  return { code, message: describeError(error), wayOut: 'retry' };
}
