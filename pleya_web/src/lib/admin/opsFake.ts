/**
 * Een nepserver voor de tests van Opslag en Scans en taken (S10.3): roots,
 * bibliotheken, scans en jobs in het geheugen, elke aanvraag bijgehouden, en
 * per route een foutantwoord in te stellen. Alleen voor tests.
 */
import type { Job, Library, Scan, StorageRoot } from '../api/types';
import { apiError, clientFor, json, type Seen } from './libraryFake';

export { apiError, library, root, scan } from './libraryFake';

export function job(id: string, extra: Partial<Job> = {}): Job {
  return {
    id,
    kind: 'scan_library',
    state: 'failed',
    attempts: 3,
    max_attempts: 3,
    last_error: 'ffprobe gaf na 60 s geen antwoord',
    run_at: '2026-10-26T08:00:00Z',
    created_at: '2026-10-26T08:00:00Z',
    finished_at: '2026-10-26T08:05:00Z',
    cancel_requested_at: null,
    ...extra
  };
}

export interface OpsFakeOptions {
  libraries?: Library[];
  roots?: StorageRoot[];
  /** Nieuwste eerst, zoals de server ze geeft. */
  scans?: Scan[];
  jobs?: Job[];
  /** Pagina's scans na de eerste, gevraagd met `cursor=pageN`. */
  morePages?: Scan[][];
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
}

export function opsFake(options: OpsFakeOptions) {
  const seen: Seen[] = [];
  const state = structuredClone({
    libraries: options.libraries ?? [],
    roots: options.roots ?? [],
    scans: options.scans ?? [],
    jobs: options.jobs ?? [],
    morePages: options.morePages ?? []
  });

  const fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(request.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    const method = request.method;
    seen.push({ method, path: path + (url.search && method === 'GET' ? url.search : ''), body: undefined });

    // Een route met cursor krijgt ook een eigen sleutel: "GET /scans?cursor=page1".
    const cursor = url.searchParams.get('cursor');
    const cursorKey = cursor ? `?cursor=${cursor}` : '';
    const failure = options.fail?.[`${method} ${path}${cursorKey}`] ?? options.fail?.[`${method} ${path}`];
    if (failure) return typeof failure === 'function' ? failure() : failure.clone();

    if (method === 'GET' && path === '/libraries') return json({ items: state.libraries });
    if (method === 'GET' && path === '/storage/roots') return json({ roots: state.roots });
    if (method === 'GET' && path === '/scans') {
      const cursor = url.searchParams.get('cursor');
      if (cursor) {
        const index = Number(cursor.replace('page', ''));
        const items = state.morePages[index - 1] ?? [];
        return json({ items, next_cursor: index < state.morePages.length ? `page${index + 1}` : null });
      }
      // Zoals de server: `library_id` en `limit` beperken de lijst, nieuwste eerst.
      const libraryId = url.searchParams.get('library_id');
      const limit = Number(url.searchParams.get('limit') ?? '');
      let items = libraryId ? state.scans.filter((s) => s.library_id === libraryId) : state.scans;
      if (libraryId && limit > 0) items = items.slice(0, limit);
      return json({ items, next_cursor: libraryId || !state.morePages.length ? null : 'page1' });
    }
    if (method === 'GET' && path === '/jobs') return json({ items: state.jobs, next_cursor: null });
    if (method === 'POST' && path === '/storage/roots/recheck') return new Response(null, { status: 202 });

    const scan = path.match(/^\/libraries\/([^/]+)\/scan$/);
    if (method === 'POST' && scan) {
      const id = scan[1]!;
      if (!state.libraries.some((l) => l.id === id)) return apiError('library.not_found', 404);
      return json({ id: `new-${id}`, library_id: id, state: 'queued' }, 202);
    }
    const act = path.match(/^\/jobs\/([^/]+)\/(cancel|retry)$/);
    if (method === 'POST' && act) {
      const current = state.jobs.find((j) => j.id === act[1]);
      if (!current) return apiError('library.not_found', 404);
      if (act[2] === 'cancel') current.cancel_requested_at = '2026-10-26T09:00:00Z';
      else current.state = 'pending';
      return json(current);
    }
    return apiError('library.not_found', 404);
  };

  return {
    client: clientFor(fetch),
    seen,
    /** Alleen de aanvragen die iets veranderen. */
    writes: () => seen.filter((s) => s.method !== 'GET').map((s) => `${s.method} ${s.path}`),
    state
  };
}
