/**
 * Een nepserver voor de tests van scherm 34 (S10.6): gebruikers, API-tokens,
 * MCP-status en auditlog in het geheugen, elke aanvraag met methode, pad en
 * lichaam bijgehouden, en per route een foutantwoord in te stellen. De regels
 * die de echte server ook kent zijn nagebootst (een nieuw token krijgt een
 * geheim dat alleen in het antwoord staat, de lijst bevat nooit een geheim, een
 * ingetrokken token valt uit de lijst), zodat een test een weigering kan
 * uitlokken. Tokenwaarden zijn duidelijk nep. Alleen voor tests.
 */
import type { ApiToken } from '../../api/adminTokens';
import type { Role, ServerDetail, User } from '../../api/types';
import { apiError, clientFor, json, type Seen } from '../libraryFake';

export { apiError };

export const FAKE_SECRET = 'plyat1_NEP-GEEN-ECHT-GEHEIM-0123456789';

export function user(id: string, username: string, role: Role = 'member'): User {
  return { id, username, role } as User;
}

export function token(id: string, userId: string, name: string, extra: Partial<ApiToken> = {}): ApiToken {
  return {
    id,
    user_id: userId,
    name,
    scope: 'read',
    created_at: '2026-10-01T08:00:00Z',
    last_seen_at: '2026-10-26T08:00:00Z',
    expires_at: '2027-01-01T08:00:00Z',
    ...extra
  } as ApiToken;
}

export interface AuditRow {
  id: string;
  at: string;
  source: 'http' | 'mcp';
  operation: string;
  outcome: 'ok' | 'denied' | 'failed';
  user_id?: string;
  session_id?: string;
  target?: string;
}

export interface TokenFakeOptions {
  users: User[];
  /** Tokens per gebruikers-id. */
  tokens?: Record<string, ApiToken[]>;
  audit?: AuditRow[];
  mcp?: ServerDetail['mcp'];
  /** De rol van de aanvrager, voor de scope-cap van de nagebootste server. */
  requesterRole?: Role;
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
}

export function tokenFake(options: TokenFakeOptions) {
  const seen: Seen[] = [];
  const state = structuredClone({
    tokens: options.tokens ?? ({} as Record<string, ApiToken[]>),
    audit: options.audit ?? []
  });
  let counter = 0;

  const fetch = async (input: RequestInfo | URL, init?: RequestInit): Promise<Response> => {
    const request = input instanceof Request ? input : new Request(String(input), init);
    const url = new URL(request.url);
    const path = url.pathname.slice('/pleya/v1'.length);
    const method = request.method;
    const raw = method === 'GET' ? '' : await request.clone().text();
    const body = raw ? (JSON.parse(raw) as Record<string, unknown>) : undefined;
    seen.push({ method, path: path + (method === 'GET' ? url.search : ''), body });

    const failure = options.fail?.[`${method} ${path}`];
    if (failure) return typeof failure === 'function' ? failure() : failure.clone();

    if (method === 'GET' && path === '/users') return json({ items: options.users });
    if (method === 'GET' && path === '/server') {
      return json({
        id: 's1',
        name: 'Pleya-server',
        version: '0.9.0',
        started_at: '2026-10-20T07:41:00Z',
        mcp: options.mcp ?? { enabled: false, tool_count: 0 }
      });
    }
    if (method === 'GET' && path === '/auth/api-tokens') {
      return json({ items: state.tokens[url.searchParams.get('user_id') ?? ''] ?? [] });
    }
    if (method === 'GET' && path === '/audit') {
      const source = url.searchParams.get('source');
      const limit = Number(url.searchParams.get('limit') ?? 100);
      return json({
        items: state.audit.filter((a) => !source || a.source === source).slice(0, limit),
        next_cursor: null
      });
    }
    if (method === 'POST' && path === '/auth/api-tokens') {
      const scope = String(body?.['scope']);
      const name = String(body?.['name'] ?? '').trim();
      if (name === '' || name.length > 64) return apiError('session.invalid', 400);
      const role = options.requesterRole ?? 'owner';
      if (scope === 'admin' && role !== 'owner' && role !== 'admin') {
        return apiError('auth.scope_exceeds_role', 400, { scope, role });
      }
      const owner = options.users.find((u) => u.role === role) ?? options.users[0]!;
      const created = token(`new-${(counter += 1)}`, owner.id, name, {
        scope: scope as ApiToken['scope'],
        last_seen_at: new Date().toISOString(),
        expires_at: new Date(Date.now() + Number(body?.['expires_in_days'] ?? 90) * 86_400_000).toISOString()
      });
      (state.tokens[owner.id] ??= []).push(created);
      return json({ token: created, secret: FAKE_SECRET }, 201);
    }
    const revoke = path.match(/^\/sessions\/([^/]+)$/);
    if (method === 'DELETE' && revoke) {
      for (const list of Object.values(state.tokens)) {
        const at = list.findIndex((t) => t.id === revoke[1]);
        if (at >= 0) {
          list.splice(at, 1);
          return new Response(null, { status: 204 });
        }
      }
      return apiError('auth.session_not_found', 404);
    }
    return apiError('auth.user_not_found', 404);
  };

  return {
    client: clientFor(fetch),
    seen,
    /** Alleen de aanvragen die iets veranderen, als "METHOD /pad". */
    writes: () => seen.filter((s) => s.method !== 'GET').map((s) => `${s.method} ${s.path}`),
    state
  };
}
