import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import Hero from './Hero.svelte';
import type { Item } from '../api/types';

vi.mock('../stores/session.svelte', () => ({
  session: { client: { artworkBlob: vi.fn(async () => new Blob(['x'])) } }
}));

function movie(patch: Partial<Item> = {}): Item {
  return {
    id: 'm1',
    kind: 'movie',
    title: 'Blade Runner',
    added_at: '2026-01-01T00:00:00Z',
    year: 1982,
    duration_ms: 6_960_000,
    ...patch
  } as Item;
}

describe('Hero', () => {
  it('toont de titel als de kop van de pagina', () => {
    render(Hero, { props: { item: movie() } });
    expect(screen.getByRole('heading', { name: 'Blade Runner' })).toBeInTheDocument();
  });

  it('zet jaar en duur op één regel', () => {
    render(Hero, { props: { item: movie() } });
    expect(screen.getByText('1982 · 1h 56m')).toBeInTheDocument();
  });

  it('leidt naar de detailpagina en niet naar een speler', () => {
    const { container } = render(Hero, { props: { item: movie() } });
    expect(screen.getByRole('link')).toHaveAttribute('href', '/items/m1');
    // Afspelen is PS-4, en poort 3 en 4 staan nog open.
    expect(container.querySelector('video')).toBeNull();
    expect(screen.queryByRole('button', { name: /play/i })).toBeNull();
  });

  it('gebruikt de backdrop wanneer die er is, anders de poster', () => {
    const { container } = render(Hero, {
      props: { item: movie({ artwork: { poster_id: 'p1', backdrop_id: 'b1' } }) }
    });
    expect(container.querySelector('.artwork--flat')).not.toBeNull();
  });
});
