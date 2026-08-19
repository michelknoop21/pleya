import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import MediaGrid from './MediaGrid.svelte';
import type { Item } from '../api/types';

vi.mock('../stores/session.svelte', () => ({
  session: { client: { artworkBlob: vi.fn(async () => new Blob(['x'])) } }
}));

function items(count: number): Item[] {
  return Array.from({ length: count }, (_, i) => ({
    id: `i${i}`,
    kind: 'movie' as const,
    title: `Title ${i}`,
    added_at: '2026-01-01T00:00:00Z'
  }));
}

describe('MediaGrid', () => {
  it('is een lijst met een naam, zodat een schermlezer weet waar hij is', () => {
    render(MediaGrid, { props: { items: items(3), label: 'Films' } });
    expect(screen.getByRole('list', { name: 'Films' })).toBeInTheDocument();
  });

  it('zet elk item in een eigen lijstonderdeel', () => {
    render(MediaGrid, { props: { items: items(7) } });
    expect(screen.getAllByRole('listitem')).toHaveLength(7);
  });

  it('tekent niets bij een lege lijst, in plaats van een lege cel', () => {
    render(MediaGrid, { props: { items: [] } });
    expect(screen.queryAllByRole('listitem')).toHaveLength(0);
  });

  it('geeft een raster van alleen afleveringen de brede vorm', () => {
    const episodes: Item[] = [
      { id: 'e1', kind: 'episode', title: 'E1', added_at: '2026-01-01T00:00:00Z' },
      { id: 'e2', kind: 'episode', title: 'E2', added_at: '2026-01-01T00:00:00Z' }
    ];
    const { container } = render(MediaGrid, { props: { items: episodes } });
    expect(container.querySelectorAll('.artwork--wide')).toHaveLength(2);
  });

  it('houdt een gemengd raster op één vorm, zodat een rij één hoogte heeft', () => {
    const mixed: Item[] = [
      { id: 'e1', kind: 'episode', title: 'E1', added_at: '2026-01-01T00:00:00Z' },
      { id: 'm1', kind: 'movie', title: 'M1', added_at: '2026-01-01T00:00:00Z' }
    ];
    const { container } = render(MediaGrid, { props: { items: mixed } });
    expect(container.querySelectorAll('.artwork--poster')).toHaveLength(2);
    expect(container.querySelectorAll('.artwork--wide')).toHaveLength(0);
  });

  it('laadt alleen de eerste kaarten meteen, de rest wacht op de waarnemer', () => {
    const { container } = render(MediaGrid, { props: { items: items(40), eagerCount: 4 } });
    // De luie kaarten hebben nog geen <img> en ook geen fallback: ze zijn
    // simpelweg nog niet in beeld geweest.
    expect(container.querySelectorAll('.artwork img')).toHaveLength(0);
    expect(container.querySelectorAll('.artwork')).toHaveLength(40);
  });
});
