import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { PleyaClient, type FetchLike } from '../api/client';
import { TokenStore, type TokenStorage } from '../auth/tokens';

const h = vi.hoisted(() => ({ goto: vi.fn(async () => {}), client: null as unknown }));
vi.mock('$app/navigation', () => ({ goto: h.goto }));
vi.mock('../stores/session.svelte', () => ({ session: { get client() { return h.client; } } }));
import ItemDelete from './ItemDelete.svelte';
import PageNoticeView from './PageNoticeView.svelte';
import { pageNotice } from '../stores/pageNotice.svelte';

function storage(): TokenStorage {
  const data = new Map<string, string>();
  return { getItem: key => data.get(key) ?? null, setItem: (key, value) => void data.set(key, value), removeItem: key => void data.delete(key) };
}
const json = (value: unknown, status = 200) => new Response(JSON.stringify(value), { status, headers: { 'Content-Type': 'application/json' } });
const fail = (status: number, code: string, details: Record<string, unknown> = {}) =>
  json({ error: { code, message: code, retryable: false, details } }, status);

let requests: Request[];
let reply: (request: Request) => Response | Promise<Response>;

beforeEach(() => {
  h.goto.mockClear();
  pageNotice.current = null;
  requests = [];
  reply = () => json({ removed_files: 3, removed_items: 1 });
  const tokens = new TokenStore(storage(), storage());
  tokens.set({ access_token: 'test-a', refresh_token: 'test-r', expires_in_ms: 600000 });
  const fetch = vi.fn(async (input: RequestInfo | URL) => {
    const request = input instanceof Request ? input : new Request(input);
    requests.push(request);
    return reply(request);
  });
  h.client = new PleyaClient({ baseUrl: 'http://server.test/pleya/v1', tokens, fetch: fetch as unknown as FetchLike });
});

const movie = { id: 'm1', title: 'Heat', kind: 'movie' as const, parent_id: null };
const season = { id: 's1', title: 'Seizoen 1', kind: 'season' as const, parent_id: 'show1' };
const deletes = () => requests.filter(request => request.method === 'DELETE');

describe('een titel met zijn bestanden verwijderen', () => {
  it('noemt de titel, het wissen van de opslag en wat er voor alle gebruikers meegaat', () => {
    render(ItemDelete, { props: { item: season, open: true } });
    const dialog = screen.getByRole('dialog');
    expect(dialog.textContent).toContain('Delete “Seizoen 1”?');
    expect(dialog.textContent).toContain('erased from storage and cannot be recovered');
    expect(dialog.textContent).toContain('Watch status, history, favorites, ratings, downloads and places in lists');
    expect(dialog.textContent).toContain('All episodes under it are deleted too.');
  });

  it('noemt bij een film geen afleveringen', () => {
    render(ItemDelete, { props: { item: movie, open: true } });
    expect(screen.getByRole('dialog').textContent).not.toContain('episodes');
  });

  it('stuurt niets bij annuleren', async () => {
    render(ItemDelete, { props: { item: movie, open: true } });
    await fireEvent.click(screen.getByRole('button', { name: 'Cancel' }));
    expect(screen.queryByRole('dialog')).toBeNull();
    expect(requests).toHaveLength(0);
  });

  it('stuurt bij dubbel klikken één DELETE', async () => {
    let release: (value: Response) => void = () => {};
    reply = () => new Promise(resolve => (release = resolve));
    render(ItemDelete, { props: { item: movie, open: true } });
    const confirm = screen.getByRole('button', { name: 'Delete files' });
    confirm.click();
    confirm.click();
    await fireEvent.click(confirm);
    await waitFor(() => expect(requests).toHaveLength(1));
    release(json({ removed_files: 1, removed_items: 1 }));
    await waitFor(() => expect(h.goto).toHaveBeenCalled());
    expect(deletes()).toHaveLength(1);
    expect(new URL(deletes()[0]!.url).pathname).toBe('/pleya/v1/items/m1');
  });

  it('gaat na succes naar het overzicht en meldt het aantal gewiste bestanden', async () => {
    render(ItemDelete, { props: { item: movie, open: true } });
    await fireEvent.click(screen.getByRole('button', { name: 'Delete files' }));
    await waitFor(() => expect(h.goto).toHaveBeenCalledWith('/films'));
    expect(pageNotice.current).toEqual({ path: '/films', tone: 'info', text: '“Heat” is deleted, 3 files erased.', lines: [] });
  });

  it('gaat na een seizoen naar de serie erboven', async () => {
    render(ItemDelete, { props: { item: season, open: true } });
    await fireEvent.click(screen.getByRole('button', { name: 'Delete files' }));
    await waitFor(() => expect(h.goto).toHaveBeenCalledWith('/items/show1'));
  });

  it('blijft bij een onvolledige verwijdering staan, toont de gebleven paden en leest het item opnieuw', async () => {
    const onreload = vi.fn();
    reply = request => request.method === 'DELETE'
      ? fail(409, 'library.media_delete_incomplete', {
        removed_files: 4, removed_items: 2,
        failed: [{ path: 'Show/S01/<b>e3</b>.mkv', reason: 'remove_failed' }, { path: 'Show/S01/e3.srt', reason: 'media_kept' }]
      })
      : json({ id: 's1', kind: 'season', title: 'Seizoen 1', added_at: '2026-01-01T00:00:00Z' });
    render(ItemDelete, { props: { item: season, open: true, onreload } });
    await fireEvent.click(screen.getByRole('button', { name: 'Delete files' }));
    await waitFor(() => expect(onreload).toHaveBeenCalledOnce());
    expect(h.goto).not.toHaveBeenCalled();
    expect(requests.map(request => `${request.method} ${new URL(request.url).pathname}`)).toEqual(['DELETE /pleya/v1/items/s1', 'GET /pleya/v1/items/s1']);

    render(PageNoticeView, { props: { path: '/' } });
    const alert = screen.getByRole('alert');
    expect(alert.textContent).toContain('“Seizoen 1” was not fully deleted: 4 files and 2 titles are gone');
    expect(screen.getAllByRole('listitem').map(item => item.textContent)).toEqual([
      'Show/S01/<b>e3</b>.mkv: could not be erased',
      'Show/S01/e3.srt: kept because a media file stayed'
    ]);
    expect(alert.querySelector('b')).toBeNull();
  });

  it('leest niets opnieuw als er niets weg is', async () => {
    const onreload = vi.fn();
    reply = () => fail(409, 'library.media_delete_incomplete', { removed_files: 0, removed_items: 0, failed: [{ path: 'a.mkv', reason: 'symlink' }] });
    render(ItemDelete, { props: { item: movie, open: true, onreload } });
    await fireEvent.click(screen.getByRole('button', { name: 'Delete files' }));
    await waitFor(() => expect(pageNotice.current?.lines).toEqual(['a.mkv: is a symbolic link']));
    expect(requests).toHaveLength(1);
    expect(onreload).not.toHaveBeenCalled();
    expect(h.goto).not.toHaveBeenCalled();
  });

  it.each([
    [409, 'library.media_delete_unavailable', { reason: 'disabled' }, 'Deleting files is turned off on this server.'],
    [409, 'library.media_delete_unavailable', { reason: 'read_only' }, 'The storage of “Heat” is mounted read-only, so nothing was deleted.'],
    [409, 'library.media_delete_unavailable', { reason: 'root_overlap' }, 'The storage of “Heat” overlaps with another library, so nothing was deleted.'],
    [409, 'library.scan_in_progress', {}, 'A scan of this library is running or waiting. Try again after the scan.'],
    [503, 'storage.unavailable', {}, 'The storage of “Heat” cannot be reached right now. Nothing was deleted.'],
    [403, 'library.delete_not_permitted', {}, 'Only the owner or an administrator can delete files.'],
    [404, 'item.not_found', {}, '“Heat” no longer exists or is not visible to you.']
  ])('meldt %i %s %o in eigen woorden en blijft staan', async (status, code, details, text) => {
    reply = () => fail(status, code, details);
    render(ItemDelete, { props: { item: movie, open: true } });
    await fireEvent.click(screen.getByRole('button', { name: 'Delete files' }));
    await waitFor(() => expect(pageNotice.current).toEqual({ path: '/', tone: 'err', text, lines: [] }));
    expect(h.goto).not.toHaveBeenCalled();
  });
});
