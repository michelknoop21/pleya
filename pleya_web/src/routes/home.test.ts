import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item, Library } from '../lib/api/types';

const h = vi.hoisted(() => ({
  hub: vi.fn(),
  capabilities: { watch_state: true, playback_plan: true },
  libraries: [] as Library[]
}));
vi.mock('../lib/stores/session.svelte.js', () => ({
  session: {
    client: { hub: h.hub },
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
  h.hub.mockImplementation(async (id: string, query: { library_id?: string }) => ({
    items: id === 'continue_watching' ? [item('Resume me')]
      : id === 'next_up' ? [item('Next episode', 'episode')]
      : [item(query.library_id ?? 'Hero')]
  }));
});

describe('Home uses the current server capabilities and libraries', () => {
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
