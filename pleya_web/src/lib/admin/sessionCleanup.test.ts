/**
 * De rekenregels achter Oude toestellen opruimen en Overal uitloggen (DEC-164).
 */
import { afterEach, beforeEach, describe, expect, it } from 'vitest';

import { ApiError } from '../api/errors';
import { setLocale } from '../i18n';
import { deviceLabel, isStale, revokeEach, staleSessions, UNKNOWN_DEVICE_NAME } from './sessionCleanup';
import { userSession } from './userFake';

const NOW = Date.parse('2026-10-26T12:00:00Z');
const daysAgo = (n: number) => new Date(NOW - n * 86_400_000).toISOString();

beforeEach(() => setLocale('nl'));
afterEach(() => setLocale('en'));

describe('welke toestellen oud zijn', () => {
  it('telt alleen wat langer dan de periode niet gezien is', () => {
    expect(isStale(userSession('a', 'x', { last_seen_at: daysAgo(31) }), 30, NOW)).toBe(true);
    expect(isStale(userSession('a', 'x', { last_seen_at: daysAgo(29) }), 30, NOW)).toBe(false);
    expect(isStale(userSession('a', 'x', { last_seen_at: daysAgo(52) }), 60, NOW)).toBe(false);
  });

  it('sluit het eigen toestel en API-tokens uit, hoe oud ook (negatieve controle)', () => {
    const old = daysAgo(200);
    const items = [
      userSession('mine', 'Deze browser', { last_seen_at: old, current: true }),
      userSession('agent', 'Agent', { last_seen_at: old, kind: 'api' }),
      userSession('legacy', 'Legacy device', { last_seen_at: old, kind: 'legacy' }),
      userSession('dev', UNKNOWN_DEVICE_NAME, { last_seen_at: old })
    ];
    expect(staleSessions(items, (s) => s, 30, NOW).map((s) => s.id)).toEqual(['legacy', 'dev']);
  });

  it('laat een onleesbare datum staan', () => {
    expect(isStale(userSession('a', 'x', { last_seen_at: 'geen datum' }), 30, NOW)).toBe(false);
  });
});

describe('een rij intrekkingen', () => {
  it('gaat door na een fout en zegt wat lukte en wat niet', async () => {
    const seen: string[] = [];
    const progress: number[] = [];
    const outcome = await revokeEach(
      ['a', 'b', 'c', 'd'],
      async (id) => {
        seen.push(id);
        if (id === 'b') throw new ApiError({ status: 500, code: 'server.internal', message: 'kapot', retryable: true });
        if (id === 'c') throw new TypeError('Failed to fetch');
      },
      (n) => progress.push(n)
    );
    expect(seen).toEqual(['a', 'b', 'c', 'd']);
    expect(outcome.done).toEqual(['a', 'd']);
    expect(outcome.failed.map((f) => f.item)).toEqual(['b', 'c']);
    expect(progress).toEqual([1, 2, 3, 4]);
  });

  it('telt een sessie die al weg is als gelukt', async () => {
    const outcome = await revokeEach(['a'], async () => {
      throw new ApiError({ status: 404, code: 'auth.session_not_found', message: 'weg', retryable: false });
    });
    expect(outcome.done).toEqual(['a']);
    expect(outcome.failed).toEqual([]);
  });
});

describe('de naam van een toestel', () => {
  it('toont de plaatshouder van de server als Onbekend toestel, met de dag van aanmelden waar gevraagd', () => {
    const unknown = userSession('a', UNKNOWN_DEVICE_NAME, { created_at: '2026-09-04T10:00:00Z' });
    expect(deviceLabel(unknown)).toBe('Onbekend toestel');
    expect(deviceLabel(unknown, true)).toBe('Onbekend toestel, aangemeld op 4 september 2026');
    expect(deviceLabel(userSession('b', '  ', {}))).toBe('Onbekend toestel');
  });

  it('laat een echte naam staan', () => {
    expect(deviceLabel(userSession('a', 'Safari op macOS'), true)).toBe('Safari op macOS');
  });
});
