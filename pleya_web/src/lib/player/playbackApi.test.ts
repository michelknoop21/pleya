/**
 * De aanvragen buiten openapi-fetch om: stoppen met keepalive, de bearer voor
 * hls.js, en de ondertitel. Het accesstoken hoort in een header en nergens in
 * een URL.
 */
import { describe, expect, it, vi } from 'vitest';

import { PleyaClient, type FetchLike } from '../api/client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import { playbackApi } from './playbackApi';
import { SubtitleNotReadyError } from './subtitleRetry';

function memory(initial: Record<string, string> = {}): TokenStorage {
  const map = new Map(Object.entries(initial));
  return {
    getItem: (k) => map.get(k) ?? null,
    setItem: (k, v) => void map.set(k, v),
    removeItem: (k) => void map.delete(k)
  };
}

const BASE = 'http://server.test/pleya/v1';

function setup(fetchImpl = vi.fn(async (_u: string, _i?: RequestInit) => new Response(null, { status: 204 }))) {
  const tokens = new TokenStore(memory({ 'pleya.refresh_token': 'ververs' }), memory());
  tokens.set({ access_token: 'geheim-1', refresh_token: 'ververs', expires_in_ms: 600_000 });
  const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl as unknown as FetchLike });
  return { api: playbackApi(client, fetchImpl), fetchImpl, tokens, client };
}

describe('playbackApi buiten openapi-fetch', () => {
  it('stopt een sessie met DELETE, keepalive en de bearer in de header', () => {
    const { api, fetchImpl } = setup();
    api.stop('sess 1', true);
    const [url, init] = fetchImpl.mock.calls[0]!;
    expect(url).toBe(`${BASE}/playback/sessions/sess%201`);
    expect(url).not.toContain('geheim-1');
    expect(init?.method).toBe('DELETE');
    expect(init?.keepalive).toBe(true);
    expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer geheim-1');
  });

  it('haalt een ondertitel op met de bearer in de header', async () => {
    const fetchImpl = vi.fn(async (_u: string, _i?: RequestInit) => new Response('WEBVTT\n', { status: 200 }));
    const { api } = setup(fetchImpl);
    expect(await api.subtitleText('sub-1')).toBe('WEBVTT\n');
    const [url, init] = fetchImpl.mock.calls[0]!;
    expect(url).toBe(`${BASE}/subtitles/sub-1`);
    expect(new Headers(init?.headers).get('Authorization')).toBe('Bearer geheim-1');
  });

  it('maakt van 503 een herhaalbare fout met de Retry-After van de server', async () => {
    const fetchImpl = vi.fn(async () => new Response('{}', { status: 503, headers: { 'Retry-After': '7' } }));
    const { api } = setup(fetchImpl);
    const error = await api.subtitleText('sub-1').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(SubtitleNotReadyError);
    expect((error as SubtitleNotReadyError).retryAfterMs).toBe(7000);
  });

  it.each([401, 404, 502])('herhaalt %i niet', async (status) => {
    const { api } = setup(vi.fn(async () => new Response('{}', { status })));
    const error = await api.subtitleText('sub-1').catch((e: unknown) => e);
    expect(error).toBeInstanceOf(Error);
    expect(error).not.toBeInstanceOf(SubtitleNotReadyError);
  });

  it('ververst een verlopen accesstoken voor hls.js', async () => {
    const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
      const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
      if (url.endsWith('/auth/refresh')) {
        return new Response(
          JSON.stringify({ access_token: 'geheim-2', refresh_token: 'ververs-2', expires_in_ms: 600_000 }),
          { status: 200, headers: { 'content-type': 'application/json' } }
        );
      }
      return new Response(null, { status: 204 });
    });
    const tokens = new TokenStore(memory({ 'pleya.refresh_token': 'ververs' }), memory());
    const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: fetchImpl as unknown as FetchLike });
    expect(await playbackApi(client).bearer()).toBe('geheim-2');
  });

  it('geeft geen bearer zonder sessie (negatieve controle)', async () => {
    const tokens = new TokenStore(memory(), memory());
    const client = new PleyaClient({ baseUrl: BASE, tokens, fetch: vi.fn() as unknown as FetchLike });
    expect(await client.bearer()).toBeNull();
  });
});

describe('watch-state transport', () => {
  const body = { item_id: 'item', session_id: 'viewing', position_ms: 7000,
    occurred_at: '2026-10-29T12:00:00Z', completed: false, explicit_action: 'none' as const,
    base_revision: 3, backlog: false };
  it('starts the pagehide POST with keepalive and a header, without query credentials', async () => {
    const state = { position_ms: 7000, watched: false, play_count: 0, updated_at: '2026-10-29T12:00:00Z', revision: 4 };
    const fetchImpl = vi.fn(async () => new Response(JSON.stringify(state), { status: 200, headers: { 'Content-Type': 'application/json' } }));
    const { api } = setup(fetchImpl);
    const pending = api.reportWatchState(body, true);
    expect(fetchImpl).toHaveBeenCalledTimes(1);
    const [url, init] = vi.mocked(fetchImpl).mock.calls[0] as unknown as [string, RequestInit];
    expect(url).toBe(`${BASE}/watch-state`);
    expect(init).toMatchObject({ method: 'POST', keepalive: true });
    expect(new Headers(init.headers).get('Authorization')).toBe('Bearer geheim-1');
    expect(JSON.parse(init.body as string)).toEqual(body);
    expect(await pending).toEqual(state);
  });
  it('does not send after the account has been cleared', async () => {
    const { api, fetchImpl, tokens } = setup();
    tokens.clear();
    await expect(api.reportWatchState(body, true)).rejects.toThrow('No active playback account');
    expect(fetchImpl).not.toHaveBeenCalled();
  });
});

it('a viewing API cannot write after another account logs in', async () => {
  const pair = { access_token: 'account-B', refresh_token: 'refresh-B', expires_in_ms: 900000 };
  const fetchImpl = vi.fn(async () => new Response(JSON.stringify(pair), { status: 200, headers: { 'Content-Type': 'application/json' } }));
  const { api, client } = setup(fetchImpl);
  await client.login({ username: 'B', password: 'canned' });
  fetchImpl.mockClear();
  await expect(api.reportWatchState({ item_id: 'item', session_id: 'viewing-A', position_ms: 1,
    occurred_at: '2026-10-29T12:00:00Z', completed: false, explicit_action: 'none' }, true)).rejects.toThrow();
  expect(fetchImpl).not.toHaveBeenCalled();
});

it('a refreshed authenticated POST replays the original unconsumed body', async () => {
  const seen: unknown[] = [];
  const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
    const request = input as Request;
    if (request.url.endsWith('/auth/refresh')) return new Response(JSON.stringify({ access_token: 'fresh-A', refresh_token: 'refresh-fresh-A', expires_in_ms: 900000 }), { headers: { 'Content-Type': 'application/json' } });
    seen.push(await request.json());
    if (seen.length === 1) return new Response(JSON.stringify({ code: 'auth.token_expired' }), { status: 401, headers: { 'Content-Type': 'application/json' } });
    return new Response(JSON.stringify({ position_ms: 1, watched: false, play_count: 0, updated_at: '2026-10-29T12:00:00Z', revision: 4 }), { headers: { 'Content-Type': 'application/json' } });
  });
  const { api } = setup(fetchImpl as never);
  const body = { item_id: 'item', session_id: 'viewing', position_ms: 1, occurred_at: '2026-10-29T12:00:00Z', completed: false, explicit_action: 'none' as const, backlog: false };
  await api.reportWatchState(body);
  expect(seen).toEqual([body, body]);
});

it('drops a subtitle that arrives after the account changed', async () => {
  const fetchImpl = vi.fn(async (input: RequestInfo | URL) => {
    const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
    if (url.endsWith('/subtitles/s1')) {
      await client.login({ username: 'B', password: 'canned' });
      return new Response('WEBVTT\n');
    }
    return new Response(JSON.stringify({ access_token: 'B', refresh_token: 'refresh-B', expires_in_ms: 900000 }), { headers: { 'Content-Type': 'application/json' } });
  });
  const { api, client } = setup(fetchImpl);
  await expect(api.subtitleText('s1')).rejects.toThrow('Playback account changed');
});

it('all old viewing operations refuse after account replacement', async () => {
  const fetchImpl = vi.fn(async () => new Response(JSON.stringify({ access_token: 'B', refresh_token: 'refresh-B', expires_in_ms: 900000 }), { headers: { 'Content-Type': 'application/json' } }));
  const { api, client } = setup(fetchImpl);
  await client.login({ username: 'B', password: 'canned' });
  fetchImpl.mockClear();
  await expect(api.bearer()).rejects.toThrow('Playback account changed');
  await expect(api.streamSession('v1')).rejects.toThrow('Playback account changed');
  await expect(api.subtitleText('s1')).rejects.toThrow('Playback account changed');
  api.stop('old-A', false);
  expect(fetchImpl).not.toHaveBeenCalled();
});
