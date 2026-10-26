/**
 * Een nepserver voor de tests van de instellingenschermen (S10.5): instellingen,
 * serverdetail, omgeving, log, sessies en transcodesessies in het geheugen, elke
 * aanvraag met methode, pad en lichaam bijgehouden, en per route een
 * foutantwoord in te stellen. Alleen voor tests.
 */
import type { UserSession } from '../../api/adminUsers';
import type {
  ConnectivityCheck,
  Info,
  ServerDetail,
  ServerEnvironment,
  ServerLog,
  Settings,
  TranscodeSessionList,
  User
} from '../../api/types';
import { apiError, clientFor, json, library, type Seen } from '../libraryFake';

export { apiError, library };

export function baseSettings(): Settings {
  return {
    server_name: { value: 'Pleya-server', source: 'env' },
    access_token_ttl: { value: '15m0s', source: 'env' },
    refresh_token_ttl: { value: '720h0m0s', source: 'env' },
    stream_token_ttl: { value: '5m0s', source: 'env' },
    stream_session_ttl: { value: '30m0s', source: 'env' },
    max_stream_sessions: { value: 8, source: 'env' },
    public_url: { value: 'https://web.pleya.app', source: 'env' },
    web_origin: { value: '', source: 'env' },
    cors_origins: { value: [], source: 'env' }
  };
}

export function baseServer(): ServerDetail {
  return {
    id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77',
    name: 'Pleya-server',
    version: '0.9.0',
    started_at: '2026-10-20T07:41:00Z',
    public_url: 'https://web.pleya.app',
    listen: ':8080',
    behind_proxy: true,
    trusted_proxies: ['172.18.0.0/16'],
    build: 'go1.23 linux/amd64',
    database: { version: '18.6', schema: 8 },
    ffprobe: { found: true, version: 'ffmpeg 5.1.9' },
    health: { ready: true, jobs_running: 1, jobs_failed: 2 },
    mcp: { enabled: false, tool_count: 0 }
  } as ServerDetail;
}

export function baseInfo(): Info {
  return {
    protocol: { major: 1, feature_level: 1, profile: 'full' },
    server: { id: '0191f2a4-7c3e-7d10-9b2a-6f1e0c2d5a77' },
    capabilities: {
      browse: true,
      search: true,
      artwork: true,
      watch_state: true,
      transcode: true,
      downloads: true,
      users: true,
      administration: true,
      live_tv: false
    },
    auth: { methods: ['password'], setup_required: false }
  } as Info;
}

export function user(id: string, username: string, role: User['role'] = 'member'): User {
  return { id, username, role } as User;
}

export function device(
  id: string,
  name: string,
  extra: Partial<UserSession> = {}
): UserSession {
  return {
    id,
    device_name: name,
    created_at: '2026-10-01T08:00:00Z',
    last_seen_at: '2026-10-26T08:00:00Z',
    current: false,
    kind: 'device',
    ...extra
  } as UserSession;
}

export interface SettingsFakeOptions {
  settings?: Settings;
  server?: ServerDetail;
  info?: Info;
  users?: User[];
  /** Sessies per gebruikers-id. */
  sessions?: Record<string, UserSession[]>;
  environment?: ServerEnvironment['entries'];
  log?: ServerLog['entries'];
  transcode?: TranscodeSessionList;
  connectivity?: ConnectivityCheck;
  coverage?: Record<string, unknown>;
  attention?: unknown;
  libraries?: ReturnType<typeof library>[];
  /** "METHOD /pad" naar een vast antwoord, voor de foutpaden. */
  fail?: Record<string, Response | (() => Response)>;
}

export function settingsFake(options: SettingsFakeOptions = {}) {
  const seen: Seen[] = [];
  const state = structuredClone({
    settings: options.settings ?? baseSettings(),
    sessions: options.sessions ?? {},
    transcode: options.transcode ?? {
      max_sessions: 2,
      hardware: { accel: 'none', reason: 'no render node' },
      items: []
    }
  });

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

    if (method === 'GET' && path === '/settings') return json(state.settings);
    if (method === 'PATCH' && path === '/settings') {
      for (const [key, value] of Object.entries(body as Record<string, unknown>)) {
        (state.settings as Record<string, { value: unknown; source: string }>)[key] = { value, source: 'db' };
        if (key.endsWith('_ttl')) {
          (state.settings as Record<string, { value: unknown }>)[key]!.value = `${value as string}`;
        }
      }
      return json(state.settings);
    }
    if (method === 'GET' && path === '/server') return json(options.server ?? baseServer());
    if (method === 'GET' && path === '/info') return json(options.info ?? baseInfo());
    if (method === 'GET' && path === '/libraries') return json({ items: options.libraries ?? [] });
    if (method === 'GET' && path === '/users') return json({ items: options.users ?? [] });
    if (method === 'GET' && path === '/sessions') {
      return json({ items: state.sessions[url.searchParams.get('user_id') ?? ''] ?? [] });
    }
    const revoke = path.match(/^\/sessions\/([^/]+)$/);
    if (method === 'DELETE' && revoke) {
      for (const list of Object.values(state.sessions)) {
        const at = list.findIndex((s) => s.id === revoke[1]);
        if (at >= 0) {
          list.splice(at, 1);
          return new Response(null, { status: 204 });
        }
      }
      return apiError('auth.session_not_found', 404);
    }
    if (method === 'GET' && path === '/server/environment') return json({ entries: options.environment ?? [] });
    if (method === 'GET' && path === '/server/log') return json({ entries: options.log ?? [] });
    if (method === 'POST' && path === '/server/connectivity-check') {
      return json(options.connectivity ?? { public_url_reachable: true, range_intact: true, behind_proxy: true });
    }
    if (method === 'POST' && path === '/server/rotate-signing-key') {
      return (body as { confirm?: string } | undefined)?.confirm === 'rotate'
        ? new Response(null, { status: 204 })
        : apiError('server.confirm_mismatch', 409, { expected: 'rotate' });
    }
    if (method === 'GET' && path === '/transcode-sessions') return json(state.transcode);
    const stop = path.match(/^\/transcode-sessions\/([^/]+)$/);
    if (method === 'DELETE' && stop) {
      const at = state.transcode.items.findIndex((s) => s.id === stop[1]);
      if (at < 0) return apiError('library.not_found', 404);
      state.transcode.items.splice(at, 1);
      return new Response(null, { status: 204 });
    }
    const coverage = path.match(/^\/libraries\/([^/]+)\/metadata-coverage$/);
    if (method === 'GET' && coverage) {
      const hit = options.coverage?.[coverage[1]!];
      return hit ? json(hit) : apiError('library.not_found', 404);
    }
    if (method === 'GET' && path === '/metadata/attention') {
      return json(options.attention ?? { items: [], total: 0 });
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
