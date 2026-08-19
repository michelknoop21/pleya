import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';

import MediaCard from './MediaCard.svelte';
import type { Item } from '../api/types';

// De kaart laadt artwork via de client; die aanvraag hoort hier niet thuis.
vi.mock('../stores/session.svelte', () => ({
  session: { client: { artworkBlob: vi.fn(async () => new Blob(['x'])) } }
}));

function item(patch: Partial<Item> = {}): Item {
  return {
    id: 'i1',
    kind: 'movie',
    title: 'Grease',
    added_at: '2026-01-01T00:00:00Z',
    ...patch
  } as Item;
}

describe('MediaCard', () => {
  it('is een link naar de detailpagina van het item', () => {
    render(MediaCard, { props: { item: item() } });
    const link = screen.getByRole('link', { name: /Grease/ });
    expect(link).toHaveAttribute('href', '/items/i1');
  });

  it('toont de titel en het jaar', () => {
    render(MediaCard, { props: { item: item({ year: 1978 }) } });
    expect(screen.getByText('Grease')).toBeInTheDocument();
    expect(screen.getByText('1978')).toBeInTheDocument();
  });

  it('toont geen samenvatting, genre, cast of beoordeling, want Item draagt die niet', () => {
    const { container } = render(MediaCard, { props: { item: item({ year: 1978 }) } });
    const text = container.textContent ?? '';
    for (const absent of ['summary', 'genre', 'cast', 'rating', 'studio', 'tagline']) {
      expect(text.toLowerCase()).not.toContain(absent);
    }
  });

  it('geeft een aflevering een 16:9-beeld en een film een poster', () => {
    const { container, unmount } = render(MediaCard, {
      props: { item: item({ kind: 'episode', index: 2 }) }
    });
    expect(container.querySelector('.artwork--wide')).not.toBeNull();
    unmount();

    const movie = render(MediaCard, { props: { item: item() } });
    expect(movie.container.querySelector('.artwork--poster')).not.toBeNull();
  });

  it('houdt de metaregel gereserveerd, ook als er niets in staat', () => {
    const { container } = render(MediaCard, { props: { item: item() } });
    const meta = container.querySelector('.card__meta');
    expect(meta).not.toBeNull();
    expect(meta?.textContent).toBe('');
  });
});
