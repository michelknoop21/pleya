import { describe, expect, it, vi } from 'vitest';

import { PleyaClient, type FetchLike } from './client';
import { ApiError, TransportError, describeError } from './errors';
import { TokenStore, type TokenStorage } from '../auth/tokens';

function memoryStorage(initial: Record<string, string> = {}): TokenStorage {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (key) => map.get(key) ?? null,
    setItem: (key, value) => void map.set(key, value),
    removeItem: (key) => void map.delete(key)
  };
}

/** Een tokenopslag met een eigen sessieopslag ernaast, zoals in de browser. */
function stores(refresh?: string) {
  const persistent = memoryStorage(refresh ? { 'pleya.refresh_token': refresh } : {});
  const session = memoryStorage();
  return { persistent, session, tokens: new TokenStore(persistent, session) };
}

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { 'Content-Type': 'application/json' }
  });
}

const BASE = 'http://server.test/pleya/v1';

function clientWith(fetchImpl: FetchLike, storage = memoryStorage()) {
  const tokens = new TokenStore(storage, memoryStorage());
  return { client: new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl }), tokens };
}

describe('de gegenereerde client', () => {
  it('praat uitsluitend met paden onder /pleya/v1', async () => {
    const seen: string[] = [];
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      seen.push(typeof input === 'string' ? input : input instanceof URL ? input.href : input.url);
      return json({ items: [] });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    await client.libraries();

    expect(seen).toHaveLength(1);
    expect(seen[0]).toBe(`${BASE}/libraries`);
  });

  it('geeft de lijst uit LibraryList terug', async () => {
    const fetchImpl = vi.fn(async () =>
      json({ items: [{ id: 'a', title: 'Films', kind: 'movies', item_count: 3 }] })
    ) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    await expect(client.libraries()).resolves.toEqual([
      { id: 'a', title: 'Films', kind: 'movies', item_count: 3 }
    ]);
  });

  it('stuurt de sortering en de cursor mee als queryparameters', async () => {
    let url = '';
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      return json({ items: [], next_cursor: null });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    await client.libraryItems('lib-1', { sort: '-added_at', cursor: 'opaque', limit: 50 });

    expect(url).toContain('/libraries/lib-1/items');
    expect(url).toContain('sort=-added_at');
    expect(url).toContain('cursor=opaque');
    expect(url).toContain('limit=50');
  });
});

describe('authenticatie op de aanvraag', () => {
  it('hangt het accesstoken aan een endpoint van klasse authenticated', async () => {
    let auth: string | null = null;
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      auth = input instanceof Request ? input.headers.get('Authorization') : null;
      return json({ items: [] });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });
    await client.libraries();

    expect(auth).toBe('Bearer A1');
  });

  it('laat een publiek endpoint zonder header', async () => {
    let auth: string | null = 'nog niet gelezen';
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      auth = input instanceof Request ? input.headers.get('Authorization') : null;
      return json({
        protocol: { major: 1, feature_level: 1, profile: 'full' },
        server: { id: 's' },
        capabilities: { browse: true, search: true, artwork: true, watch_state: false },
        auth: { methods: ['password'], setup_required: false }
      });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });
    await client.info();

    expect(auth).toBeNull();
  });
});

describe('tokenvernieuwing', () => {
  it('ververst na een 401 en stuurt de aanvraag opnieuw', async () => {
    const calls: string[] = [];
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const req = input as Request;
      const url = req.url;
      calls.push(`${req.method} ${url}`);

      if (url.endsWith('/auth/refresh')) {
        return json({
          access_token: 'A2',
          refresh_token: 'R2',
          token_type: 'bearer',
          expires_in_ms: 900000
        });
      }
      if (req.headers.get('Authorization') === 'Bearer A2') {
        return json({ items: [{ id: 'x', title: 'T', kind: 'movie', added_at: '2026-01-01T00:00:00Z' }] });
      }
      return json(
        { error: { code: 'auth.token_expired', message: 'expired', retryable: false } },
        401
      );
    }) as unknown as FetchLike;

    const { client, tokens } = clientWith(fetchImpl, memoryStorage({ 'pleya.refresh_token': 'R1' }));
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    const page = await client.search({ q: 'grease' });

    expect(page.items).toHaveLength(1);
    expect(calls.filter((c) => c.includes('/auth/refresh'))).toHaveLength(1);
    expect(tokens.accessToken).toBe('A2');
    expect(tokens.refreshToken).toBe('R2');
  });

  it('ververst hoogstens één keer tegelijk, want het refreshtoken roteert', async () => {
    let refreshes = 0;
    let release: () => void = () => {};
    const gate = new Promise<void>((resolve) => {
      release = resolve;
    });

    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const req = input as Request;
      if (req.url.endsWith('/auth/refresh')) {
        refreshes += 1;
        await gate;
        return json({
          access_token: 'A2',
          refresh_token: 'R2',
          token_type: 'bearer',
          expires_in_ms: 900000
        });
      }
      if (req.headers.get('Authorization') === 'Bearer A2') return json({ items: [] });
      return json(
        { error: { code: 'auth.token_expired', message: 'expired', retryable: false } },
        401
      );
    }) as unknown as FetchLike;

    const { client, tokens } = clientWith(fetchImpl, memoryStorage({ 'pleya.refresh_token': 'R1' }));
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    const all = Promise.all([client.libraries(), client.libraries(), client.libraries()]);
    // Alle drie de aanvragen zitten nu achter dezelfde refresh te wachten.
    await Promise.resolve();
    release();
    await all;

    expect(refreshes).toBe(1);
  });

  it('meldt de sessie verloren wanneer het refreshtoken zelf wordt afgewezen', async () => {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const req = input as Request;
      if (req.url.endsWith('/auth/refresh')) {
        return json(
          { error: { code: 'auth.refresh_token_reused', message: 'reused', retryable: false } },
          401
        );
      }
      return json({ error: { code: 'auth.token_expired', message: 'x', retryable: false } }, 401);
    }) as unknown as FetchLike;

    const lost = vi.fn();
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
    const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl, onSessionLost: lost });
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await expect(client.libraries()).rejects.toBeInstanceOf(ApiError);
    expect(lost).toHaveBeenCalledTimes(1);
    expect(tokens.refreshToken).toBeNull();
  });

  it('probeert niet eindeloos opnieuw wanneer het verse token ook faalt', async () => {
    let attempts = 0;
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const req = input as Request;
      if (req.url.endsWith('/auth/refresh')) {
        return json({
          access_token: 'A2',
          refresh_token: 'R2',
          token_type: 'bearer',
          expires_in_ms: 1
        });
      }
      attempts += 1;
      return json({ error: { code: 'auth.token_invalid', message: 'x', retryable: false } }, 401);
    }) as unknown as FetchLike;

    const { client, tokens } = clientWith(fetchImpl, memoryStorage({ 'pleya.refresh_token': 'R1' }));
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await expect(client.libraries()).rejects.toBeInstanceOf(ApiError);
    expect(attempts).toBe(2);
  });

  it('herstelt een sessie uit een bewaard refreshtoken', async () => {
    const fetchImpl = vi.fn(async () =>
      json({ access_token: 'A9', refresh_token: 'R9', token_type: 'bearer', expires_in_ms: 900000 })
    ) as unknown as FetchLike;

    const { client, tokens } = clientWith(fetchImpl, memoryStorage({ 'pleya.refresh_token': 'R1' }));

    await expect(client.restore()).resolves.toBe(true);
    expect(tokens.accessToken).toBe('A9');
  });

  it('herstelt niets zonder bewaard refreshtoken', async () => {
    const fetchImpl = vi.fn() as unknown as FetchLike;
    const { client } = clientWith(fetchImpl);
    await expect(client.restore()).resolves.toBe(false);
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});

describe('foutafhandeling', () => {
  it('vertaalt de foutvorm naar een ApiError met code, status en retryable', async () => {
    const fetchImpl = vi.fn(async () =>
      json({ error: { code: 'library.not_found', message: 'not found', retryable: false } }, 404)
    ) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await expect(client.item('nope')).rejects.toMatchObject({
      code: 'library.not_found',
      status: 404,
      retryable: false
    });
  });

  it('leest retry_after_ms uit details bij auth.rate_limited', async () => {
    const fetchImpl = vi.fn(async () =>
      json(
        {
          error: {
            code: 'auth.rate_limited',
            message: 'too many attempts',
            retryable: true,
            details: { retry_after_ms: 8400 }
          }
        },
        429
      )
    ) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    await client.login({ username: 'x', password: 'y' }).catch((err: unknown) => {
      expect(err).toBeInstanceOf(ApiError);
      const api = err as ApiError;
      expect(api.code).toBe('auth.rate_limited');
      expect(api.retryable).toBe(true);
      expect(api.retryAfterMs).toBe(8400);
    });
    expect.assertions(4);
  });

  it('behandelt een antwoord zonder foutvorm als fout in plaats van als leeg', async () => {
    const fetchImpl = vi.fn(
      async () => new Response('<html>proxy</html>', { status: 502, headers: { 'Content-Type': 'text/html' } })
    ) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await expect(client.libraries()).rejects.toMatchObject({ code: 'client.malformed_response' });
  });

  it('onderscheidt een netwerkstoring van een serverfout', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    const err = await client.libraries().catch((e: unknown) => e);
    expect(err).toBeInstanceOf(TransportError);
    expect(describeError(err)).toContain('Cannot reach the server');
  });

  it('geeft een onbekende servercode een leesbare tekst met de code erin', () => {
    const err = new ApiError({
      code: 'library.brand_new',
      message: 'x',
      status: 409,
      retryable: false
    });
    expect(describeError(err)).toContain('library.brand_new');
  });
});

describe('artwork', () => {
  it('haalt de bytes op met een Authorization-header en geeft een blob terug', async () => {
    let auth: string | null = null;
    const fetchImpl = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      auth = new Headers(init?.headers).get('Authorization');
      // Geen jsdom-Blob als body: die mist `stream()`, en undici's Response vraagt
      // daarom. Op macOS valt dat toevallig goed uit, op de Linux-runner niet.
      return new Response('bytes', { status: 200, headers: { 'content-type': 'image/jpeg' } });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    const blob = await client.artworkBlob('art-1');
    expect(blob.size).toBeGreaterThan(0);
    expect(auth).toBe('Bearer A1');
  });

  it('zet het artwork-id in het pad en niet in de querystring', async () => {
    let url = '';
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      url = String(input);
      return new Response('b', { status: 200 });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });
    await client.artworkBlob('art 1');

    expect(url).toBe(`${BASE}/artwork/art%201`);
    expect(url).not.toContain('token');
  });

  it('geeft een 404 door als ApiError, want dat is een normale toestand', async () => {
    const fetchImpl = vi.fn(async () =>
      json({ error: { code: 'library.not_found', message: 'x', retryable: false } }, 404)
    ) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await expect(client.artworkBlob('art-1')).rejects.toMatchObject({ code: 'library.not_found' });
  });
});

describe('afmelden', () => {
  it('doet geen aanroep, want het protocol kent geen uitlogendpoint', () => {
    const fetchImpl = vi.fn() as unknown as FetchLike;
    const { client, tokens } = clientWith(fetchImpl, memoryStorage({ 'pleya.refresh_token': 'R1' }));
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    client.signOut();

    expect(fetchImpl).not.toHaveBeenCalled();
    expect(tokens.accessToken).toBeNull();
    expect(tokens.refreshToken).toBeNull();
  });
});

describe('een herlaadbeurt', () => {
  it('ververst niet zolang het accesstoken nog geldig is', async () => {
    const fetchImpl = vi.fn() as unknown as FetchLike;
    const { persistent, session } = stores('R1');

    new TokenStore(persistent, session).set({
      access_token: 'A1',
      refresh_token: 'R1',
      expires_in_ms: 900_000
    });

    // Een verse client op dezelfde opslag is wat er na F5 gebeurt.
    const client = new PleyaClient({
      baseUrl: BASE,
      tokens: new TokenStore(persistent, session),
      fetch: fetchImpl
    });

    await expect(client.restore()).resolves.toBe(true);
    // Geen refresh, dus ook geen rotatie die een tweede herlaadbeurt kan
    // betrappen op hergebruik.
    expect(fetchImpl).not.toHaveBeenCalled();
  });

  it('ververst wel wanneer het accesstoken verlopen is', async () => {
    const fetchImpl = vi.fn(async () =>
      json({ access_token: 'A2', refresh_token: 'R2', token_type: 'bearer', expires_in_ms: 900_000 })
    ) as unknown as FetchLike;

    const { persistent, session } = stores('R1');
    const client = new PleyaClient({
      baseUrl: BASE,
      tokens: new TokenStore(persistent, session),
      fetch: fetchImpl
    });

    await expect(client.restore()).resolves.toBe(true);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
  });
});
