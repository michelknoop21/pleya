/**
 * Een nepserver voor de tests van Onderhoud (S25.6): back-ups in het geheugen,
 * elke aanvraag met lichaam bijgehouden, per route een vast antwoord voor de
 * foutpaden, en een restore die eerst een paar keer 503 `server.maintenance`
 * geeft voor hij terugkomt. Alleen voor tests; niets in de app importeert dit.
 */
import type { Backup, BackupList, BackupRestoreTest } from '../../api/types';
import { apiError, clientFor, json, type Seen } from '../libraryFake';

export { apiError } from '../libraryFake';

/** De zin die de server als `restore_confirmation` geeft (internal/backup/restore.go). */
export function sentence(startedAt: string): string {
  return `herstel ${startedAt}: kijkstatus, gebruikers, sessies, instellingen en scans van daarna gaan verloren`;
}

export function restoreTest(extra: Partial<BackupRestoreTest> = {}): BackupRestoreTest {
  return {
    id: 't1',
    status: 'ok',
    started_at: '2026-10-25T03:45:00Z',
    finished_at: '2026-10-25T03:47:00Z',
    schema_from: 22,
    schema_to: 22,
    titles_expected: 576,
    titles_found: 576,
    failure_code: null,
    ...extra
  };
}

export function backup(id: string, extra: Partial<Backup> = {}): Backup {
  const started = extra.started_at ?? '2026-10-25T03:30:00Z';
  const status = extra.status ?? 'ok';
  return {
    id,
    status,
    trigger: 'schedule',
    started_at: started,
    finished_at: status === 'running' ? null : '2026-10-25T03:32:00Z',
    size_bytes: status === 'running' ? null : 412_000_000,
    schema_version: 22,
    titles: 576,
    secrets_included: true,
    failure_code: null,
    restore_confirmation: status === 'ok' ? sentence(started) : null,
    last_restore_test: null,
    ...extra
  };
}

export function list(items: Backup[], extra: Partial<BackupList> = {}): BackupList {
  return {
    items,
    dir: '/backups',
    schedule: '03:30',
    retention_days: 14,
    same_failure_domain: false,
    secrets_key_configured: true,
    ...extra
  };
}

export interface BackupsFakeOptions {
  list: BackupList;
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
  /** Na een geslaagde restore zoveel GET's lang 503 `server.maintenance`, daarna terug. */
  maintenanceCalls?: number;
}

export function backupsFake(options: BackupsFakeOptions) {
  const seen: Seen[] = [];
  const state = structuredClone(options.list);
  let maintenance = 0;

  const fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(request.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    const method = request.method;
    let body: unknown;
    if (method !== 'GET') {
      try {
        body = await request.clone().json();
      } catch {
        body = undefined;
      }
    }
    seen.push({ method, path, body });

    if (maintenance > 0) {
      maintenance -= 1;
      return apiError('server.maintenance', 503);
    }
    const failure = options.fail?.[`${method} ${path}`];
    if (failure) return typeof failure === 'function' ? failure() : failure.clone();

    if (method === 'GET' && path === '/backups') return json(state);
    if (method === 'POST' && path === '/backups') {
      if (state.items.some((b) => b.status === 'running')) return apiError('server.backup_busy', 409);
      const created = backup(`new-${state.items.length}`, {
        status: 'running',
        trigger: 'manual',
        started_at: '2026-10-26T10:00:00Z',
        schema_version: null,
        titles: null
      });
      state.items.unshift(created);
      return json(created, 202);
    }
    const action = path.match(/^\/backups\/([^/]+)\/(verify|restore)$/);
    if (method === 'POST' && action) {
      const target = state.items.find((b) => b.id === action[1]);
      if (!target) return apiError('library.not_found', 404);
      if (action[2] === 'verify') {
        if (target.status !== 'ok') return apiError('server.backup_not_restorable', 409, { reason: 'status' });
        target.last_restore_test = restoreTest({ status: 'running', finished_at: null });
        return json(target, 202);
      }
      const confirm = (body as { confirm?: string } | undefined)?.confirm;
      if (confirm !== target.restore_confirmation) {
        return apiError('server.confirm_mismatch', 409, { expected: target.restore_confirmation });
      }
      maintenance = options.maintenanceCalls ?? 0;
      return json(target, 202);
    }
    return apiError('library.not_found', 404);
  };

  return {
    client: clientFor(fetch),
    seen,
    state,
    /** Alleen de aanvragen die iets veranderen. */
    writes: () => seen.filter((s) => s.method !== 'GET').map((s) => `${s.method} ${s.path}`),
    restores: () => seen.filter((s) => s.method === 'POST' && s.path.endsWith('/restore'))
  };
}
