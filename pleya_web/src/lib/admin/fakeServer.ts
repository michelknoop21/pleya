/**
 * Een nepserver voor de beheertests: één fetch die op pad antwoordt en elke
 * aanvraag bijhoudt, zodat een test kan tellen welke beheerpaden er gevraagd
 * zijn. Alleen voor tests; niets in de app importeert dit.
 */
import { PleyaClient, type FetchLike } from '../api/client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import type { Role } from '../api/types';
import { ADMIN_PATHS } from '../api/admin';

export const FAKE_BASE = 'http://server.test/pleya/v1';

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

const NOT_FOUND = { error: { code: 'auth.user_not_found', message: 'not found', retryable: false } };

export interface FakeServerOptions {
  role: Role;
  administration?: boolean;
  signedIn?: boolean;
}

export function fakeServer({ role, administration = true, signedIn = true }: FakeServerOptions) {
  const seen: string[] = [];
  const isAdmin = role === 'owner' || role === 'admin';

  const fetch: FetchLike = async (input) => {
    const url = new URL(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    seen.push(path);
    // De server zelf: een lid krijgt 404 op elk beheerpad.
    if ((ADMIN_PATHS as readonly string[]).includes(path) && !isAdmin) return json(NOT_FOUND, 404);
    switch (path) {
      case '/info':
        return json({
          protocol: { major: 1, feature_level: 1, profile: 'full' },
          server: { id: 's1' },
          capabilities: { browse: true, search: true, artwork: true, watch_state: true, users: true, administration },
          auth: { methods: ['password'], setup_required: false }
        });
      case '/server':
        return json({ id: 's1', name: 'Pleya-server', version: '0.9.0', started_at: '2026-10-25T10:00:00Z' });
      case '/libraries':
        return json({ items: [{ id: 'l1', title: 'Films', kind: 'movies', item_count: 461 }] });
      case '/users/me':
        return json({ id: 'u1', username: 'michel', role });
      case '/users':
        return json({ items: [{ id: 'u1', username: 'michel', role }] });
      case '/scans':
      case '/jobs':
        return json({ items: [], next_cursor: null });
      case '/storage/roots':
        return json({ roots: [] });
      case '/stream-sessions':
        return json({ items: [] });
      case '/transcode-sessions':
        return json({ max_sessions: 0, hardware: { accel: 'none', reason: null }, items: [] });
      default:
        return json(NOT_FOUND, 404);
    }
  };

  const tokens = new TokenStore(memoryStorage(), memoryStorage());
  if (signedIn) tokens.set({ access_token: 'a', refresh_token: 'r', expires_in_ms: 3_600_000 });
  const client = new PleyaClient({ baseUrl: FAKE_BASE, tokens, fetch });

  return {
    client,
    seen,
    /** De beheerpaden die gevraagd zijn; `/users/me` is geen beheerpad. */
    adminCalls: () => seen.filter((p) => (ADMIN_PATHS as readonly string[]).includes(p))
  };
}
