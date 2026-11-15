import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../api/types';
import { ARTWORK_LOADER_KEY } from './artworkLoader';

const h = vi.hoisted(() => ({ item: vi.fn() }));
vi.mock('../stores/session.svelte', () => ({ session: { client: { item: h.item }, capabilities: { playback_plan: true, watch_state: true } } }));
import ContinueWatchingRail from './ContinueWatchingRail.svelte';

const episode: Item = {
  id: 'episode-actual', kind: 'episode', title: 'Large Birds, Spiders and Mom', parent_id: 'season', index: 1,
  added_at: '2026-11-02T12:00:00Z', duration_ms: 1_200_000,
  user_state: { watched: false, position_ms: 300_000, play_count: 0, updated_at: '2026-11-02T12:00:00Z' },
  artwork: { poster_id: 'episode-still', backdrop_id: 'episode-background' }
};
beforeEach(() => {
  h.item.mockReset();
  h.item.mockImplementation(async id => id === 'season'
    ? { id, kind: 'season', parent_id: 'show', title: 'Season 5', index: 5 }
    : { id: 'show', kind: 'show', title: 'Two and a Half Men', artwork: { poster_id: 'show-cover' } });
});

describe('continue watching cards', () => {
  it('shows a resolved series name while another series is still waiting', async () => {
    h.item.mockImplementation(async id => {
      if (id === 'blocked-season') return new Promise(() => {});
      return id === 'season'
        ? { id, kind: 'season', parent_id: 'show', title: 'Season 5' }
        : { id: 'show', kind: 'show', title: 'Two and a Half Men', artwork: { poster_id: 'show-cover' } };
    });
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image']));
    const { container } = render(ContinueWatchingRail, {
      props: { items: [episode, { ...episode, id: 'blocked-episode', parent_id: 'blocked-season' }] },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    expect(await screen.findByRole('link', { name: /Two and a Half Men/ })).toHaveAttribute('href', '/items/episode-actual');
    // De wachtende aflevering staat er al, onder haar eigen titel.
    expect(container.querySelector('a[href="/items/blocked-episode"] .card__title')).toHaveTextContent('Large Birds, Spiders and Mom');
  });
  it('renders a wide card with the episode still, the progress bar and the series line, linking to the original episode', async () => {
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image'], { type: 'image/png' }));
    const { container } = render(ContinueWatchingRail, { props: { items: [episode] }, context: new Map([[ARTWORK_LOADER_KEY, loader]]) });
    const link = await screen.findByRole('link', { name: /Two and a Half Men/ });
    expect(link).toHaveAttribute('href', '/items/episode-actual');
    expect(container.querySelector('.card')).toHaveAttribute('data-shape', 'wide');
    expect(container.querySelector('.rail')).toHaveClass('rail--wide');
    await waitFor(() => expect(loader).toHaveBeenCalledWith('episode-background', expect.any(AbortSignal)));
    expect(loader.mock.calls.some(call => call[0] === 'show-cover')).toBe(false);
    // 300 000 van 1 200 000: een kwart, onderin het beeld.
    expect(container.querySelector<HTMLElement>('.card__art .prog i')?.style.width).toBe('25%');
    expect(link).toHaveTextContent('S5 · E1 · 15m left · Large Birds, Spiders and Mom');
  });
  it('falls back to the series backdrop for an episode without a still', async () => {
    h.item.mockImplementation(async id => id === 'season'
      ? { id, kind: 'season', parent_id: 'show', title: 'Season 5', index: 5 }
      : { id: 'show', kind: 'show', title: 'Two and a Half Men', artwork: { poster_id: 'show-cover', backdrop_id: 'show-wide' } });
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image'], { type: 'image/png' }));
    render(ContinueWatchingRail, { props: { items: [{ ...episode, artwork: {} }] }, context: new Map([[ARTWORK_LOADER_KEY, loader]]) });
    await waitFor(() => expect(loader).toHaveBeenCalledWith('show-wide', expect.any(AbortSignal)));
  });
  it('shows a film with its own title and the time left', async () => {
    const film: Item = { ...episode, id: 'film', kind: 'movie', title: 'Dune', parent_id: null, index: null };
    const { container } = render(ContinueWatchingRail, { props: { items: [film] } });
    expect(await screen.findByRole('link', { name: 'Dune 15m left' })).toHaveAttribute('href', '/items/film');
    expect(container.querySelector('.card')).toHaveAttribute('data-shape', 'wide');
    expect(h.item).not.toHaveBeenCalled();
  });
  it('offers the quick actions on its cards', async () => {
    render(ContinueWatchingRail, { props: { items: [{ ...episode, versions: [{ id: 'v', container: 'mkv', duration_ms: 1_200_000, file_count: 1 }] }] } });
    expect(await screen.findByRole('link', { name: /^Play / })).toHaveAttribute('href', '/items/episode-actual/play?t=300');
    expect(screen.getByRole('button', { name: 'Mark watched' })).toBeInTheDocument();
  });
  it('keeps the episode reachable under its own title and still when the parent is unavailable', async () => {
    h.item.mockRejectedValue(new Error('404'));
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image'], { type: 'image/png' }));
    render(ContinueWatchingRail, { props: { items: [episode] }, context: new Map([[ARTWORK_LOADER_KEY, loader]]) });
    const link = await screen.findByRole('link', { name: /Large Birds/ });
    expect(link).toHaveAttribute('href', '/items/episode-actual');
    await waitFor(() => expect(h.item).toHaveBeenCalled());
    await waitFor(() => expect(loader).toHaveBeenCalledWith('episode-background', expect.any(AbortSignal)));
    // De afleveringstitel staat er één keer, niet ook nog in de onderregel.
    expect(link.textContent?.match(/Large Birds/g)).toHaveLength(1);
  });
  it('aborts ancestor requests when the rail is removed', async () => {
    let requested: AbortSignal | undefined;
    h.item.mockImplementation((_id, signal) => { requested = signal; return new Promise(() => {}); });
    const { unmount } = render(ContinueWatchingRail, { props: { items: [episode] } });
    await waitFor(() => expect(requested).toBeDefined());
    unmount();
    expect(requested?.aborted).toBe(true);
  });
});
