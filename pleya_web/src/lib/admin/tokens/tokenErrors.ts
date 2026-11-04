/**
 * Elke foutcode van de routes achter scherm 34, als een zin met een uitweg
 * (S10.6). Zelfde opzet als settingsErrors.ts.
 *
 * De codes uit `openapi.yaml` (createApiToken, listApiTokens, revokeSession,
 * listAudit) en `pleya_server/internal/api/handlers_api_tokens.go`:
 *
 * - `POST /auth/api-tokens`: `auth.scope_exceeds_role` (400, met `details.scope`
 *   en `details.role`: het bereik boven de rol van de eigenaar) en
 *   `session.invalid` (400, een naam, bereik of periode die niet klopt).
 * - `auth.user_not_found` (404): de aanvrager is geen beheerder (meer), of de
 *   aanvraag kwam van een API-token zonder bereik `admin`. De server gebruikt
 *   dezelfde code voor beide, byte-gelijk.
 * - `DELETE /sessions/{id}`: `auth.session_not_found` (404).
 * - `GET /audit`: `library.cursor_invalid` (400); dit scherm stuurt geen cursor.
 * - Overal: `server.internal` met verzoeknummer, `server.database_unavailable`,
 *   `storage.full` en de 401-codes van een verlopen sessie. Die vallen door naar
 *   `libraryProblem`, net als elke code die hier niet staat.
 */
import { ApiError } from '../../api/errors';
import { t } from '../../i18n';
import { libraryProblem, type LibraryProblem } from '../libraryErrors';
import { scopeLabel } from './tokens';
import { roleLabel } from '../users';
import type { Role } from '../../api/types';

export type TokenContext = 'create' | 'revoke';

export function tokenProblem(error: unknown, context: TokenContext, name = ''): LibraryProblem {
  if (error instanceof ApiError) {
    switch (error.code) {
      case 'auth.scope_exceeds_role': {
        const { scope, role } = error.details;
        return {
          code: error.code,
          message: t('admin.tok.err.scopeExceeds', {
            scope: typeof scope === 'string' ? scopeLabel(scope) : '',
            role: typeof role === 'string' ? roleLabel(role as Role).toLowerCase() : ''
          }),
          wayOut: 'none'
        };
      }
      case 'session.invalid':
        return { code: error.code, message: t('admin.tok.err.invalid'), wayOut: 'none' };
      case 'auth.user_not_found':
        return { code: error.code, message: t('admin.tok.err.notAdmin'), wayOut: 'home' };
      case 'auth.session_not_found':
        if (context === 'revoke') {
          return { code: error.code, message: t('admin.tok.err.sessionGone', { name }), wayOut: 'reload' };
        }
        break;
    }
  }
  return libraryProblem(error, name);
}
