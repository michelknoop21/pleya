/**
 * Elke foutcode die gebruikersbeheer van de server kan krijgen, als een zin
 * met een uitweg (S10.4). Zelfde opzet als libraryErrors.ts.
 *
 * De codes komen uit `openapi.yaml` (createUser, updateUser, deleteUser,
 * setUserPermissions, listSessions, revokeSession) en uit
 * `pleya_server/internal/api/handlers_users.go`:
 *
 * - `auth.user_not_found` (404): de aanvrager is geen beheerder (meer), de
 *   gebruiker bestaat niet (meer), of de invoer werd afgekeurd. De server
 *   gebruikt die ene code ook voor een te kort wachtwoord, een lege naam en een
 *   onbekende rol, om niets te verraden. De schermen controleren dat vooraf.
 * - `auth.username_taken`, `auth.owner_immutable`, `auth.permission_not_allowed`
 *   (409).
 * - `library.not_found` (404, een bibliotheek in de rechtenlijst), en
 *   `auth.session_not_found` (404).
 * - `server.internal`, `server.database_unavailable`, `storage.full` en de
 *   401-codes van een verlopen sessie, zoals bij de bibliotheken.
 */
import { ApiError, TransportError, describeError } from '../api/errors';
import { t, type MessageKey } from '../i18n';

export type UserWayOut = 'retry' | 'reload' | 'list' | 'login' | 'home' | 'none';

export interface UserProblem {
  code: string;
  message: string;
  wayOut: UserWayOut;
}

const KNOWN: Record<string, { key: MessageKey; wayOut: UserWayOut }> = {
  'auth.user_not_found': { key: 'admin.users.err.userNotFound', wayOut: 'reload' },
  'auth.username_taken': { key: 'admin.users.err.usernameTaken', wayOut: 'none' },
  'auth.owner_immutable': { key: 'admin.users.err.ownerImmutable', wayOut: 'none' },
  'auth.permission_not_allowed': { key: 'admin.users.err.permissionNotAllowed', wayOut: 'none' },
  'library.not_found': { key: 'admin.users.err.libraryNotFound', wayOut: 'reload' },
  'auth.session_not_found': { key: 'admin.users.err.sessionNotFound', wayOut: 'reload' },
  'server.database_unavailable': { key: 'admin.lib.err.database', wayOut: 'retry' },
  'storage.full': { key: 'admin.lib.err.storageFull', wayOut: 'retry' }
};

/** `name` is de gebruiker of de gebruikersnaam waar de melding over gaat. */
export function userProblem(error: unknown, name: string): UserProblem {
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
