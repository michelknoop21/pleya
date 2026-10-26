/**
 * Een nepserver voor de tests van scherm 36 (S22.6): de aandachtslijst in het
 * geheugen, PUT en DELETE op `/items/{id}/metadata-match`, elke aanvraag met
 * methode, pad en lichaam bijgehouden, en per route een foutantwoord in te
 * stellen. Een gekozen of afgewezen titel gedraagt zich als de server: een
 * keuze haalt hem van de lijst, een afwijzing zet hem op `rejected`.
 * Alleen voor tests.
 */
import type { MetadataAttention } from '../../api/types';
import { apiError, clientFor, json, type Seen } from '../libraryFake';

export { apiError };

export function attention(
  id: string,
  title: string,
  state: MetadataAttention['state'],
  extra: Partial<MetadataAttention> = {}
): MetadataAttention {
  return {
    item_id: id,
    library_id: 'l1',
    kind: 'movie',
    title,
    year: 2021,
    state,
    alternatives: [],
    updated_at: '2026-10-26T08:00:00Z',
    ...extra
  };
}

export interface MatchFakeOptions {
  items?: MetadataAttention[];
  /** Het werkelijke aantal als de lijst is afgekapt. */
  total?: number;
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
}

export function matchFake(options: MatchFakeOptions = {}) {
  const seen: Seen[] = [];
  const state = structuredClone({ items: options.items ?? [] });

  const fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(request.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    const method = request.method;
    const raw = method === 'GET' ? '' : await request.clone().text();
    const body = raw ? (JSON.parse(raw) as unknown) : undefined;
    seen.push({ method, path: path + (method === 'GET' ? url.search : ''), body });

    const failure = options.fail?.[`${method} ${path}`];
    if (failure) return typeof failure === 'function' ? failure() : failure.clone();

    if (method === 'GET' && path === '/metadata/attention') {
      return json({ items: state.items, total: options.total ?? state.items.length });
    }
    const match = path.match(/^\/items\/([^/]+)\/metadata-match$/);
    if (match) {
      const id = match[1]!;
      const at = state.items.findIndex((i) => i.item_id === id);
      if (at < 0) return apiError('library.not_found', 404);
      if (method === 'PUT') {
        const externalId = (body as { external_id?: string }).external_id ?? '';
        if (!/^[1-9][0-9]{0,9}$/.test(externalId)) return apiError('library.invalid_match', 400);
        state.items.splice(at, 1);
        return json({ item_id: id, state: 'matched', external_id: externalId }, 202);
      }
      if (method === 'DELETE') {
        state.items[at] = { ...state.items[at]!, state: 'rejected', alternatives: [] };
        return json({ item_id: id, state: 'rejected', external_id: null });
      }
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
