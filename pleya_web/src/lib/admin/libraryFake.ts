/**
 * Een nepserver voor de tests van bibliotheekbeheer (S10.2): bibliotheken,
 * roots en scans in het geheugen, elke aanvraag met methode, pad en lichaam
 * bijgehouden, en per route een foutantwoord in te stellen. Alleen voor tests;
 * niets in de app importeert dit.
 */
import { PleyaClient, type FetchLike } from '../api/client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import type { Library, Scan, StorageRoot } from '../api/types';

const BASE = 'http://server.test/pleya/v1';

function memoryStorage(): TokenStorage {
  const map = new Map<string, string>();
  return {
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => void map.set(key, value),
    removeItem: (key) => void map.delete(key)
  };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}

export function apiError(code: string, status: number, details?: Record<string, unknown>): Response {
  return json({ error: { code, message: code, retryable: false, ...(details ? { details } : {}) } }, status);
}

export interface Seen {
  method: string;
  path: string;
  body: unknown;
}

export function library(id: string, title: string, extra: Partial<Library> = {}): Library {
  return {
    id,
    title,
    kind: 'movies',
    item_count: 0,
    managed: 'db',
    scan_interval_seconds: null,
    scan_on_start: true,
    ...extra
  };
}

export function root(path: string, owner: Library | null, extra: Partial<StorageRoot> = {}): StorageRoot {
  return {
    path,
    fs_type: 'btrfs',
    inode_trusted: true,
    inode_trust_source: 'fstype_default',
    mounted: true,
    free_bytes: 1_100_000_000_000,
    total_bytes: 2_000_000_000_000,
    libraries: owner ? [{ id: owner.id, title: owner.title }] : [],
    ...extra
  };
}

export function scan(libraryId: string, state: Scan['state'], extra: Partial<Scan> = {}): Scan {
  return {
    id: `scan-${libraryId}`,
    library_id: libraryId,
    trigger: 'manual',
    state,
    started_at: '2026-10-26T08:00:00Z',
    finished_at: state === 'running' || state === 'queued' ? null : '2026-10-26T08:11:00Z',
    files_seen: 120,
    files_new: 0,
    files_renamed: 0,
    files_changed: 0,
    files_probed: 0,
    files_missing: 0,
    bytes_hashed: 0,
    items_created: 3,
    versions_created: 0,
    error_count: 0,
    last_error: null,
    current_path: null,
    ...extra
  };
}

export interface LibraryFakeOptions {
  libraries: Library[];
  roots: StorageRoot[];
  scans?: Record<string, Scan>;
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
}

export function libraryFake(options: LibraryFakeOptions) {
  const seen: Seen[] = [];
  // Een eigen kopie: een PATCH of overname in de ene test mag de volgende
  // niet raken.
  const state = structuredClone({
    libraries: options.libraries,
    roots: options.roots,
    scans: options.scans ?? {}
  });

  const fetch: FetchLike = async (input, init) => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(request.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    const method = request.method;
    const text = method === 'GET' ? '' : await request.text();
    const body: unknown = text ? JSON.parse(text) : undefined;
    seen.push({ method, path, body });

    const failure = options.fail?.[`${method} ${path}`];
    if (failure) return typeof failure === 'function' ? failure() : failure.clone();

    const match = path.match(/^\/libraries\/([^/]+)(\/scan|\/adopt|\/metadata-coverage)?$/);
    if (method === 'GET' && path === '/libraries') return json({ items: state.libraries });
    if (method === 'GET' && path === '/storage/roots') return json({ roots: state.roots });
    if (method === 'GET' && path === '/scans') {
      const id = url.searchParams.get('library_id') ?? '';
      const found = state.scans[id];
      return json({ items: found ? [found] : [], next_cursor: null });
    }
    if (method === 'POST' && path === '/libraries') {
      const created = library('new1', (body as { title: string }).title);
      state.libraries.push(created);
      return json(created, 201);
    }
    if (match) {
      const [, id, sub] = match;
      const current = state.libraries.find((l) => l.id === id);
      if (!current) return apiError('library.not_found', 404);
      if (sub === '/scan' && method === 'POST') {
        state.scans[id!] = scan(id!, 'queued');
        return json(state.scans[id!], 202);
      }
      if (sub === '/adopt' && method === 'POST') {
        Object.assign(current, { managed: 'db' });
        return json(current);
      }
      if (sub === '/metadata-coverage') {
        return json({
          items: 10,
          with_sidecar: 9,
          with_summary: 9,
          with_genres: 9,
          ratio: 0.9,
          threshold: 0.8,
          gate_met: true
        });
      }
      if (!sub && method === 'PATCH') {
        Object.assign(current, body as object);
        return json(current);
      }
      if (!sub && method === 'DELETE') {
        if ((body as { confirm?: string }).confirm !== current.title) {
          return apiError('library.confirm_mismatch', 409);
        }
        state.libraries = state.libraries.filter((l) => l.id !== id);
        return new Response(null, { status: 204 });
      }
    }
    return apiError('library.not_found', 404);
  };

  const tokens = new TokenStore(memoryStorage(), memoryStorage());
  tokens.set({ access_token: 'a', refresh_token: 'r', expires_in_ms: 3_600_000 });
  const client = new PleyaClient({ baseUrl: BASE, tokens, fetch });

  return {
    client,
    seen,
    /** Alleen de aanvragen die iets veranderen. */
    writes: () => seen.filter((s) => s.method !== 'GET')
  };
}
