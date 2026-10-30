import { describe, expect, it, vi } from 'vitest';
import { PleyaClient, type FetchLike } from './client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import { knownVisibility, listsApi, nextInList } from './lists';

function storage(): TokenStorage {
  const data = new Map<string, string>();
  return { getItem: (key) => data.get(key) ?? null, setItem: (key, value) => void data.set(key, value), removeItem: (key) => void data.delete(key) };
}
const json = (value: unknown) => new Response(JSON.stringify(value), { headers: { 'Content-Type': 'application/json' } });

function setup(pages: unknown[] = []) {
  const requests: Request[] = [];
  const fetch = vi.fn(async (input: RequestInfo | URL) => {
    const request = input instanceof Request ? input : new Request(input);
    requests.push(request);
    if (request.url.endsWith('/auth/login')) return json({ access_token: 'test-account-B', refresh_token: 'test-refresh-B', expires_in_ms: 600000 });
    if (request.method === 'GET') return json(pages.shift() ?? { items: [], next_cursor: null });
    return new Response(null, { status: 204 });
  });
  const tokens = new TokenStore(storage(), storage());
  tokens.set({ access_token: 'test-account-A', refresh_token: 'test-refresh-A', expires_in_ms: 600000 });
  const client = new PleyaClient({ baseUrl: 'http://server.test/pleya/v1', tokens, fetch: fetch as unknown as FetchLike });
  return { client, api: listsApi(client), requests };
}

describe('lists API', () => {
  it('sends the full list on PUT and one id on POST, per kind', async () => {
    const { api, requests } = setup();
    await api.replaceItems('playlist', 'p', ['b', 'a']);
    await api.addItems('collection', 'c', ['x']);
    await api.removeItem('playlist', 'p', 'a');
    await api.remove('collection', 'c');
    expect(requests.map((r) => [r.method, new URL(r.url).pathname])).toEqual([
      ['PUT', '/pleya/v1/playlists/p/items'],
      ['POST', '/pleya/v1/collections/c/items'],
      ['DELETE', '/pleya/v1/playlists/p/items/a'],
      ['DELETE', '/pleya/v1/collections/c']
    ]);
    expect(await requests[0]!.clone().json()).toEqual({ item_ids: ['b', 'a'] });
  });

  it('reads every page before a reorder', async () => {
    const { api, requests } = setup([
      { items: [{ id: '1' }], next_cursor: 'next' },
      { items: [{ id: '2' }], next_cursor: null }
    ]);
    const items = await api.allItems('playlist', 'p');
    expect(items.map((item) => item.id)).toEqual(['1', '2']);
    expect(new URL(requests[1]!.url).searchParams.get('cursor')).toBe('next');
  });

  it('refuses a write after the account changed', async () => {
    const { client, api, requests } = setup();
    await client.login({ username: 'B', password: 'test-only' });
    requests.length = 0;
    await expect(api.replaceItems('playlist', 'p', [])).rejects.toThrow(/account/i);
    expect(requests).toHaveLength(0);
  });
});

describe('list helpers', () => {
  it('treats a visibility it does not know as unknown', () => {
    expect(knownVisibility('users')).toBe('users');
    expect(knownVisibility('friends')).toBeNull();
  });

  it('finds the next row and stops at the end', () => {
    const items = [{ id: 'a' }, { id: 'b' }];
    expect(nextInList(items, 'a')).toBe('b');
    expect(nextInList(items, 'b')).toBeNull();
    expect(nextInList(items, 'gone')).toBeNull();
  });
});
