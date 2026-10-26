/** De rekenregels van scherm 35: waarschuwingen, de wachtlus na een restore en de foutzinnen. */
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { ApiError, TransportError } from '../../api/errors';
import { setLocale } from '../../i18n';
import type { AdminBackupsApi } from '../../api/adminBackups';
import { backupProblem } from './backupErrors';
import { isLive, waitForServer, warnings } from './backups';
import { backup, list, restoreTest } from './backupsFake';

const NOW = Date.parse('2026-10-26T12:00:00Z');
const ago = (days: number) => new Date(NOW - days * 86_400_000).toISOString();

beforeEach(() => setLocale('nl'));

function api(list: () => Promise<unknown>): AdminBackupsApi {
  return { list } as unknown as AdminBackupsApi;
}

const apiError = (code: string, status: number, details: Record<string, unknown> = {}) =>
  new ApiError({ code, message: code, status, retryable: false, details });

describe('isLive', () => {
  it('is waar voor een lopende back-up en voor een lopende hersteltest', () => {
    expect(isLive(list([backup('a', { status: 'running' })]))).toBe(true);
    expect(isLive(list([backup('a', { last_restore_test: restoreTest({ status: 'running' }) })]))).toBe(true);
  });

  it('is onwaar als alles klaar, mislukt of weg is', () => {
    const items = [backup('a'), backup('b', { status: 'failed' }), backup('c', { status: 'missing' })];
    expect(isLive(list(items))).toBe(false);
  });
});

describe('warnings', () => {
  const ids = (l: ReturnType<typeof list>) => warnings(l, NOW).map((w) => w.id);

  it('noemt niets bij een gezonde stand', () => {
    const ok = backup('a', { last_restore_test: restoreTest({ finished_at: ago(2) }) });
    expect(ids(list([ok]))).toEqual([]);
  });

  it('noemt een hersteltest van precies zeven dagen nog niet te oud, en acht dagen wel', () => {
    const seven = backup('a', { last_restore_test: restoreTest({ finished_at: ago(7) }) });
    const eight = backup('a', { last_restore_test: restoreTest({ finished_at: ago(8) }) });
    expect(ids(list([seven]))).toEqual([]);
    expect(ids(list([eight]))).toEqual(['testOld']);
  });

  it('telt een mislukte hersteltest niet als geslaagd', () => {
    const failed = backup('a', { last_restore_test: restoreTest({ status: 'failed', finished_at: ago(1) }) });
    expect(ids(list([failed]))).toEqual(['testNever']);
  });

  it('vraagt geen hersteltest als er geen geslaagde back-up is', () => {
    expect(ids(list([backup('a', { status: 'failed' })]))).toEqual(['failed']);
    expect(ids(list([]))).toEqual([]);
  });

  it('geeft de waarschuwingen uit het antwoord door', () => {
    const ok = backup('a', { last_restore_test: restoreTest({ finished_at: ago(1) }) });
    expect(ids(list([ok], { same_failure_domain: true, secrets_key_configured: false }))).toEqual(['domain', 'noKey']);
  });

  it('telt verdwenen back-ups in het enkel- en meervoud', () => {
    const ok = backup('a', { last_restore_test: restoreTest({ finished_at: ago(1) }) });
    const one = warnings(list([ok, backup('m', { status: 'missing' })]), NOW).find((w) => w.id === 'missing');
    const two = warnings(list([ok, backup('m', { status: 'missing' }), backup('n', { status: 'missing' })]), NOW).find(
      (w) => w.id === 'missing'
    );
    expect(one?.message).toMatch(/^1 back-up is uit/);
    expect(two?.message).toMatch(/^2 back-ups zijn uit/);
  });
});

describe('waitForServer', () => {
  const sleep = vi.fn(async () => {});

  beforeEach(() => sleep.mockClear());

  it('wacht door tijdens onderhoud, verbindingsfouten en een 502 van de proxy', async () => {
    const calls = [
      apiError('server.maintenance', 503),
      new TransportError(new Error('weg')),
      apiError('client.malformed_response', 502),
      'ok'
    ];
    const outcome = await waitForServer(
      api(async () => {
        const next = calls.shift();
        if (next === 'ok') return list([]);
        throw next;
      }),
      { sleep }
    );
    expect(outcome).toBe('back');
    expect(sleep).toHaveBeenCalledTimes(3);
  });

  it('stuurt bij een 401 naar opnieuw inloggen in plaats van te blijven wachten', async () => {
    const outcome = await waitForServer(
      api(async () => {
        throw apiError('auth.token_invalid', 401);
      }),
      { sleep }
    );
    expect(outcome).toBe('signin');
    expect(sleep).not.toHaveBeenCalled();
  });

  it('geeft op na de wachttijd en blijft niet eindeloos vragen', async () => {
    const list = vi.fn(async () => {
      throw apiError('server.maintenance', 503);
    });
    const outcome = await waitForServer(api(list), { sleep, intervalMs: 3000, maxMs: 30_000 });
    expect(outcome).toBe('timeout');
    expect(list).toHaveBeenCalledTimes(10);
  });

  it('stopt meteen als de pagina weggaat', async () => {
    const controller = new AbortController();
    controller.abort();
    const list = vi.fn(async () => {
      throw new TransportError(new Error('weg'));
    });
    expect(await waitForServer(api(list), { sleep, signal: controller.signal })).toBe('timeout');
    expect(list).not.toHaveBeenCalled();
  });

  it('gooit een onbekende fout niet weg als wachten', async () => {
    await expect(
      waitForServer(
        api(async () => {
          throw new TypeError('kapot');
        }),
        { sleep }
      )
    ).rejects.toThrow('kapot');
  });
});

describe('backupProblem', () => {
  const problem = (code: string, details: Record<string, unknown> = {}, action: 'create' | 'restore' = 'restore') =>
    backupProblem(apiError(code, 409, details), action);

  it('geeft elke redenen van niet terug te zetten een eigen zin', () => {
    const reasons = ['status', 'schema_newer', 'key', 'unreadable', 'iets-nieuws'];
    const messages = reasons.map((reason) => problem('server.backup_not_restorable', { reason }).message);
    expect(new Set(messages).size).toBe(reasons.length);
    for (const message of messages) expect(message).not.toMatch(/server\.backup/);
  });

  it('geeft een sleutelprobleem geen herlaadknop die niets oplost', () => {
    expect(problem('server.backup_not_restorable', { reason: 'key' }).wayOut).toBe('none');
  });

  it('kent de overige codes van de back-uproutes', () => {
    for (const code of ['server.backup_busy', 'server.confirm_mismatch', 'server.maintenance', 'library.not_found']) {
      const result = problem(code);
      expect(result.message, code).not.toMatch(/\(.*\.\w+\)/);
      expect(result.wayOut, code).toBe('reload');
    }
  });

  it('onderscheidt een volle schijf bij het maken van een back-up', () => {
    expect(problem('storage.full', {}, 'create').message).toMatch(/schrijven/);
    expect(problem('storage.full', {}, 'restore').message).not.toMatch(/schrijven/);
  });

  it('valt voor de rest terug op de bibliotheekzinnen', () => {
    expect(problem('server.database_unavailable').message).toMatch(/database/i);
    expect(problem('auth.user_not_found').wayOut).toBe('home');
  });
});
