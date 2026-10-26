/**
 * De foutcodes van de twee schrijfroutes achter scherm 36, als zin met een uitweg.
 *
 * - `PUT /items/{id}/metadata-match`: `library.invalid_match` (400, het nummer
 *   is geen positief geheel getal van hoogstens tien cijfers), `library.not_found`
 *   (404, het item bestaat niet meer; de server gebruikt die code voor een
 *   onbekend item), `auth.user_not_found` (404, geen beheerder), de 401-codes
 *   van een verlopen sessie en `server.internal`.
 * - `DELETE /items/{id}/metadata-match`: dezelfde, zonder `invalid_match`.
 *
 * De rest kent `libraryProblem` al. Een weigering laat de lijst op het scherm
 * staan; alleen "bestaat niet meer" is reden de lijst opnieuw te lezen.
 */
import { ApiError } from '../../api/errors';
import { t } from '../../i18n';
import { libraryProblem, type LibraryProblem } from '../libraryErrors';

export function matchProblem(error: unknown, name: string): LibraryProblem {
  if (error instanceof ApiError) {
    if (error.code === 'library.invalid_match') {
      return { code: error.code, message: t('admin.match.err.invalid'), wayOut: 'none' };
    }
    if (error.code === 'library.not_found') {
      return { code: error.code, message: t('admin.match.err.notFound', { name }), wayOut: 'reload' };
    }
  }
  return libraryProblem(error, name);
}
