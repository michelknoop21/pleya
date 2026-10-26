/**
 * De aanvragen buiten openapi-fetch om: stoppen met keepalive, de bearer voor
 * hls.js, en de ondertitel. Het accesstoken hoort in een header en nergens in
 * een URL.
 */
import { describe, expect, it, vi } from 'vitest';

import { PleyaClient, type FetchLike } from '../api/client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import { playbackApi } from './playbackApi';

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
