import { render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../api/types';
import { ARTWORK_LOADER_KEY } from './artworkLoader';

const h = vi.hoisted(() => ({ item: vi.fn() }));
vi.mock('../stores/session.svelte', () => ({ session: { client: { item: h.item }, capabilities: {} } }));
import HubRail from './HubRail.svelte';

const episode = (id: string, index: number, artwork?: Item['artwork']): Item => ({
  id, kind: 'episode', title: 'TBA', parent_id: 'season', index, added_at: '2026-11-05T12:00:00Z', artwork
});
const season: Item = { id: 'season', kind: 'season', title: 'Season 1', parent_id: 'show', index: 1, added_at: '2026-11-05T12:00:00Z' };
const show: Item = {
  id: 'show', kind: 'show', title: 'Moon News and Markets', added_at: '2026-11-05T12:00:00Z',
  artwork: { poster_id: 'show-poster', backdrop_id: 'show-backdrop' }
};

beforeEach(() => {
  h.item.mockReset();
  h.item.mockImplementation(async (id: string) => (id === 'season' ? season : show));
});

describe('HubRail met afleveringen', () => {
  it('toont bij een aflevering zonder still de serie-achtergrond, de serienaam en S1 · E6', async () => {
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image'], { type: 'image/png' }));
    const { container } = render(HubRail, {
      props: { title: 'Next up', items: [episode('e6', 6), episode('e2', 2, { poster_id: 'own-still', backdrop_id: null })] },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    const link = await screen.findByRole('link', { name: /Moon News and Markets.*S1 · E6/ });
    expect(link).toHaveAttribute('href', '/items/e6');
    expect(container.querySelectorAll('.card[data-shape="wide"]')).toHaveLength(2);
    await waitFor(() => expect(loader).toHaveBeenCalledWith('show-backdrop', expect.any(AbortSignal)));
    // Een eigen still wint van de serie.
    await waitFor(() => expect(loader).toHaveBeenCalledWith('own-still', expect.any(AbortSignal)));
    // Twee afleveringen van één seizoen: elke ouder één keer gelezen.
    expect(h.item.mock.calls.map((call) => call[0]).sort()).toEqual(['season', 'show']);
  });

  it('valt terug op de serieposter als de serie geen achtergrond heeft', async () => {
    h.item.mockImplementation(async (id: string) =>
      id === 'season' ? season : { ...show, artwork: { poster_id: 'show-poster', backdrop_id: null } });
    const loader = vi.fn(async (_id: string, _signal: AbortSignal) => new Blob(['image'], { type: 'image/png' }));
    render(HubRail, { props: { title: 'Recently added', items: [episode('e6', 6)] }, context: new Map([[ARTWORK_LOADER_KEY, loader]]) });
    await waitFor(() => expect(loader).toHaveBeenCalledWith('show-poster', expect.any(AbortSignal)));
  });

  it('leest geen ouders voor een rij zonder afleveringen', () => {
    render(HubRail, { props: { title: 'Films', items: [{ id: 'm', kind: 'movie', title: 'Alien', added_at: '2026-11-05T12:00:00Z' }] } });
    expect(h.item).not.toHaveBeenCalled();
  });
});
