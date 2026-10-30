import { afterEach, beforeEach, describe, expect, it, vi } from 'vitest';

import { SessionState } from './session.svelte';
import { streamSessions } from '../player/streamSessionCache';
import { LAST_CONTACT_KEY, readLastContact } from './lastContact';
import { PleyaClient, type FetchLike } from '../api/client';
import { TransportError } from '../api/errors';
import { TokenStore } from '../auth/tokens';

/** Alleen wat `start()` en `load()` aanraken; de rest van de client doet hier niet mee. */
function fakeClient(overrides: Partial<Record<string, unknown>> = {}): PleyaClient {
  return {
    info: vi.fn(async () => ({
      auth: { setup_required: false },
      capabilities: { browse: true, search: true }
    })),
    restore: vi.fn(async () => true),
    server: vi.fn(async () => ({ name: 'Pleya-server' })),
    libraries: vi.fn(async () => [
      { id: 'lib-1', kind: 'movies', name: 'Films' },
      { id: 'lib-2', kind: 'books', name: 'Boeken' }
    ]),
    ...overrides
  } as unknown as PleyaClient;
}

// Node 26 zet een eigen, lege `localStorage` op de globale scope die die van
// jsdom overschaduwt; dezelfde eigen opslag als in LanguagePicker.test.ts.
function memoryStorage(): Storage {
  const data = new Map<string, string>();
  return {
    get length() {
      return data.size;
    },
    key: (index: number) => [...data.keys()][index] ?? null,
    getItem: (key: string) => data.get(key) ?? null,
    setItem: (key: string, value: string) => void data.set(key, String(value)),
    removeItem: (key: string) => void data.delete(key),
    clear: () => data.clear()
  };
}

beforeEach(() => {
  vi.stubGlobal('localStorage', memoryStorage());
});

afterEach(() => {
  vi.unstubAllGlobals();
});

describe('laatste contact', () => {
  it('load() bewaart naam, tijdstip, browse en de bibliotheekverwijzingen', async () => {
    const session = new SessionState(fakeClient());
    await session.start();

    expect(session.phase).toBe('ready');
    const record = readLastContact();
    expect(record).toMatchObject({
      name: 'Pleya-server',
      browse: true,
      libraries: [
        { id: 'lib-1', kind: 'movies' },
        { id: 'lib-2', kind: 'books' }
      ]
    });
    expect(Date.now() - Date.parse(record!.at)).toBeLessThan(5_000);
    // Alleen verwijzingen, geen titels: het record is geen kopie van de catalogus.
    expect(JSON.parse(localStorage.getItem(LAST_CONTACT_KEY)!).libraries[0]).not.toHaveProperty('name');
  });

  it('een opslag die gooit breekt load() niet', async () => {
    vi.spyOn(localStorage, 'setItem').mockImplementation(() => {
      throw new DOMException('quota', 'QuotaExceededError');
    });
    const session = new SessionState(fakeClient());
    await session.start();
    expect(session.phase).toBe('ready');
    expect(session.libraries).toHaveLength(2);
  });

  it('onbereikbaar leest het record; zonder record blijft het null', async () => {
    const down = fakeClient({
      info: vi.fn(async () => {
        throw new TransportError(new TypeError('Failed to fetch'));
      })
    });
    const without = new SessionState(down);
    await without.start();
    expect(without.phase).toBe('unreachable');
    expect(without.lastContact).toBeNull();

    await new SessionState(fakeClient()).start();
    const withRecord = new SessionState(down);
    await withRecord.start();
    expect(withRecord.lastContact?.name).toBe('Pleya-server');
  });

  it('een nieuwe poging blijft in onbereikbaar tot er een antwoord is', async () => {
    let answer: () => void = () => undefined;
    let calls = 0;
    const client = fakeClient({
      info: vi.fn(() => {
        calls += 1;
        if (calls === 1) return Promise.reject(new TransportError(new TypeError('down')));
        return new Promise((resolve) => {
          answer = () => resolve({ auth: { setup_required: false }, capabilities: { browse: true } });
        });
      })
    });
    const session = new SessionState(client);
    await session.start();
    expect(session.phase).toBe('unreachable');

    const retry = session.start();
    // Via `starting` zou de schil met de staat erin even verdwijnen.
    expect(session.phase).toBe('unreachable');
    answer();
    await retry;
    expect(session.phase).toBe('ready');
  });
});

describe('een begrensde verversing (S15.1)', () => {
  it('is geen uitloggen bij het opstarten', async () => {
    const state = new SessionState(fakeClient({ restore: vi.fn(async () => false), refreshUnavailable: true }));
    await state.start();
    expect(state.phase).toBe('unreachable');
  });

  it('is geen uitloggen bij het laden', async () => {
    const state = new SessionState(fakeClient({
      server: vi.fn(async () => { throw new TransportError(new Error('401')); }),
      refreshUnavailable: true
    }));
    await state.start();
    expect(state.phase).toBe('unreachable');
  });

  it('laat een echte afwijzing wel uitloggen (negatieve controle)', async () => {
    const state = new SessionState(fakeClient({ restore: vi.fn(async () => false), refreshUnavailable: false }));
    await state.start();
    expect(state.phase).toBe('signed-out');
  });
});

describe('een storing op de verversing, met de echte client', () => {
  function clientWith(answer: () => Response) {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const url = (input as Request).url;
      if (url.endsWith('/info')) {
        return new Response(JSON.stringify({ auth: { setup_required: false }, capabilities: { browse: true } }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' }
        });
      }
      return answer();
    }) as unknown as FetchLike;
    const stored = memoryStorage();
    stored.setItem('pleya.refresh_token', 'R1');
    return new PleyaClient({ baseUrl: 'http://server.test/pleya/v1', tokens: new TokenStore(stored, memoryStorage()), fetch: fetchImpl });
  }

  it.each([
    ['een 503', () => new Response(null, { status: 503 })],
    ['een netwerkfout', () => { throw new TypeError('failed to fetch'); }]
  ])('%s bij het opstarten is onbereikbaar en geen inlogscherm', async (_name, answer) => {
    const client = clientWith(answer);
    const state = new SessionState(client);
    await state.start();
    expect(state.phase).toBe('unreachable');
    expect(client.tokens.refreshToken).toBe('R1');
  });

  it('een afgewezen token geeft wel het inlogscherm (negatieve controle)', async () => {
    const rejected = new Response(JSON.stringify({ error: { code: 'auth.token_invalid', message: 'x', retryable: false } }), {
      status: 401,
      headers: { 'Content-Type': 'application/json' }
    });
    const client = clientWith(() => rejected);
    const state = new SessionState(client);
    await state.start();
    expect(state.phase).toBe('signed-out');
    expect(client.tokens.refreshToken).toBeNull();
  });
});

describe('afmelden (DEC-164)', () => {
  async function started(capabilities: Record<string, boolean>) {
    const signOut = vi.fn(async () => {});
    const state = new SessionState(
      fakeClient({
        info: vi.fn(async () => ({ auth: { setup_required: false }, capabilities })),
        signOut
      })
    );
    await state.start();
    return { state, signOut };
  }

  it('trekt de sessie op de server in als die capabilities.sessions heeft', async () => {
    const { state, signOut } = await started({ browse: true, sessions: true });
    await state.signOut();
    expect(signOut).toHaveBeenCalledWith({ remote: true });
    expect(state.phase).toBe('signed-out');
  });

  it('blijft lokaal zonder de vlag (negatieve controle)', async () => {
    const { state, signOut } = await started({ browse: true });
    await state.signOut();
    expect(signOut).toHaveBeenCalledWith({ remote: false });
  });

  it('blijft lokaal na een geroteerde sleutel, ook met de vlag', async () => {
    const { state, signOut } = await started({ browse: true, sessions: true });
    await state.signOut({ local: true });
    expect(signOut).toHaveBeenCalledWith({ remote: false });
  });
});

it('explicit authentication clears media IDs retained from a previous account', async () => {
  const future = new Date(Date.now() + 600000).toISOString();
  await streamSessions.get('same-version', async () => ({ stream_session_id: 'account-A', expires_at: future }));
  const session = new SessionState(fakeClient());
  await session.afterAuth();
  const fresh = vi.fn(async () => ({ stream_session_id: 'account-B', expires_at: future }));
  expect(await streamSessions.get('same-version', fresh)).toBe('account-B');
  expect(fresh).toHaveBeenCalledTimes(1);
});

it.each(['success', 'failure'])('a stale account load (%s) cannot replace the newer session state', async (result) => {
  let resolve!: (value: unknown) => void;
  let reject!: (error: Error) => void;
  const client = fakeClient({ sessionGeneration: 0,
    server: () => new Promise((yes, no) => { resolve = yes; reject = no; }) });
  const session = new SessionState(client);
  const old = session.load();
  Object.assign(client, { sessionGeneration: 1, server: async () => ({ name: 'Server B' }) });
  await session.load();
  if (result === 'success') resolve({ name: 'Server A' }); else reject(new Error('Old account failed'));
  await old;
  expect(session.server?.name).toBe('Server B');
  expect(session.phase).toBe('ready');
});

it('late signout completion cannot hide the newly authenticated account', async () => {
  let release!: () => void;
  const client = fakeClient({ sessionGeneration: 0,
    signOut: () => { Object.assign(client, { sessionGeneration: 1 }); return new Promise<void>(resolve => release = resolve); } });
  const session = new SessionState(client);
  const old = session.signOut();
  Object.assign(client, { sessionGeneration: 2, server: async () => ({ name: 'Server B' }) });
  await session.load();
  release(); await old;
  expect(session.server?.name).toBe('Server B');
  expect(session.phase).toBe('ready');
});
