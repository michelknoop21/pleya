import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../api/types';
import { ARTWORK_LOADER_KEY } from './artworkLoader';

const h = vi.hoisted(() => ({ item: vi.fn() }));
vi.mock('../stores/session.svelte', () => ({ session: { client: { item: h.item }, capabilities: {} } }));
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
    ? { id, kind: 'season', parent_id: 'show', title: 'Season 5' }
    : { id: 'show', kind: 'show', title: 'Two and a Half Men', artwork: { poster_id: 'show-cover' } });
});

describe('continue watching covers', () => {
  it('keeps keyboard focus on the retained card when slow ancestry removes a duplicate', async () => {
    let resolveShow!: (value: Item) => void;
    const pending = new Promise<Item>(resolve => { resolveShow = resolve; });
    h.item.mockImplementation(async id => id === 'season'
      ? { id, kind: 'season', parent_id: 'show' } : pending);
    render(ContinueWatchingRail, { props: { items: [episode, { ...episode, id: 'older-episode', title: 'Older episode' }] } });
    const older = screen.getByRole('link', { name: /Older episode/ });
    older.focus();
    expect(older).toHaveFocus();
    resolveShow({ id: 'show', kind: 'show', title: 'Two and a Half Men', added_at: episode.added_at });
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(1));
    await waitFor(() => expect(screen.getByRole('link')).toHaveFocus());
  });
  it('keeps the most recently resumed episode per proven show across seasons, with its own progress', async () => {
    h.item.mockImplementation(async id => id === 'season' || id === 'other-season'
      ? { id, kind: 'season', parent_id: 'show', title: id }
      : { id: 'show', kind: 'show', title: 'Two and a Half Men' });
    render(ContinueWatchingRail, { props: { items: [episode, {
      ...episode, id: 'older-episode', parent_id: 'other-season', title: 'Older episode',
      user_state: { ...episode.user_state!, position_ms: 600_000, updated_at: '2026-11-01T12:00:00Z' }
    }] } });
    await waitFor(() => expect(h.item).toHaveBeenCalledWith('show', expect.any(AbortSignal)));
    await waitFor(() => expect(screen.getAllByRole('link')).toHaveLength(1));
    expect(screen.getByRole('link')).toHaveAttribute('href', '/items/episode-actual');
    expect(screen.getByRole('link')).toHaveTextContent('15m left');
  });
  it('keeps different shows with the same title and episodes with inaccessible ancestry', async () => {
    h.item.mockImplementation(async id => {
      if (id === 'missing-season') throw new Error('404');
      if (id === 'season' || id === 'other-season') return { id, kind: 'season', parent_id: `${id}-show` };
      return { id, kind: 'show', title: 'Same title' };
    });
    render(ContinueWatchingRail, { props: { items: [episode,
      { ...episode, id: 'other-episode', parent_id: 'other-season' },
      { ...episode, id: 'unavailable-episode', parent_id: 'missing-season' }
    ] } });
    await waitFor(() => expect(screen.getAllByRole('link', { name: /Same title/ })).toHaveLength(2));
    expect(screen.getAllByRole('link')).toHaveLength(3);
  });
  it('shows a resolved series cover while another series is still waiting', async () => {
    h.item.mockImplementation(async id => {
      if (id === 'blocked-season') return new Promise(() => {});
      return id === 'season'
        ? { id, kind: 'season', parent_id: 'show', title: 'Season 5' }
        : { id: 'show', kind: 'show', title: 'Two and a Half Men', artwork: { poster_id: 'show-cover' } };
    });
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image']));
    render(ContinueWatchingRail, {
      props: { items: [episode, { ...episode, id: 'blocked-episode', parent_id: 'blocked-season' }] },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    expect(await screen.findByRole('link', { name: /Two and a Half Men/ })).toHaveAttribute('href', '/items/episode-actual');
    await waitFor(() => expect(loader).toHaveBeenCalledWith('show-cover', expect.any(AbortSignal)));
  });
  it('renders the series cover in a poster cell while linking to the original episode', async () => {
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image'], { type: 'image/png' }));
    const { container } = render(ContinueWatchingRail, { props: { items: [episode] }, context: new Map([[ARTWORK_LOADER_KEY, loader]]) });
    const link = await screen.findByRole('link', { name: /Two and a Half Men/ });
    expect(link).toHaveAttribute('href', '/items/episode-actual');
    expect(container.querySelector('.card')).toHaveAttribute('data-shape', 'poster');
    await waitFor(() => expect(loader).toHaveBeenCalledWith('show-cover', expect.any(AbortSignal)));
    expect(loader.mock.calls.some(call => call[0] === 'episode-still' || call[0] === 'episode-background')).toBe(false);
    expect(link).toHaveTextContent('15m left');
  });
  it('leaves an unavailable parent as an honest cover fallback, keeping the episode reachable', async () => {
    h.item.mockRejectedValue(new Error('404'));
    const loader = vi.fn();
    render(ContinueWatchingRail, { props: { items: [episode] }, context: new Map([[ARTWORK_LOADER_KEY, loader]]) });
    expect(await screen.findByRole('link', { name: /Large Birds/ })).toHaveAttribute('href', '/items/episode-actual');
    await waitFor(() => expect(h.item).toHaveBeenCalled());
    expect(loader).not.toHaveBeenCalled();
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
