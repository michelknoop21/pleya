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

  describe('een storing op de verversing', () => {
    const envelope = (status: number, code: string) =>
      json({ error: { code, message: 'x', retryable: status >= 500 } }, status);
    const expired = () => json({ error: { code: 'auth.token_expired', message: 'x', retryable: false } }, 401);

    function setup(answer: () => Response | Promise<Response>) {
      const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
        const req = input as Request;
        return req.url.endsWith('/auth/refresh') ? await answer() : expired();
      }) as unknown as FetchLike;
      const lost = vi.fn();
      const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
      const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl, onSessionLost: lost });
      tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 0 });
      return { client, tokens, lost };
    }

    it.each([
      ['500 met envelop', () => envelope(500, 'server.internal')],
      ['503 met envelop', () => envelope(503, 'storage.unavailable')],
      ['502 van een proxy zonder envelop', () => new Response('<html>Bad Gateway</html>', { status: 502 })],
      ['503 zonder inhoud', () => new Response(null, { status: 503 })],
      ['204 zonder inhoud', () => new Response(null, { status: 204 })],
      ['een netwerkfout', () => { throw new TypeError('failed to fetch'); }]
    ])('logt niet uit bij %s en laat het token staan', async (_name, answer) => {
      const { client, tokens, lost } = setup(answer);
      await expect(client.libraries()).rejects.toBeInstanceOf(ApiError);
      expect(lost).not.toHaveBeenCalled();
      expect(tokens.refreshToken).toBe('R1');
      expect(client.refreshUnavailable).toBe(true);
    });

    it.each([
      ['401 zonder bekende code', 401, 'auth.something_new'],
      ['auth.token_invalid', 401, 'auth.token_invalid'],
      ['auth.token_expired', 401, 'auth.token_expired'],
      ['auth.refresh_token_reused', 401, 'auth.refresh_token_reused']
    ])('logt wel uit bij %s (negatieve controle)', async (_name, status, code) => {
      const { client, tokens, lost } = setup(() => envelope(status, code));
      await expect(client.libraries()).rejects.toBeInstanceOf(ApiError);
      expect(lost).toHaveBeenCalledOnce();
      expect(tokens.refreshToken).toBeNull();
      expect(client.refreshUnavailable).toBe(false);
    });
  });

  it('een geweigerde origin is geen storing en geen uitloggen', async () => {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const req = input as Request;
      const refused = { error: { code: 'auth.origin_rejected', message: 'x', retryable: false } };
      return req.url.endsWith('/auth/refresh')
        ? json(refused, 403)
        : json({ error: { code: 'auth.token_expired', message: 'x', retryable: false } }, 401);
    }) as unknown as FetchLike;
    const lost = vi.fn();
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
    const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl, onSessionLost: lost });
    await expect(client.restore()).resolves.toBe(false);
    expect(client.refreshRefused?.code).toBe('auth.origin_rejected');
    expect(client.refreshUnavailable).toBe(false);
    expect(lost).not.toHaveBeenCalled();
    expect(tokens.refreshToken).toBe('R1');
  });

  describe('een 429 op de verversing (S15.1)', () => {
    const limited = (retryAfter: string | null = '2') => new Response(
      JSON.stringify({ error: { code: 'auth.rate_limited', message: 'x', retryable: true, details: { retry_after_ms: 1500 } } }),
      { status: 429, headers: { 'Content-Type': 'application/json', ...(retryAfter ? { 'Retry-After': retryAfter } : {}) } }
    );
    const pair = (n: number) => json({ access_token: `A${n}`, refresh_token: `R${n}`, token_type: 'bearer', expires_in_ms: 900_000 });
    const expired = () => json({ error: { code: 'auth.token_expired', message: 'x', retryable: false } }, 401);

    function setup(answers: (() => Response)[], options: { delay?: (ms: number) => Promise<void> } = {}) {
      const bodies: unknown[] = [];
      const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
        const req = input as Request;
        if (req.url.endsWith('/auth/refresh')) {
          bodies.push(await req.clone().json());
          return answers.shift()!();
        }
        return req.headers.get('x-pleya-retry') === '1' ? json({ items: [] }) : expired();
      }) as unknown as FetchLike;
      const lost = vi.fn();
      const delays: number[] = [];
      const delay = options.delay ?? (async (ms: number) => void delays.push(ms));
      const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
      const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl, onSessionLost: lost, delay });
      tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 0 });
      return { client, tokens, lost, delays, bodies };
    }

    it('wacht volgens Retry-After, ververst en houdt de sessie', async () => {
      const { client, tokens, lost, delays, bodies } = setup([() => limited('2'), () => pair(2)]);
      await expect(client.libraries()).resolves.toEqual([]);
      expect(lost).not.toHaveBeenCalled();
      expect(delays).toHaveLength(1);
      expect(delays[0]).toBeGreaterThanOrEqual(2000);
      expect(delays[0]).toBeLessThan(2750);
      expect(tokens.refreshToken).toBe('R2');
      expect(bodies).toEqual([{ refresh_token: 'R1' }, { refresh_token: 'R1' }]);
      expect(client.refreshUnavailable).toBe(false);
    });

    it('valt terug op retry_after_ms zonder de header', async () => {
      const { client, delays } = setup([() => limited(null), () => pair(2)]);
      await client.libraries();
      expect(delays[0]).toBeGreaterThanOrEqual(1500);
      expect(delays[0]).toBeLessThan(2250);
    });

    it('geeft op zonder uit te loggen en laat de tokens staan', async () => {
      const { client, tokens, lost, delays } = setup(Array.from({ length: 5 }, () => () => limited('1')));
      await expect(client.libraries()).rejects.toBeInstanceOf(ApiError);
      expect(lost).not.toHaveBeenCalled();
      expect(tokens.refreshToken).toBe('R1');
      expect(delays).toHaveLength(4);
      expect(client.refreshUnavailable).toBe(true);
    });

    it('telt hetzelfde token niet als geslaagd, ook niet als het lokaal nog geldt', async () => {
      const { client, tokens, bodies } = setup([() => limited('1'), () => pair(2)]);
      tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });
      await expect(client.libraries()).resolves.toEqual([]);
      expect(bodies).toHaveLength(2);
      expect(tokens.accessToken).toBe('A2');
    });

    it('wacht niet op een proxy die een uur vraagt', async () => {
      const { client, tokens, lost, delays } = setup([() => limited('3600')]);
      await expect(client.libraries()).rejects.toBeInstanceOf(ApiError);
      expect(delays).toHaveLength(0);
      expect(lost).not.toHaveBeenCalled();
      expect(tokens.refreshToken).toBe('R1');
    });

    it('gebruikt na het wachten het token dat een ander tabblad intussen roteerde', async () => {
      const ref: { tokens?: TokenStore } = {};
      const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
      const answers = [() => limited('1'), () => pair(3)];
      const bodies: unknown[] = [];
      const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
        const req = input as Request;
        if (req.url.endsWith('/auth/refresh')) {
          bodies.push(await req.clone().json());
          return answers.shift()!();
        }
        return req.headers.get('x-pleya-retry') === '1' ? json({ items: [] }) : expired();
      }) as unknown as FetchLike;
      const delay = async () => void persistent.setItem('pleya.refresh_token', 'R2');
      ref.tokens = new TokenStore(persistent, memoryStorage());
      const client = new PleyaClient({ baseUrl: BASE, tokens: ref.tokens, fetch: fetchImpl, delay });
      ref.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 0 });
      await client.libraries();
      expect(bodies).toEqual([{ refresh_token: 'R1' }, { refresh_token: 'R2' }]);
    });

    it('stopt met wachten als de gebruiker intussen afmeldt', async () => {
      let release = () => {};
      const { client, tokens, lost, bodies } = setup([() => limited('1'), () => pair(2)], {
        delay: () => new Promise<void>((resolve) => { release = resolve; })
      });
      const request = client.libraries().catch(() => null);
      await vi.waitFor(() => expect(bodies).toHaveLength(1));
      await client.signOut();
      release();
      await request;
      expect(bodies).toHaveLength(1);
      expect(lost).not.toHaveBeenCalled();
      expect(tokens.refreshToken).toBeNull();
    });

    it('voegt gelijktijdige aanvragen ook tijdens het wachten samen', async () => {
      const { client, bodies } = setup([() => limited('1'), () => pair(2)]);
      await Promise.all([client.libraries(), client.libraries(), client.libraries()]);
      expect(bodies).toHaveLength(2);
    });
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

  // Venster 1 verruimt het foutdomein (DEC-135 en DEC-136). De compatibiliteits-
  // toets daaronder rust op de aanname dat een onbekend domein hier generiek
  // afloopt in plaats van ergens op te takken. Dat is een aanname over deze code,
  // dus hij hoort hier gemeten te worden en niet alleen in het besluit te staan.
  it.each(['server.internal', 'settings.invalid_value'])(
    'behandelt %s als een gewone onbekende code en tekent geen authstoring',
    (code) => {
      const err = new ApiError({ code, message: 'x', status: 500, retryable: true });
      expect(describeError(err)).toContain(code);
      expect(err.isAuthFailure).toBe(false);
    }
  );
});

describe('artwork', () => {
  it('haalt de bytes op met een Authorization-header en geeft een blob terug', async () => {
    let auth: string | null = null;
    const fetchImpl = vi.fn(async (_input: RequestInfo | URL, init?: RequestInit) => {
      auth = new Headers(init?.headers).get('Authorization');
      // Een kale string als body, geen Blob. jsdom's Blob mist `stream()`, waar
      // undici's Response om vraagt (op macOS valt dat toevallig goed uit, op de
      // Linux-runner niet), en Response.blob() bouwt zelf een Blob uit de string,
      // zodat er geen Blob uit een ander realm dan de Response binnenkomt.
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

  it('zet ?width= alleen wanneer er een breedte is meegegeven', async () => {
    const urls: string[] = [];
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      urls.push(String(input));
      return new Response('b', { status: 200 });
    }) as unknown as FetchLike;

    const { client } = clientWith(fetchImpl);
    client.tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });
    await client.artworkBlob('art-1', undefined, 480);
    await client.artworkBlob('art-1');

    expect(urls).toEqual([`${BASE}/artwork/art-1?width=480`, `${BASE}/artwork/art-1`]);
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
  it('doet zonder remote geen aanroep, zoals op een server zonder capabilities.sessions', async () => {
    const fetchImpl = vi.fn() as unknown as FetchLike;
    const { client, tokens } = clientWith(fetchImpl, memoryStorage({ 'pleya.refresh_token': 'R1' }));
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await client.signOut();

    expect(fetchImpl).not.toHaveBeenCalled();
    expect(tokens.accessToken).toBeNull();
    expect(tokens.refreshToken).toBeNull();
  });

  it('trekt met remote eerst de eigen sessie in, met het accesstoken, en leegt dan de opslag', async () => {
    const seen: { url: string; method: string; auth: string | null }[] = [];
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const request = input as Request;
      seen.push({ url: request.url, method: request.method, auth: request.headers.get('Authorization') });
      return new Response(null, { status: 204 });
    }) as unknown as FetchLike;
    const { client, tokens } = clientWith(fetchImpl);
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await client.signOut({ remote: true });

    expect(seen).toEqual([{ url: `${BASE}/auth/logout`, method: 'POST', auth: 'Bearer A1' }]);
    expect(tokens.accessToken).toBeNull();
    expect(tokens.refreshToken).toBeNull();
  });

  it('verzilvert in cookiemodus eerst de cookie als het accesstoken verlopen is, anders blijft de sessie leven', async () => {
    const seen: { path: string; auth: string | null }[] = [];
    const tokens = new TokenStore(memoryStorage(), memoryStorage());
    const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: (async (input: RequestInfo | URL) => {
      const request = input as Request;
      const path = new URL(request.url).pathname.replace('/pleya/v1', '');
      seen.push({ path, auth: request.headers.get('Authorization') });
      if (path === '/info') return json({ capabilities: { cookie_auth: true } });
      if (path === '/auth/refresh') return json({ access_token: 'fresh-A', expires_in_ms: 900_000 });
      return new Response(null, { status: 204 });
    }) as FetchLike });
    await client.info();

    await client.signOut({ remote: true });

    expect(seen.slice(1)).toEqual([{ path: '/auth/refresh', auth: null }, { path: '/auth/logout', auth: 'Bearer fresh-A' }]);
    expect(tokens.accessToken).toBeNull();
  });

  it('meldt lokaal toch af als de server niet bereikbaar is', async () => {
    const fetchImpl = vi.fn(async () => {
      throw new TypeError('Failed to fetch');
    }) as unknown as FetchLike;
    const { client, tokens } = clientWith(fetchImpl);
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });

    await client.signOut({ remote: true });

    expect(tokens.accessToken).toBeNull();
    expect(tokens.refreshToken).toBeNull();
  });
});

describe('toestelvelden bij inloggen (DEC-164)', () => {
  async function loginBody(fields: Record<string, string>): Promise<Record<string, unknown>> {
    let body: Record<string, unknown> = {};
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      body = (await (input as Request).json()) as Record<string, unknown>;
      return json({ access_token: 'A', refresh_token: 'R', token_type: 'bearer', expires_in_ms: 900_000 });
    }) as unknown as FetchLike;
    const { client } = clientWith(fetchImpl);
    await client.login({ username: 'michel', password: 'geheim', ...fields });
    return body;
  }

  it('stuurt device_id en device_name mee als de aanroeper ze geeft', async () => {
    const body = await loginBody({ device_id: 'web-1', device_name: 'Safari op macOS' });
    expect(body).toEqual({
      username: 'michel',
      password: 'geheim',
      device_id: 'web-1',
      device_name: 'Safari op macOS'
    });
  });

  it('stuurt geen enkel device-veld zonder (negatieve controle)', async () => {
    const body = await loginBody({});
    expect(Object.keys(body).sort()).toEqual(['password', 'username']);
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

describe('account replacement during pending requests', () => {
  const pair = (name: string) => ({ access_token: name, refresh_token: 'refresh-' + name, expires_in_ms: 900000 });
  it.each([200, 401])('a late refresh (%s) cannot replace or clear the new account', async (status) => {
    let release!: (response: Response) => void;
    const lost = vi.fn();
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'refresh-A' }), memoryStorage());
    const client = new PleyaClient({ baseUrl: BASE, tokens, onSessionLost: lost,
      fetch: (async (input: RequestInfo | URL) => {
        const url = input instanceof Request ? input.url : String(input);
        if (url.endsWith('/auth/refresh')) return await new Promise(resolve => release = resolve);
        return json(pair('B'));
      }) as FetchLike });
    const pending = client.restore();
    await vi.waitFor(() => expect(release).toBeTypeOf('function'));
    await client.login({ username: 'B', password: 'canned' });
    release(status === 200 ? json(pair('A-late')) : json({ code: 'auth.token_invalid' }, 401));
    await pending;
    expect(tokens.accessToken).toBe('B');
    expect(lost).not.toHaveBeenCalled();
  });
  it('never retries an old 401 with the newly selected account', async () => {
    let release!: (response: Response) => void;
    const sent: string[] = [];
    const { client } = clientWith((async (input: RequestInfo | URL) => {
      const request = input as Request;
      if (request.url.endsWith('/auth/login')) return json(pair('B'));
      if (request.url.endsWith('/auth/refresh')) return json(pair('B-refreshed'));
      sent.push(request.headers.get('Authorization') ?? '');
      if (sent.length > 1) return json({ items: [] });
      return await new Promise(resolve => release = resolve);
    }) as FetchLike);
    client.tokens.set(pair('A'));
    const old = client.libraries();
    const rejected = expect(old).rejects.toBeInstanceOf(ApiError);
    await vi.waitFor(() => expect(release).toBeTypeOf('function'));
    await client.login({ username: 'B', password: 'canned' });
    release(json({ code: 'auth.token_invalid' }, 401));
    await rejected;
    expect(sent).toEqual(['Bearer A']);
    expect(client.tokens.accessToken).toBe('B');
  });
  it('a late logout cannot clear a newer successful login', async () => {
    let release!: (response: Response) => void;
    const { client } = clientWith((async (input: RequestInfo | URL) => {
      const url = input instanceof Request ? input.url : String(input);
      if (url.endsWith('/auth/logout')) return await new Promise(resolve => release = resolve);
      return json(pair('B'));
    }) as FetchLike);
    client.tokens.set(pair('A'));
    const pending = client.signOut({ remote: true });
    await vi.waitFor(() => expect(release).toBeTypeOf('function'));
    await client.login({ username: 'B', password: 'canned' });
    release(new Response(null, { status: 204 }));
    await pending;
    expect(client.tokens.accessToken).toBe('B');
  });
});

it('does not return an old successful response after account replacement', async () => {
  let release!: (response: Response) => void;
  const { client } = clientWith((async (input: RequestInfo | URL) => {
    const url = input instanceof Request ? input.url : String(input);
    if (url.endsWith('/auth/login')) return json({ access_token: 'B', refresh_token: 'RB', expires_in_ms: 900000 });
    return await new Promise(resolve => release = resolve);
  }) as FetchLike);
  client.tokens.set({ access_token: 'A', refresh_token: 'RA', expires_in_ms: 900000 });
  const old = client.libraries();
  const rejected = expect(old).rejects.toBeInstanceOf(TransportError);
  await vi.waitFor(() => expect(release).toBeTypeOf('function'));
  await client.login({ username: 'B', password: 'canned' });
  release(json({ items: [{ id: 'private-A', title: 'Only A', kind: 'movies', item_count: 1 }] }));
  await rejected;
});

describe('existing cookie-auth contract', () => {
  function cookieServer(supports = true, failing?: string, shared?: ReturnType<typeof stores>, onRefresh?: () => void) {
    const storage = shared ?? stores();
    const seen: { path: string; body: Record<string, unknown> | null; auth: string | null }[] = [];
    const client = new PleyaClient({ baseUrl: BASE, tokens: storage.tokens, fetch: (async (input: RequestInfo | URL) => {
      const request = input as Request;
      const path = new URL(request.url).pathname.replace('/pleya/v1', '');
      const raw = request.method === 'POST' ? await request.text() : '';
      const body = raw ? JSON.parse(raw) : null;
      seen.push({ path, body, auth: request.headers.get('Authorization') });
      if (path === failing) return json({ error: { code: 'server.unavailable', message: 'canned' } }, 503);
      if (path === '/info') return json({ capabilities: { cookie_auth: supports } });
      if (path === '/auth/logout') return new Response(null, { status: 204 });
      if (path === '/auth/refresh') onRefresh?.();
      if (path === '/auth/setup') return json({ access_token: 'setup-A', refresh_token: 'setup-R', expires_in_ms: 900000 });
      const cookie = body?.credential_mode === 'cookie';
      return json({ access_token: 'new-A', expires_in_ms: 900000, ...(cookie ? {} : { refresh_token: 'new-R' }) });
    }) as FetchLike });
    return { client, seen, ...storage };
  }
  it('does not sign back in with the cookie after a logout that failed', async () => {
    const { client, seen, tokens } = cookieServer(true, '/auth/logout');
    await client.info();
    await client.login({ username: 'owner', password: 'canned' });
    await client.signOut({ remote: true });
    expect(await client.restore()).toBe(false);
    expect(seen.some(request => request.path === '/auth/refresh')).toBe(false);
    await client.login({ username: 'owner', password: 'canned' });
    tokens.clear();
    expect(await client.restore()).toBe(true);
  });
  it('a tab whose account was replaced elsewhere stops instead of refreshing as the new account', async () => {
    const shared = stores();
    const tab = cookieServer(true, undefined, shared);
    await tab.client.info();
    await tab.client.login({ username: 'A', password: 'canned' });
    const other = cookieServer(true, undefined, { ...shared, tokens: new TokenStore(shared.persistent, memoryStorage()) });
    await other.client.info();
    await other.client.login({ username: 'B', password: 'canned' });
    tab.tokens.clear();
    expect(await tab.client.restore()).toBe(false);
    expect(tab.seen.some(request => request.path === '/auth/refresh')).toBe(false);
  });
  it('discards a refresh when the account changed while it was in flight', async () => {
    const shared = stores();
    const otherTab = new TokenStore(shared.persistent, memoryStorage());
    const tab = cookieServer(true, undefined, shared, () => otherTab.rotateEpoch());
    await tab.client.info();
    await tab.client.login({ username: 'A', password: 'canned' });
    tab.tokens.clear();
    expect(await tab.client.restore()).toBe(false);
    expect(tab.tokens.accessToken).toBeNull();
    await new Promise((resolve) => setTimeout(resolve, 5));
    expect(tab.seen.some(request => request.path === '/auth/logout')).toBe(false);
  });
  it('requests cookie login and restores without a JavaScript refresh credential', async () => {
    const { client, seen, tokens, persistent, session } = cookieServer();
    await client.info();
    await client.login({ username: 'owner', password: 'canned' });
    expect(seen.find(request => request.path === '/auth/login')?.body).toMatchObject({ credential_mode: 'cookie' });
    expect(tokens.accessToken).toBe('new-A');
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
    tokens.clear();
    expect(await client.restore()).toBe(true);
    expect(seen.find(request => request.path === '/auth/refresh')?.body).toEqual({ credential_mode: 'cookie' });
    expect(tokens.accessToken).toBe('new-A');
  });
  it('does not send credential_mode to an older server', async () => {
    const { client, seen, persistent } = cookieServer(false);
    await client.info(); await client.login({ username: 'owner', password: 'canned' });
    expect(seen.find(request => request.path === '/auth/login')?.body).not.toHaveProperty('credential_mode');
    expect(persistent.getItem('pleya.refresh_token')).toBe('new-R');
  });
  it('retains an existing legacy session until the next explicit login', async () => {
    const { client, seen, tokens, persistent, session } = cookieServer();
    tokens.set({ access_token: 'expired-A', refresh_token: 'legacy-R', expires_in_ms: 0 });
    await client.info();
    expect(await client.restore()).toBe(true);
    expect(seen.find(request => request.path === '/auth/refresh')?.body).toEqual({ refresh_token: 'legacy-R' });
    expect(persistent.getItem('pleya.refresh_token')).toBe('new-R');
    await client.login({ username: 'owner', password: 'canned' });
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
  });
  it('moves setup to a cookie session and retires the setup session first', async () => {
    const { client, seen, tokens, persistent, session } = cookieServer();
    await client.info();
    await client.setup({ setup_code: 'fixture', username: 'owner', password: 'canned', device_id: 'browser' });
    expect(seen.map(request => request.path)).toEqual(['/info', '/auth/setup', '/auth/logout', '/auth/login']);
    expect(seen[1]?.body).not.toHaveProperty('credential_mode');
    expect(seen[2]?.auth).toBe('Bearer setup-A');
    expect(seen[3]?.body).toEqual({ username: 'owner', password: 'canned', device_id: 'browser', credential_mode: 'cookie' });
    expect(tokens.accessToken).toBe('new-A');
    expect(tokens.refreshToken).toBeNull();
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
  });
  it('leaves no token behind when the cookie login after setup fails', async () => {
    const { client, tokens, persistent, session } = cookieServer(true, '/auth/login');
    await client.info();
    await client.setup({ setup_code: 'fixture', username: 'owner', password: 'canned' });
    expect(tokens.accessToken).toBeNull();
    expect(tokens.refreshToken).toBeNull();
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
  });
  it('still moves to the cookie when retiring the setup session fails', async () => {
    const { client, seen, tokens, persistent } = cookieServer(true, '/auth/logout');
    await client.info();
    await client.setup({ setup_code: 'fixture', username: 'owner', password: 'canned' });
    expect(seen.at(-1)?.path).toBe('/auth/login');
    expect(tokens.accessToken).toBe('new-A');
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
  });
  it('keeps the token pair of setup on a server without cookie_auth', async () => {
    const { client, seen, persistent } = cookieServer(false);
    await client.info();
    await client.setup({ setup_code: 'fixture', username: 'owner', password: 'canned' });
    expect(seen.map(request => request.path)).toEqual(['/info', '/auth/setup']);
    expect(persistent.getItem('pleya.refresh_token')).toBe('setup-R');
  });
});

it('recognizes public routes when the browser resolves a relative API base URL', async () => {
  const NativeRequest = globalThis.Request;
  class BrowserRequest extends NativeRequest {
    constructor(input: RequestInfo | URL, init?: RequestInit) {
      super(typeof input === 'string' ? new URL(input, 'http://relative.test') : input, init);
    }
  }
  vi.stubGlobal('Request', BrowserRequest);
  try {
    let auth: string | null = null;
    const tokens = stores().tokens;
    tokens.set({ access_token: 'canned-A', refresh_token: 'canned-R', expires_in_ms: 900000 });
    const client = new PleyaClient({ baseUrl: '/pleya/v1', tokens, fetch: (async (input: RequestInfo | URL) => {
      auth = (input as Request).headers.get('Authorization');
      return json({ capabilities: { cookie_auth: false } });
    }) as FetchLike });
    await client.info();
    expect(auth).toBeNull();
  } finally { vi.stubGlobal('Request', NativeRequest); }
});

it('a rejected cookie refresh never falls back to a JSON refresh credential', async () => {
  const bodies: unknown[] = [];
  const lost = vi.fn();
  const { tokens } = stores();
  const client = new PleyaClient({ baseUrl: BASE, tokens, onSessionLost: lost, fetch: (async (input: RequestInfo | URL) => {
    const request = input as Request;
    if (request.url.endsWith('/info')) return json({ capabilities: { cookie_auth: true } });
    bodies.push(await request.json());
    return json({ code: 'auth.token_invalid' }, 401);
  }) as FetchLike });
  await client.info();
  expect(await client.restore()).toBe(false);
  expect(bodies).toEqual([{ credential_mode: 'cookie' }]);
  expect(lost).toHaveBeenCalledTimes(1);
});

it('a failed explicit cookie login leaves the existing legacy credential intact', async () => {
  const { tokens, persistent } = stores('legacy-R');
  const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: (async (input: RequestInfo | URL) => {
    const request = input as Request;
    if (request.url.endsWith('/info')) return json({ capabilities: { cookie_auth: true } });
    return json({ code: 'auth.invalid_credentials' }, 401);
  }) as FetchLike });
  await client.info();
  await expect(client.login({ username: 'owner', password: 'wrong-canned' })).rejects.toBeInstanceOf(ApiError);
  expect(persistent.getItem('pleya.refresh_token')).toBe('legacy-R');
});

describe('existing catalog filter contract', () => {
  it('sends repeated filter values and the complete server sort without inventing query fields', async () => {
    let request: Request | undefined;
    const { client } = clientWith((async input => { request = input as Request; return json({ items: [] }); }) as FetchLike);
    await client.libraryItems('movies', { genre: ['Drama', 'Science fiction & fantasy'], year: ['2025'], watch: 'unwatched', resolution: ['fhd','uhd'], sort: '-last_played_at', limit: 24 });
    const params = new URL(request!.url).searchParams;
    expect(params.getAll('genre')).toEqual(['Drama','Science fiction & fantasy']);
    expect(params.getAll('resolution')).toEqual(['fhd','uhd']);
    expect(params.get('watch')).toBe('unwatched');
    expect(params.get('sort')).toBe('-last_played_at');
    expect(params.has('watched')).toBe(false);
  });
  it('loads library facets over the existing authenticated route without filter queries', async () => {
    let request: Request | undefined;
    const facets = { genres: [{value:'Drama',count:2}], years: [{value:'2025',count:1}], content_ratings: [], audio_languages: [], resolutions: [], watch: {unwatched:2,in_progress:0,watched:0} };
    const { client, tokens } = clientWith((async input => { request = input as Request; return json(facets); }) as FetchLike);
    tokens.set({access_token:'canned-A',refresh_token:'canned-R',expires_in_ms:900000});
    expect(await client.libraryFacets('movies')).toEqual(facets);
    expect(request!.url).toBe(`${BASE}/libraries/movies/facets`);
    expect(request!.headers.get('Authorization')).toBe('Bearer canned-A');
  });
});

/** Een server met één refreshketen, en twee tabbladen met dezelfde opslag. */
function refreshServer(start = 'R1') {
  let live = start;
  let counter = 1;
  const seen: Record<string, unknown>[] = [];
  let inFlight = 0;
  let overlap = false;
  const handler = async (request: Request, capabilities: Record<string, boolean>): Promise<Response> => {
    const path = new URL(request.url).pathname.replace('/pleya/v1', '');
    if (path === '/info') return json({ capabilities });
    if (path !== '/auth/refresh') return json({ items: [] });
    const body = (await request.json()) as Record<string, string>;
    seen.push(body);
    inFlight += 1;
    overlap = overlap || inFlight > 1;
    await new Promise((resolve) => setTimeout(resolve, 1));
    inFlight -= 1;
    if (body['credential_mode'] !== 'cookie' && body['refresh_token'] !== live) {
      return json({ error: { code: 'auth.refresh_token_reused', message: 'reused', retryable: false } }, 401);
    }
    counter += 1;
    live = `R${counter}`;
    return json({
      access_token: `A${counter}`, token_type: 'bearer', expires_in_ms: 900_000,
      ...(body['credential_mode']?.startsWith('cookie') ? {} : { refresh_token: live })
    });
  };
  return { seen, handler, overlapped: () => overlap };
}

/** Exclusief op naam, zoals `navigator.locks`: wie volgt wacht tot de callback klaar is. */
function memoryLocks() {
  let tail: Promise<unknown> = Promise.resolve();
  return {
    request<T>(_name: string, _options: { signal: AbortSignal }, callback: () => Promise<T>): Promise<T> {
      const run = tail.then(callback, callback);
      tail = run.catch(() => undefined);
      return run;
    }
  };
}

describe('verversen tussen tabbladen', () => {
  function tab(persistent: TokenStorage, server: ReturnType<typeof refreshServer>, capabilities: Record<string, boolean>,
    locks: ReturnType<typeof memoryLocks> | null, onSessionLost = vi.fn()) {
    const tokens = new TokenStore(persistent, memoryStorage());
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks, onSessionLost,
      fetch: ((input: RequestInfo | URL) => server.handler(input as Request, capabilities)) as FetchLike
    });
    return { client, tokens, onSessionLost };
  }

  it('laat twee tabbladen na elkaar verversen, en de tweede gebruikt het nieuwe token', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const server = refreshServer();
    const locks = memoryLocks();
    const first = tab(persistent, server, { cookie_auth: true }, locks);
    const second = tab(persistent, server, { cookie_auth: true }, locks);

    const results = await Promise.all([first.client.restore(), second.client.restore()]);

    expect(results).toEqual([true, true]);
    expect(server.overlapped()).toBe(false);
    expect(server.seen.map((body) => body['refresh_token'])).toEqual(['R1', 'R2']);
    expect(first.onSessionLost).not.toHaveBeenCalled();
    expect(second.onSessionLost).not.toHaveBeenCalled();
    expect(new Set([first.tokens.accessToken, second.tokens.accessToken]).size).toBe(2);
  });

  it('werkt zonder navigator.locks zoals eerst: zonder slot lopen de aanvragen door elkaar', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const server = refreshServer();
    const only = tab(persistent, server, { cookie_auth: true }, null);
    await expect(only.client.restore()).resolves.toBe(true);
    expect(server.seen).toEqual([{ refresh_token: 'R1' }]);

    const raced = refreshServer();
    const shared = memoryStorage({ 'pleya.refresh_token': 'R1' });
    await Promise.all([tab(shared, raced, {}, null).client.restore(), tab(shared, raced, {}, null).client.restore()]);
    expect(raced.overlapped()).toBe(true);
  });

  it('houdt het slot niet vast tijdens het wachten op een 429', async () => {
    let held = false;
    let heldDuringDelay = false;
    const locks = {
      async request<T>(_name: string, _options: { signal: AbortSignal }, callback: () => Promise<T>): Promise<T> {
        held = true;
        try {
          return await callback();
        } finally {
          held = false;
        }
      }
    };
    const answers = [
      () => json({ error: { code: 'auth.rate_limited', message: 'wacht', retryable: true, details: { retry_after_ms: 10 } } }, 429),
      () => json({ access_token: 'A2', refresh_token: 'R2', token_type: 'bearer', expires_in_ms: 900_000 })
    ];
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks,
      delay: async () => { heldDuringDelay = held; },
      fetch: (async () => answers.shift()!()) as FetchLike
    });
    await expect(client.restore()).resolves.toBe(true);
    expect(heldDuringDelay).toBe(false);
  });

  /** Een slot dat een ander tabblad nooit teruggeeft; alleen het signaal komt er nog doorheen. */
  const stuckLocks = {
    request<T>(_name: string, options: { signal: AbortSignal }): Promise<T> {
      return new Promise((_, reject) => {
        options.signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
      });
    }
  };

  it('ververst zelf als een ander tabblad het slot niet teruggeeft', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const server = refreshServer();
    const tokens = new TokenStore(persistent, memoryStorage());
    const onSessionLost = vi.fn();
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks: stuckLocks, onSessionLost, refreshTimeoutMs: 5,
      fetch: ((input: RequestInfo | URL) => server.handler(input as Request, {})) as FetchLike
    });

    await expect(client.restore()).resolves.toBe(true);

    expect(server.seen).toEqual([{ refresh_token: 'R1' }]);
    expect(tokens.accessToken).toBe('A2');
    expect(onSessionLost).not.toHaveBeenCalled();
  });

  it('een slot dat weigert houdt het verversen niet tegen', async () => {
    const server = refreshServer();
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
    const client = new PleyaClient({
      baseUrl: BASE, tokens,
      locks: { request: async () => { throw new DOMException('Denied', 'SecurityError'); } },
      fetch: ((input: RequestInfo | URL) => server.handler(input as Request, {})) as FetchLike
    });

    await expect(client.restore()).resolves.toBe(true);
    expect(server.seen).toHaveLength(1);
  });

  it('stuurt een aanvraag die onder het slot mislukte niet nog eens zonder slot', async () => {
    const send = vi.fn(async () => { throw new TypeError('Failed to fetch'); });
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
    const client = new PleyaClient({ baseUrl: BASE, tokens, locks: memoryLocks(), fetch: send as unknown as FetchLike });

    await expect(client.restore()).resolves.toBe(false);

    expect(send).toHaveBeenCalledTimes(1);
    expect(client.refreshUnavailable).toBe(true);
  });

  it('de opstart hangt niet aan een verversing die nooit antwoord krijgt', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const tokens = new TokenStore(persistent, memoryStorage());
    const onSessionLost = vi.fn();
    const silent = (input: RequestInfo | URL) => new Promise<Response>((_, reject) => {
      const { signal } = input as Request;
      signal.addEventListener('abort', () => reject(new DOMException('Aborted', 'AbortError')));
    });
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks: memoryLocks(), onSessionLost, refreshTimeoutMs: 5, fetch: silent as FetchLike
    });

    await expect(client.restore()).resolves.toBe(false);

    expect(client.refreshUnavailable).toBe(true);
    expect(onSessionLost).not.toHaveBeenCalled();
    expect(persistent.getItem('pleya.refresh_token')).toBe('R1');
  });
});

describe('een oude websessie stapt over op de cookie', () => {
  const capabilities = { cookie_auth: true, cookie_upgrade: true };
  function tab(persistent: TokenStorage, server: ReturnType<typeof refreshServer>, onSessionLost = vi.fn(), caps = capabilities, session = memoryStorage()) {
    const tokens = new TokenStore(persistent, session);
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks: null, onSessionLost,
      fetch: ((input: RequestInfo | URL) => server.handler(input as Request, caps)) as FetchLike
    });
    return { client, tokens, onSessionLost };
  }

  it('ruilt het token in, wist het en ververst daarna met de cookie', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1', 'pleya.session_epoch': 'e1' });
    const server = refreshServer();
    const session = memoryStorage();
    const { client, tokens } = tab(persistent, server, vi.fn(), capabilities, session);
    await client.info();

    await expect(client.restore()).resolves.toBe(true);
    expect(server.seen).toEqual([{ refresh_token: 'R1', credential_mode: 'cookie_upgrade' }]);
    expect(persistent.getItem('pleya.refresh_token')).toBeNull();
    expect(session.getItem('pleya.access_token')).toBeNull();
    expect(tokens.accessToken).toBe('A2');
    expect(tokens.epoch).toBe('e1');

    tokens.set({ access_token: 'verlopen', expires_in_ms: 0 });
    await expect(client.bearer()).resolves.toBe('A3');
    expect(server.seen[1]).toEqual({ credential_mode: 'cookie' });
  });

  it('blijft op het token als de server de overstap niet kent', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const server = refreshServer();
    const { client } = tab(persistent, server, vi.fn(), { cookie_auth: true, cookie_upgrade: false });
    await client.info();
    await client.restore();
    expect(server.seen).toEqual([{ refresh_token: 'R1' }]);
    expect(persistent.getItem('pleya.refresh_token')).toBe('R2');
  });

  it('een tabblad dat achterbleef volgt de cookie in plaats van zijn sessie te verliezen', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1', 'pleya.session_epoch': 'e1' });
    const server = refreshServer();
    const ahead = tab(persistent, server);
    const behind = tab(persistent, server);
    await ahead.client.info();
    await behind.client.info();

    await ahead.client.restore();
    await expect(behind.client.bearer()).resolves.toBe('A3');

    expect(server.seen[1]).toEqual({ credential_mode: 'cookie' });
    expect(behind.onSessionLost).not.toHaveBeenCalled();
  });

  it('een uitlog in een ander tabblad blijft een uitlog', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1', 'pleya.session_epoch': 'e1' });
    const server = refreshServer();
    const here = tab(persistent, server);
    await here.client.info();
    persistent.removeItem('pleya.refresh_token');
    persistent.setItem('pleya.session_epoch', 'e2');

    await expect(here.client.bearer()).resolves.toBeNull();
    expect(server.seen).toEqual([]);
  });

  /** De overstap blijft onderweg tot `answer()`, en logout gaat zoals `logout` zegt. */
  function pendingUpgrade(persistent: TokenStorage, logout: () => Promise<Response>) {
    const seen: { path: string; auth: string | null }[] = [];
    let answer = () => {};
    const answered = new Promise<void>((resolve) => { answer = resolve; });
    const tokens = new TokenStore(persistent, memoryStorage());
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks: null,
      fetch: (async (input: RequestInfo | URL) => {
        const request = input as Request;
        const path = new URL(request.url).pathname.replace('/pleya/v1', '');
        if (path === '/info') return json({ capabilities });
        if (path === '/users/me') return new Response(null, { status: 401 });
        seen.push({ path, auth: request.headers.get('Authorization') });
        if (path === '/auth/logout') return logout();
        await answered;
        return json({ access_token: 'A2', token_type: 'bearer', expires_in_ms: 900_000 });
      }) as FetchLike
    });
    return { client, tokens, seen, answer };
  }

  it('afmelden tijdens de overstap sluit de sessie die de cookie nog kreeg', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const { client, seen, answer } = pendingUpgrade(persistent, async () => new Response(null, { status: 204 }));
    await client.info();
    const restoring = client.restore();
    await vi.waitFor(() => expect(seen).toHaveLength(1));

    await client.signOut({ remote: true });
    answer();
    await expect(restoring).resolves.toBe(false);

    await vi.waitFor(() => expect(seen[1]).toEqual({ path: '/auth/logout', auth: 'Bearer A2' }));
  });

  it('afmelden in een ander tabblad tijdens de overstap sluit de sessie die de cookie nog kreeg', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const { client, seen, answer } = pendingUpgrade(persistent, async () => new Response(null, { status: 204 }));
    const other = tab(persistent, refreshServer());
    await client.info();
    await other.client.info();
    const restoring = client.restore();
    await vi.waitFor(() => expect(seen).toHaveLength(1));

    await other.client.signOut({ remote: true });
    answer();
    await expect(restoring).resolves.toBe(false);

    await vi.waitFor(() => expect(seen[1]).toEqual({ path: '/auth/logout', auth: 'Bearer A2' }));
  });

  it('een accesstoken van vóór de overstap houdt die afmelding niet tegen', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const { client, tokens, seen, answer } = pendingUpgrade(persistent, async () => new Response(null, { status: 204 }));
    const other = tab(persistent, refreshServer());
    await client.info();
    await other.client.info();
    tokens.set({ access_token: 'A1', refresh_token: 'R1', expires_in_ms: 900_000 });
    const asking = client.me().catch(() => undefined);
    await vi.waitFor(() => expect(seen).toHaveLength(1));

    await other.client.signOut({ remote: true });
    answer();
    await asking;

    await vi.waitFor(() => expect(seen[1]).toEqual({ path: '/auth/logout', auth: 'Bearer A2' }));
    expect(tokens.accessToken).toBeNull();
  });

  it('ook als die afmelding niet aankomt, logt een herlaadbeurt niet stil weer in', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const { client, seen, answer } = pendingUpgrade(persistent, async () => { throw new TypeError('Failed to fetch'); });
    await client.info();
    const restoring = client.restore();
    await vi.waitFor(() => expect(seen).toHaveLength(1));
    await client.signOut({ remote: true });
    answer();
    await restoring;
    await vi.waitFor(() => expect(seen).toHaveLength(2));

    const server = refreshServer();
    const reloaded = tab(persistent, server);
    await reloaded.client.info();
    await expect(reloaded.client.restore()).resolves.toBe(false);
    expect(server.seen).toEqual([]);
  });

  it('een nieuwe login tijdens de overstap wordt niet afgemeld door het late antwoord', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const { client, tokens, seen, answer } = pendingUpgrade(persistent, async () => new Response(null, { status: 204 }));
    await client.info();
    const restoring = client.restore();
    await vi.waitFor(() => expect(seen).toHaveLength(1));
    await client.signOut();
    tokens.set({ access_token: 'nieuwe-login', expires_in_ms: 900_000 });

    answer();
    await restoring;
    await new Promise((resolve) => setTimeout(resolve, 5));

    expect(seen.map((call) => call.path)).toEqual(['/auth/refresh']);
  });

  it('een overstap die mislukte telt niet meer mee bij afmelden', async () => {
    const tokens = new TokenStore(memoryStorage({ 'pleya.refresh_token': 'R1' }), memoryStorage());
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks: null,
      fetch: (async (input: RequestInfo | URL) => (input as Request).url.endsWith('/info')
        ? json({ capabilities })
        : json({ error: { code: 'server.internal', message: 'stuk', retryable: true } }, 503)) as FetchLike
    });
    await client.info();
    await expect(client.restore()).resolves.toBe(false);

    await client.signOut();

    expect(tokens.signedOut).toBe(false);
  });

  it('afmelden zonder overstap onderweg zet geen marker, in tokenmodus is er niets te bewaken', async () => {
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const { client, tokens } = pendingUpgrade(persistent, async () => new Response(null, { status: 204 }));
    await client.signOut();
    expect(tokens.signedOut).toBe(false);
  });

  it('valt terug op het token als deze origin geen cookie mag: de sessie werkte al zonder', async () => {
    const seen: Record<string, unknown>[] = [];
    const persistent = memoryStorage({ 'pleya.refresh_token': 'R1' });
    const tokens = new TokenStore(persistent, memoryStorage());
    const onSessionLost = vi.fn();
    const client = new PleyaClient({
      baseUrl: BASE, tokens, locks: null, onSessionLost, delay: async () => undefined,
      fetch: (async (input: RequestInfo | URL) => {
        const request = input as Request;
        if (request.url.endsWith('/info')) return json({ capabilities });
        const body = (await request.json()) as Record<string, unknown>;
        seen.push(body);
        if (body['credential_mode']) return json({ error: { code: 'auth.origin_rejected', message: 'nee', retryable: false } }, 403);
        return json({ access_token: 'A2', refresh_token: 'R2', token_type: 'bearer', expires_in_ms: 900_000 });
      }) as FetchLike
    });
    await client.info();

    await expect(client.restore()).resolves.toBe(true);
    expect(seen).toEqual([{ refresh_token: 'R1', credential_mode: 'cookie_upgrade' }, { refresh_token: 'R1' }]);
    expect(persistent.getItem('pleya.refresh_token')).toBe('R2');
    expect(client.refreshRefused).toBeNull();
    expect(onSessionLost).not.toHaveBeenCalled();

    tokens.set({ access_token: 'verlopen', refresh_token: 'R2', expires_in_ms: 0 });
    await client.bearer();
    expect(seen[2]).toEqual({ refresh_token: 'R2' });
  });
});
