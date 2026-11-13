import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../../lib/api/types';

const h = vi.hoisted(() => ({
  item: vi.fn(), children: vi.fn(), hub: vi.fn(), watched: vi.fn(), favorite: vi.fn(),
  caps: {} as Record<string, boolean>, admin: false, url: new URL('http://client.test/items/show')
}));
vi.mock('$app/state', () => ({ page: { params: { id: 'show' }, get url() { return h.url; } } }));
vi.mock('$app/navigation', () => ({ goto: vi.fn() }));
vi.mock('../../lib/stores/session.svelte.js', () => ({ session: {
  client: { item: h.item, children: h.children, hub: h.hub },
  get canAdminister() { return h.admin; },
  get capabilities() { return h.caps; }
} }));
vi.mock('../../lib/api/personal', () => ({ personalApi: () => ({ setWatched: h.watched, setFavorite: h.favorite }) }));
import Detail from './[id]/+page.svelte';

const at = '2026-10-29T12:00:00Z';
const show: Item = { id: 'show', kind: 'show', title: 'Fixture show', year: 2022, added_at: at, summary: 'A real plot from NFO.',
  genres: ['Drama', 'Mystery'], content_rating: '16', child_count: 2, episode_count: 5, watched_episode_count: 2,
  people: [{ name: 'Director name', role: 'director' }, { name: 'Actor name', role: 'actor', character: 'Character name' }] };
const season = (n: number): Item => ({ id: `s${n}`, kind: 'season', title: `Season ${n}`, index: n, parent_id: 'show', added_at: at, child_count: n === 1 ? 2 : 3 });
const episode = (seasonNo: number, n: number, state?: Partial<NonNullable<Item['user_state']>>): Item => ({
  id: `s${seasonNo}e${n}`, kind: 'episode', title: `Episode ${seasonNo}.${n}`, index: n, parent_id: `s${seasonNo}`, added_at: at,
  duration_ms: 3_000_000, summary: `Plot ${seasonNo}.${n}`, versions: [{ id: 'v', container: 'mkv', duration_ms: 3_000_000, file_count: 1 }],
  user_state: state ? { position_ms: 0, watched: false, play_count: 0, updated_at: at, ...state } : null
});
const byParent: Record<string, Item[]> = {
  show: [season(1), season(2)],
  s1: [episode(1, 1, { watched: true }), episode(1, 2, { watched: true })],
  s2: [episode(2, 1, { watched: true }), episode(2, 2, { position_ms: 1_200_000 }), episode(2, 3)]
};

beforeEach(() => {
  h.caps = { playback_plan: true, watch_state: true, favorites: true };
  h.admin = false;
  h.url = new URL('http://client.test/items/show');
  for (const mock of [h.item, h.children, h.hub, h.watched, h.favorite]) mock.mockReset();
  h.item.mockResolvedValue(structuredClone(show));
  h.children.mockImplementation(async (id: string) => ({ items: structuredClone(byParent[id] ?? []), next_cursor: null }));
  h.hub.mockImplementation(async (hub: string) => ({ items: hub === 'continue_watching' ? [{ ...episode(9, 1, { position_ms: 5 }), parent_id: 'other-season' }, structuredClone(byParent['s2']![1]!)] : [], next_cursor: null }));
  h.watched.mockImplementation(async (_id: string, watched: boolean) => ({ position_ms: 0, watched, play_count: 1, updated_at: at }));
  h.favorite.mockResolvedValue(undefined);
});

describe('series detail', () => {
  it('shows the series head with seasons, rating, genres and the watched count', async () => {
    render(Detail);
    expect(await screen.findByRole('heading', { level: 1, name: 'Fixture show' })).toBeInTheDocument();
    expect(screen.getByText(/2022 · 2 seasons/)).toHaveTextContent('16');
    expect(screen.getByText(/Drama, Mystery/)).toBeInTheDocument();
    expect(screen.getByText('A real plot from NFO.')).toBeInTheDocument();
    expect(await screen.findByText('2 of 5 episodes watched')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: /Series/ })).toHaveAttribute('href', '/series');
  });

  it('continues with the episode the server names and opens that season', async () => {
    render(Detail);
    const panel = await screen.findByRole('region', { name: /Continue watching · Season 2 · Episode 2/ });
    expect(within(panel).getByRole('link', { name: /Resume/ })).toHaveAttribute('href', '/items/s2e2/play?t=1200');
    expect(within(panel).getByRole('link', { name: 'Play from start' })).toHaveAttribute('href', '/items/s2e2/play');
    expect(await screen.findByRole('button', { name: 'Season 2 · 3' })).toHaveAttribute('aria-pressed', 'true');
    expect(await screen.findByText('1 watched · 1 in progress · 1 unwatched')).toBeInTheDocument();
    expect(h.children).not.toHaveBeenCalledWith('s1', expect.anything(), expect.anything());
  });

  it('lists episodes with a play link, a detail link and a summary, and switches season', async () => {
    render(Detail);
    const list = await screen.findByRole('list', { name: 'Episodes' });
    expect(await within(list).findByRole('link', { name: '2. Episode 2.2' })).toHaveAttribute('href', '/items/s2e2');
    expect(within(list).getByRole('link', { name: 'Play Episode 2.2' })).toHaveAttribute('href', '/items/s2e2/play?t=1200');
    expect(within(list).getByText('Plot 2.3')).toBeInTheDocument();
    await fireEvent.click(screen.getByRole('button', { name: 'Season 1 · 2' }));
    expect(await screen.findByRole('link', { name: '1. Episode 1.1' })).toBeInTheDocument();
    expect(screen.queryByRole('link', { name: '2. Episode 2.2' })).toBeNull();
  });

  it('toggles one episode and keeps the counts in step', async () => {
    render(Detail);
    const toggle = await screen.findByRole('button', { name: 'Episode 2.3: watched on or off' });
    expect(toggle).toHaveAttribute('aria-pressed', 'false');
    await fireEvent.click(toggle);
    await waitFor(() => expect(toggle).toHaveAttribute('aria-pressed', 'true'));
    expect(h.watched).toHaveBeenCalledWith('s2e3', true, 3_000_000);
    expect(screen.getByText('2 watched · 1 in progress · 0 unwatched')).toBeInTheDocument();
    expect(screen.getByText('3 of 5 episodes watched')).toBeInTheDocument();
  });

  it('marks a whole season through the per-episode route, skipping what is already watched', async () => {
    render(Detail);
    await fireEvent.click(await screen.findByRole('button', { name: 'Mark season as watched' }));
    await screen.findByRole('button', { name: 'Mark season as unwatched' });
    expect(h.watched.mock.calls.map(call => call[0])).toEqual(['s2e2', 's2e3']);
    expect(screen.getByText('4 of 5 episodes watched')).toBeInTheDocument();
  });

  it('stops marking at the first failure and says so', async () => {
    h.watched.mockRejectedValueOnce(new Error('offline'));
    render(Detail);
    await fireEvent.click(await screen.findByRole('button', { name: 'Mark season as watched' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(h.watched).toHaveBeenCalledTimes(1);
    expect(screen.getByRole('button', { name: 'Mark season as watched' })).toBeInTheDocument();
  });

  it('counts what was written before a later failure, and reloads the hubs once', async () => {
    h.watched.mockImplementationOnce(async () => ({ position_ms: 0, watched: true, play_count: 1, updated_at: at }));
    h.watched.mockRejectedValueOnce(new Error('offline'));
    render(Detail);
    await fireEvent.click(await screen.findByRole('button', { name: 'Mark season as watched' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(h.watched).toHaveBeenCalledTimes(2);
    expect(screen.getByText('3 of 5 episodes watched')).toBeInTheDocument();
    // Twee hubs bij het laden, twee na de reeks: niet twee per aflevering.
    expect(h.hub).toHaveBeenCalledTimes(4);
  });

  it('opens Details and cast when the URL points at watched-by', async () => {
    h.url = new URL('http://client.test/items/show#watched-by');
    render(Detail);
    expect(await screen.findByRole('tab', { name: 'Details and cast' })).toHaveAttribute('aria-selected', 'true');
  });

  it('hides watch controls and the continue panel without watch state', async () => {
    h.caps = { playback_plan: true };
    render(Detail);
    expect(await screen.findByRole('button', { name: 'Season 1 · 2' })).toHaveAttribute('aria-pressed', 'true');
    await screen.findByRole('link', { name: '1. Episode 1.1' });
    expect(h.hub).not.toHaveBeenCalled();
    expect(screen.queryByRole('button', { name: /watched on or off/ })).toBeNull();
    expect(screen.queryByRole('button', { name: /Mark season/ })).toBeNull();
    expect(screen.queryByText(/episodes watched/)).toBeNull();
  });

  it('keeps the favorite control connected', async () => {
    render(Detail);
    await fireEvent.click(await screen.findByRole('button', { name: 'Add to favorites' }));
    await screen.findByRole('button', { name: 'Remove from favorites' });
    expect(h.favorite).toHaveBeenCalledWith('show', true);
  });

  it('keeps later seasons reachable through the existing cursor', async () => {
    h.children.mockImplementation(async (id: string, query: { cursor?: string }) => id !== 'show' ? { items: [], next_cursor: null }
      : query.cursor ? { items: [season(2)], next_cursor: null } : { items: [season(1)], next_cursor: 'next-page' });
    render(Detail);
    await screen.findByRole('button', { name: 'Season 1 · 2' });
    await fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByRole('button', { name: 'Season 2 · 3' });
    expect(h.children).toHaveBeenCalledWith('show', { limit: 100, cursor: 'next-page' }, expect.any(AbortSignal));
  });

  it('retains metadata when loading seasons fails and retries only the failed section', async () => {
    h.children.mockRejectedValueOnce(new Error('offline'));
    render(Detail);
    await fireEvent.click(await screen.findByRole('button', { name: 'Retry' }));
    expect(screen.getByText('A real plot from NFO.')).toBeInTheDocument();
    await screen.findByRole('button', { name: 'Season 1 · 2' });
    expect(h.item).toHaveBeenCalledTimes(1);
  });

  it('moves cast, facts and the admin links to the details tab, reachable by keyboard', async () => {
    h.admin = true; h.caps = { ...h.caps, metadata_overrides: true };
    render(Detail);
    const tab = await screen.findByRole('tab', { name: 'Episodes' });
    expect(tab).toHaveAttribute('aria-selected', 'true');
    await fireEvent.keyDown(tab, { key: 'ArrowRight' });
    expect(screen.getByRole('tab', { name: 'Details and cast' })).toHaveAttribute('aria-selected', 'true');
    expect(screen.getByRole('tab', { name: 'Details and cast' })).toHaveFocus();
    expect(screen.getByText('Actor name').parentElement).toHaveTextContent('Character name');
    expect(screen.getByRole('link', { name: 'Edit metadata' })).toHaveAttribute('href', '/admin/metadata/edit?item=show');
    expect(screen.getByRole('link', { name: 'Correct match' })).toHaveAttribute('href', '/admin/metadata/match?item=show');
    expect(screen.queryByRole('list', { name: 'Episodes' })).toBeNull();
  });
});
