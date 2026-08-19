import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import HubRail from './HubRail.svelte';
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

describe('HubRail', () => {
  it('tekent kop en rij wanneer er inhoud is', () => {
    render(HubRail, { props: { title: 'Recently added', items: items(4) } });
    expect(screen.getByRole('heading', { name: 'Recently added' })).toBeInTheDocument();
    expect(screen.getAllByRole('listitem')).toHaveLength(4);
  });

  it('verdwijnt volledig bij een lege lijst', () => {
    // continue_watching en next_up leveren vandaag lege lijsten omdat er geen
    // kijkstatus is. Een kop boven niets zou beloven dat daar ooit iets komt.
    const { container } = render(HubRail, { props: { title: 'Continue watching', items: [] } });
    expect(container.querySelector('.rail')).toBeNull();
    expect(screen.queryByText('Continue watching')).toBeNull();
  });

  it('maakt van de kop een link wanneer er een doorklikpad is', () => {
    render(HubRail, { props: { title: 'Films', items: items(2), href: '/libraries/x' } });
    expect(screen.getByRole('link', { name: /Films/ })).toHaveAttribute('href', '/libraries/x');
  });

  it('geeft de schuifknoppen een naam in plaats van alleen een pijl', () => {
    render(HubRail, { props: { title: 'Films', items: items(2) } });
    expect(screen.getByRole('button', { name: 'Scroll left' })).toBeInTheDocument();
    expect(screen.getByRole('button', { name: 'Scroll right' })).toBeInTheDocument();
  });

  it('geeft een rij die alleen afleveringen bevat de brede vorm', () => {
    const { container } = render(HubRail, {
      props: {
        title: 'Episodes',
        items: [
          { id: 'a', kind: 'episode', title: 'E1', added_at: '2026-01-01T00:00:00Z' },
          { id: 'b', kind: 'episode', title: 'E2', added_at: '2026-01-01T00:00:00Z' }
        ] as Item[]
      }
    });
    expect(container.querySelectorAll('.artwork--wide')).toHaveLength(2);
    expect(container.querySelectorAll('.artwork--poster')).toHaveLength(0);
  });

  it('houdt een gemengde rij op één hoogte, met de poster als vorm', () => {
    const { container } = render(HubRail, {
      props: {
        title: 'Recently added',
        items: [
          { id: 'a', kind: 'episode', title: 'E', added_at: '2026-01-01T00:00:00Z' },
          { id: 'b', kind: 'movie', title: 'M', added_at: '2026-01-01T00:00:00Z' }
        ] as Item[]
      }
    });
    expect(container.querySelectorAll('.artwork--poster')).toHaveLength(2);
    expect(container.querySelectorAll('.artwork--wide')).toHaveLength(0);
  });
});
