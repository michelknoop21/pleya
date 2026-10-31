import { describe, expect, it, vi } from 'vitest';
import { PleyaClient, type FetchLike } from './client';
import { TokenStore, type TokenStorage } from '../auth/tokens';
import { allPages, knownVisibility, listsApi, mergeOrder, nextInList, orderedItems } from './lists';
import { ApiError } from './errors';
import type { Item } from './types';

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
  it('sends the revision the reorder mode saw, and none on a server without one', async () => {
    const { api, requests } = setup([
      { id: 'p', revision: 7 },
      { items: [{ id: 'a' }, { id: 'b' }], next_cursor: null },
      { items: [{ id: 'a' }, { id: 'b' }], next_cursor: null },
      { items: [{ id: 'a' }], next_cursor: null }
    ]);
    const base = await api.readForReorder('playlist', 'p');
    expect(base.revision).toBe(7);
    await api.saveOrder('playlist', 'p', ['b', 'a'], base.revision);
    expect(await requests.at(-1)!.clone().json()).toEqual({ item_ids: ['b', 'a'], base_revision: 7 });
    await api.saveOrder('playlist', 'p', ['a']);
    expect(await requests.at(-1)!.clone().json()).toEqual({ item_ids: ['a'] });
  });

  it('reads the revision before the rows', async () => {
    const { api, requests } = setup([{ id: 'c', revision: 1 }]);
    await api.readForReorder('collection', 'c');
    expect(requests.map((r) => new URL(r.url).pathname)).toEqual(['/pleya/v1/collections/c', '/pleya/v1/collections/c/items']);
  });

  it('turns a 409 into library.list_conflict for the screen', async () => {
    const fetch = vi.fn(async (input: RequestInfo | URL) => {
      const request = input as Request;
      if (request.method === 'GET') return json({ items: [{ id: 'a' }], next_cursor: null });
      return new Response(JSON.stringify({ error: { code: 'library.list_conflict', message: 'changed', retryable: false, details: { revision: 9 } } }),
        { status: 409, headers: { 'Content-Type': 'application/json' } });
    });
    const tokens = new TokenStore(storage(), storage());
    tokens.set({ access_token: 'test-account-A', refresh_token: 'test-refresh-A', expires_in_ms: 600000 });
    const api = listsApi(new PleyaClient({ baseUrl: 'http://server.test/pleya/v1', tokens, fetch: fetch as unknown as FetchLike }));
    const err = await api.saveOrder('playlist', 'p', ['a'], 7).catch((e: unknown) => e);
    expect(err).toBeInstanceOf(ApiError);
    expect((err as ApiError).code).toBe('library.list_conflict');
  });

  it('keeps the chosen order on the list as it is now', () => {
    const row = (id: string) => ({ id }) as Item;
    expect(orderedItems(['b', 'weg', 'a'], [row('a'), row('b'), row('nieuw')]).map((item) => item.id)).toEqual(['b', 'a', 'nieuw']);
  });

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

  it('applies a reorder to the list as it is now, not as it was when the mode opened', async () => {
    const { api, requests } = setup([
      { items: [{ id: 'a' }, { id: 'b' }, { id: 'nieuw' }], next_cursor: null }
    ]);
    await api.saveOrder('playlist', 'p', ['b', 'weg', 'a']);
    const put = requests.at(-1)!;
    expect(put.method).toBe('PUT');
    expect(await put.clone().json()).toEqual({ item_ids: ['b', 'a', 'nieuw'] });
  });

  it('merges a chosen order with the current rows', () => {
    expect(mergeOrder(['c', 'a'], ['a', 'c'])).toEqual(['c', 'a']);
    expect(mergeOrder(['c', 'a'], ['a', 'b', 'c', 'd'])).toEqual(['c', 'a', 'b', 'd']);
    expect(mergeOrder(['c', 'a'], ['a'])).toEqual(['a']);
    expect(mergeOrder(['a'], [])).toEqual([]);
  });

  it('follows the cursor to the last page', async () => {
    const read = vi.fn(async (cursor?: string) => cursor
      ? { items: [2], next_cursor: null }
      : { items: [1], next_cursor: 'next' });
    await expect(allPages(read)).resolves.toEqual([1, 2]);
    expect(read).toHaveBeenLastCalledWith('next');
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
