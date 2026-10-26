/**
 * Een nepserver voor de tests van gebruikersbeheer (S10.4): gebruikers,
 * bibliotheken, sessies en rechten in het geheugen, elke aanvraag met methode,
 * pad en lichaam bijgehouden, en per route een foutantwoord in te stellen.
 * De regels die de echte server ook kent zijn nagebootst (de eigenaar is vast,
 * een beperkte gebruiker krijgt geen Beheren, een naam is uniek), zodat een test
 * een weigering kan uitlokken in plaats van alleen kan voorschrijven. Alleen
 * voor tests; niets in de app importeert dit.
 */
import { PleyaClient, type FetchLike } from '../api/client';
import type { UserSession } from '../api/adminUsers';
import { TokenStore } from '../auth/tokens';
import type { Role, User } from '../api/types';
import { apiError, json, library, memoryStorage, type Seen } from './libraryFake';

export { apiError, library };

const BASE = 'http://server.test/pleya/v1';

export function user(id: string, username: string, role: Role): User {
  return { id, username, role };
}

export function userSession(id: string, device: string, extra: Partial<UserSession> = {}): UserSession {
  return {
    id,
    device_name: device,
    created_at: '2026-08-28T10:00:00Z',
    last_seen_at: '2026-10-26T08:02:00Z',
    current: false,
    kind: 'device',
    ...extra
  };
}

export interface UserFakeOptions {
  users: User[];
  libraries: ReturnType<typeof library>[];
  /** Sessies per gebruikers-id. */
  sessions?: Record<string, UserSession[]>;
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
}

interface Right {
  library_id: string;
  permission: string;
}

export function userFake(options: UserFakeOptions) {
  const seen: Seen[] = [];
  const state = structuredClone({
    users: options.users,
    libraries: options.libraries,
    sessions: options.sessions ?? {},
    rights: {} as Record<string, Right[]>
  });

  const fetch: FetchLike = async (input, init) => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(request.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    const method = request.method;
    const text = method === 'GET' ? '' : await request.text();
    const body = (text ? JSON.parse(text) : undefined) as Record<string, unknown> | undefined;
    seen.push({ method, path, body });

    const failure = options.fail?.[`${method} ${path}`];
    if (failure) return typeof failure === 'function' ? failure() : failure.clone();

    if (method === 'GET' && path === '/users') return json({ items: state.users });
    if (method === 'GET' && path === '/libraries') return json({ items: state.libraries });
    if (method === 'GET' && path === '/sessions') {
      return json({ items: state.sessions[url.searchParams.get('user_id') ?? ''] ?? [] });
    }
    if (method === 'POST' && path === '/users') {
      const name = String(body?.['username']);
      if (state.users.some((u) => u.username === name)) return apiError('auth.username_taken', 409);
      const created = user(`u${state.users.length + 1}`, name, body?.['role'] as Role);
      state.users.push(created);
      return json(created);
    }

    const session = path.match(/^\/sessions\/([^/]+)$/);
    if (session && method === 'DELETE') {
      for (const list of Object.values(state.sessions)) {
        const at = list.findIndex((s) => s.id === session[1]);
        if (at >= 0) {
          list.splice(at, 1);
          return new Response(null, { status: 204 });
        }
      }
      return apiError('auth.session_not_found', 404);
    }

    const match = path.match(/^\/users\/([^/]+)(\/permissions)?$/);
    if (match) {
      const target = state.users.find((u) => u.id === match[1]);
      if (!target) return apiError('auth.user_not_found', 404);
      if (match[2] && method === 'PUT') {
        const list = (body?.['permissions'] ?? []) as Right[];
        if (target.role === 'restricted' && list.some((p) => p.permission === 'manage')) {
          return apiError('auth.permission_not_allowed', 409, { permission: 'manage', role: 'restricted' });
        }
        if (list.some((p) => !state.libraries.some((l) => l.id === p.library_id))) {
          return apiError('library.not_found', 404);
        }
        state.rights[target.id] = list;
        return json({ items: list });
      }
      if (method === 'PATCH') {
        if (target.role === 'owner' && body?.['role'] && body['role'] !== 'owner') {
          return apiError('auth.owner_immutable', 409);
        }
        if (body?.['role']) target.role = body['role'] as Role;
        return json(target);
      }
      if (method === 'DELETE') {
        if (target.role === 'owner') return apiError('auth.owner_immutable', 409);
        state.users = state.users.filter((u) => u.id !== target.id);
        return new Response(null, { status: 204 });
      }
    }
    return apiError('auth.user_not_found', 404);
  };

  const tokens = new TokenStore(memoryStorage(), memoryStorage());
  tokens.set({ access_token: 'a', refresh_token: 'r', expires_in_ms: 3_600_000 });
  const client = new PleyaClient({ baseUrl: BASE, tokens, fetch });

  return {
    client,
    seen,
    /** Alleen de aanvragen die iets veranderen. */
    writes: () => seen.filter((s) => s.method !== 'GET'),
    /** De rechten die de server na een PUT bewaart. */
    rightsOf: (id: string) => state.rights[id]
  };
}
