import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item, Library } from '../lib/api/types';

const h = vi.hoisted(() => ({
  hub: vi.fn(),
  item: vi.fn(),
  capabilities: { watch_state: true, playback_plan: true },
  libraries: [] as Library[]
}));
vi.mock('../lib/stores/session.svelte.js', () => ({
  session: {
    client: { hub: h.hub, item: h.item },
    get capabilities() { return h.capabilities; },
    get libraries() { return h.libraries; }
  }
}));
import Home from './+page.svelte';

const item = (id: string, kind: Item['kind'] = 'movie'): Item => ({
  id, kind, title: id, added_at: '2026-10-29T12:00:00Z', versions: [{ id: 'version', container: 'mkv', duration_ms: 60000, file_count: 1 }]
});

beforeEach(() => {
  h.capabilities = { watch_state: true, playback_plan: true };
  h.libraries = [
    { id: 'movies', title: 'Films', kind: 'movies', item_count: 2 },
    { id: 'shows', title: 'Series', kind: 'shows', item_count: 1 }
  ];
  h.hub.mockReset();
  h.item.mockReset();
  h.hub.mockImplementation(async (id: string, query: { library_id?: string }) => ({
    items: id === 'continue_watching' ? [item('Resume me')]
      : id === 'next_up' ? [item('Next episode', 'episode')]
      : [item(query.library_id ?? 'Hero')]
  }));
});

describe('Home uses the current server capabilities and libraries', () => {
  it('gives an episode-only Home its series context while preserving episode playback', async () => {
    h.libraries = [];
    h.hub.mockImplementation(async (id: string) => ({ items: id === 'recently_added'
      ? [{ ...item('episode', 'episode'), title: 'Testing 1-2-3', parent_id: 'season' }] : [] }));
    h.item.mockImplementation(async id => id === 'season'
      ? { ...item('season', 'season'), parent_id: 'show' }
      : { ...item('show', 'show'), title: 'The Simpsons', summary: 'A family in Springfield.', artwork: { backdrop_id: 'series-background' } });
    const { container } = render(Home);
    expect(await screen.findByRole('heading', { name: 'The Simpsons' })).toBeInTheDocument();
    expect(screen.getByText('Testing 1-2-3')).toBeInTheDocument();
    expect(screen.getByText('A family in Springfield.')).toBeInTheDocument();
    expect(screen.getByRole('link', { name: 'Play' })).toHaveAttribute('href', '/items/episode/play');
    expect(screen.getByRole('link', { name: 'More info' })).toHaveAttribute('href', '/items/episode');
    expect(container.querySelector('.hero--none')).toBeNull();
  });
  it('renders Home immediately when a parent read is still pending and aborts it on leave', async () => {
    h.libraries = [];
    h.hub.mockImplementation(async (id: string) => ({ items: id === 'recently_added'
      ? [{ ...item('episode', 'episode'), parent_id: 'season' }] : [] }));
    h.item.mockImplementation(() => new Promise(() => {}));
    const { unmount } = render(Home);
    await screen.findByRole('heading', { name: 'episode' });
    expect(screen.getByRole('link', { name: 'Play' })).toHaveAttribute('href', '/items/episode/play');
    expect(h.item).toHaveBeenCalled();
    const active = h.item.mock.calls[0]![1] as AbortSignal;
    unmount();
    expect(active.aborted).toBe(true);
  });
  it('retains the episode poster when neither ancestor has artwork', async () => {
    h.libraries = [];
    h.hub.mockImplementation(async (id: string) => ({ items: id === 'recently_added'
      ? [{ ...item('episode', 'episode'), parent_id: 'season', artwork: { poster_id: 'own-poster' } }] : [] }));
    h.item.mockImplementation(async id => id === 'season'
      ? { ...item('season', 'season'), parent_id: 'show' }
      : { ...item('show', 'show'), title: 'The Simpsons' });
    const { container } = render(Home);
    await screen.findByRole('heading', { name: 'The Simpsons' });
    expect(container.querySelector('.hero')).toHaveClass('hero--poster');
    expect(container.querySelector('.hero--none')).toBeNull();
  });
  it('shows personal hubs and separate recent rows for each video library', async () => {
    render(Home);
    expect(await screen.findByRole('heading', { name: 'Continue watching' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Next episodes' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Recently added · Films' })).toBeInTheDocument();
    expect(screen.getByRole('heading', { name: 'Recently added · Series' })).toBeInTheDocument();
    expect(h.hub).toHaveBeenCalledWith('recently_added', { library_id: 'movies', limit: 24 }, expect.any(AbortSignal));
    expect(screen.getByRole('link', { name: 'Play' })).toHaveAttribute('href', '/items/Hero/play');
  });

  it('does not request personal routes on an old server', async () => {
    h.capabilities = { watch_state: false, playback_plan: true };
    render(Home);
    await screen.findByRole('heading', { name: 'Hero' });
    expect(h.hub.mock.calls.every(([id]) => id === 'recently_added')).toBe(true);
    expect(screen.queryByRole('heading', { name: 'Continue watching' })).toBeNull();
  });

  it('hides empty rows and does not confuse a personal hub with an empty server', async () => {
    h.hub.mockImplementation(async (id: string) => ({ items: id === 'continue_watching' ? [item('Resume me')] : [] }));
    render(Home);
    await screen.findByRole('heading', { name: 'Continue watching' });
    expect(screen.queryByRole('heading', { name: 'Nothing has been added yet' })).toBeNull();
    expect(screen.queryByRole('heading', { name: 'Next episodes' })).toBeNull();
    expect(screen.queryByRole('heading', { name: 'Recently added · Films' })).toBeNull();
  });

  it('aborts all in-flight hub requests when the page is left', async () => {
    const { unmount } = render(Home);
    await waitFor(() => expect(h.hub.mock.calls.length).toBeGreaterThan(1));
    const signals = h.hub.mock.calls.map((call) => call[2] as AbortSignal);
    unmount();
    expect(signals.every((signal) => signal.aborted)).toBe(true);
  });
});
