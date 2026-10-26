import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ApiError, TransportError } from '../api/errors';
import { setLocale } from '../i18n';
import { opsProblem } from './opsErrors';

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

function api(code: string, status: number, details: Record<string, unknown> = {}): ApiError {
  return new ApiError({ code, status, message: code, retryable: false, details });
}

describe('opsProblem: elke foutcode is een zin met een uitweg', () => {
  const cases: [string, number, Record<string, unknown>, string, string][] = [
    ['library.cursor_invalid', 400, {}, 'De lijst veranderde', 'reload'],
    ['library.not_found', 404, {}, 'Taak X is van de server verdwenen', 'reload'],
    ['job.not_cancellable', 409, { reason: 'finished' }, 'Taak X is al klaar', 'reload'],
    ['job.not_cancellable', 409, { reason: 'duplicate_in_flight' }, 'gelijke taak', 'reload'],
    ['job.not_cancellable', 409, {}, 'Taak X is nu niet te stoppen', 'reload'],
    ['storage.unavailable', 503, {}, 'kan nu niet bij zijn opslag', 'retry'],
    ['auth.user_not_found', 404, {}, 'geen beheerrechten meer', 'home'],
    ['auth.token_expired', 401, {}, '', 'login'],
    ['server.database_unavailable', 503, {}, 'database', 'retry'],
    ['storage.full', 507, {}, 'geen ruimte', 'retry'],
    ['server.internal', 500, {}, 'Er ging iets mis op de server', 'retry'],
    ['library.scan_in_progress', 409, {}, 'al een scan', 'activity']
  ];

  it.each(cases)('%s (%i) %j', (code, status, details, fragment, wayOut) => {
    const problem = opsProblem(api(code, status, details), 'Taak X');
    expect(problem.code).toBe(code);
    expect(problem.wayOut).toBe(wayOut);
    expect(problem.message).not.toBe('');
    expect(problem.message).toContain(fragment);
  });

  it('noemt het verzoeknummer bij een interne fout', () => {
    const problem = opsProblem(api('server.internal', 500, { request_id: 'r-42' }), 'x');
    expect(problem.message).toContain('r-42');
  });

  it('geeft bij een verbroken verbinding opnieuw proberen', () => {
    const problem = opsProblem(new TransportError(new Error('weg')), 'x');
    expect(problem.code).toBe('client.transport');
    expect(problem.wayOut).toBe('retry');
  });

  it('valt bij een onbekende code terug op een zin met opnieuw proberen', () => {
    const problem = opsProblem(api('iets.nieuws', 418), 'x');
    expect(problem.wayOut).toBe('retry');
    expect(problem.message).toContain('iets.nieuws');
  });
});
