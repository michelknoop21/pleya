import { describe, expect, it, vi } from 'vitest';
import { render, screen } from '@testing-library/svelte';
import { createRawSnippet } from 'svelte';

import MediaCard from './MediaCard.svelte';
import { ARTWORK_LOADER_KEY } from './artworkLoader';
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

function userState(position_ms: number, watched = false): Item['user_state'] {
  return { position_ms, watched, play_count: 0, updated_at: '2026-01-01T00:00:00Z' };
}

const actions = createRawSnippet(() => ({
  render: () => '<button type="button" class="card-action">Play</button>'
}));

describe('MediaCard, staten van scherm 16', () => {
  it('tekent een voortgangsbalk op de juiste breedte en zet de resterende tijd eronder', () => {
    const { container } = render(MediaCard, {
      props: {
        item: item({ year: 2021, duration_ms: 9_360_000, user_state: userState(3_600_000) })
      }
    });
    const bar = container.querySelector<HTMLElement>('.prog i');
    expect(bar).not.toBeNull();
    // 3 600 000 van 9 360 000 is 38,46 procent; de balk rekent niet af.
    expect(parseFloat(bar!.style.width)).toBeCloseTo(38.46, 1);
    expect(screen.getByText('1h 36m left')).toBeInTheDocument();
    expect(screen.queryByText('2021')).toBeNull();
  });

  it('toont geen balk zonder positie, en ook niet als het item al gezien is', () => {
    const fresh = render(MediaCard, { props: { item: item({ duration_ms: 1000 }) } });
    expect(fresh.container.querySelector('.prog')).toBeNull();
    fresh.unmount();

    const seen = render(MediaCard, {
      props: { item: item({ duration_ms: 1000, user_state: userState(500, true) }) }
    });
    expect(seen.container.querySelector('.prog')).toBeNull();
  });

  it('laat gezien winnen van nieuw', () => {
    const { container } = render(MediaCard, {
      props: { item: item({ user_state: userState(0, true) }), isNew: true }
    });
    expect(screen.getByRole('img', { name: 'Watched' })).toBeInTheDocument();
    expect(container.querySelector('.dot-new')).toBeNull();
  });

  it('toont het nieuw-punt als het item niet gezien is', () => {
    const { container } = render(MediaCard, { props: { item: item(), isNew: true } });
    expect(screen.getByRole('img', { name: 'New' })).toBeInTheDocument();
    expect(container.querySelector('.seen')).toBeNull();
  });

  it('noemt een serie gezien als elke aflevering gezien is', () => {
    render(MediaCard, {
      props: { item: item({ kind: 'show', episode_count: 8, watched_episode_count: 8 }) }
    });
    expect(screen.getByRole('img', { name: 'Watched' })).toBeInTheDocument();
  });

  it('zet de versiepil alleen boven één versie', () => {
    const version = { id: 'v' } as NonNullable<Item['versions']>[number];
    const one = render(MediaCard, { props: { item: item({ versions: [version] }) } });
    expect(one.container.querySelector('.badge-src')).toBeNull();
    one.unmount();

    render(MediaCard, { props: { item: item({ versions: [version, { ...version, id: 'w' }] }) } });
    expect(screen.getByText('2 versions')).toBeInTheDocument();
  });

  it('toont zonder artwork titel en jaar op het vlak, en geen pictogram', () => {
    const { container } = render(MediaCard, {
      props: { item: item({ title: 'The Zone of Interest', year: 2023 }) }
    });
    const none = container.querySelector('.card__none');
    expect(none).not.toBeNull();
    expect(none).toHaveAttribute('data-title', 'The Zone of Interest');
    expect(none).toHaveAttribute('data-year', '2023');
    expect(none).toHaveAttribute('aria-hidden', 'true');
    expect(container.querySelector('.artwork__fallback')).toBeNull();
  });

  it('toont het vlak met titel ook als het laden mislukt', async () => {
    const loader = vi.fn(async () => {
      throw new Error('404');
    });
    const { container, findByText } = render(MediaCard, {
      props: { item: item({ artwork: { poster_id: 'p1' } }), eager: true },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    await findByText('Grease');
    await vi.waitFor(() => expect(container.querySelector('.card__none')).not.toBeNull());
    expect(loader).toHaveBeenCalledWith('p1', expect.any(AbortSignal));
  });

  it('zet de acties buiten de link', () => {
    render(MediaCard, { props: { item: item(), actions } });
    const button = screen.getByRole('button', { name: 'Play' });
    expect(button.closest('a')).toBeNull();
    expect(button.closest('.card__over')).not.toBeNull();
  });

  it('heeft geen overlay zonder snippet', () => {
    const { container } = render(MediaCard, { props: { item: item() } });
    expect(container.querySelector('.card__over')).toBeNull();
    expect(screen.queryByRole('button')).toBeNull();
  });

  it('gebruikt een opgegeven artworkId in plaats van het eigen beeld', async () => {
    const loader = vi.fn(async () => new Blob(['x']));
    render(MediaCard, {
      props: {
        item: item({ kind: 'episode', index: 3, artwork: { poster_id: 'ep', backdrop_id: 'epb' } }),
        shape: 'poster',
        artworkId: 'show-poster',
        eager: true
      },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    await vi.waitFor(() => expect(loader).toHaveBeenCalled());
    expect(loader).toHaveBeenCalledWith('show-poster', expect.any(AbortSignal));
    expect(loader).not.toHaveBeenCalledWith('ep', expect.any(AbortSignal));
  });

  it('valt zonder artworkId terug op het eigen beeld', async () => {
    const loader = vi.fn(async () => new Blob(['x']));
    render(MediaCard, {
      props: { item: item({ artwork: { poster_id: 'own' } }), eager: true },
      context: new Map([[ARTWORK_LOADER_KEY, loader]])
    });
    await vi.waitFor(() => expect(loader).toHaveBeenCalledWith('own', expect.any(AbortSignal)));
  });

  it('gebruikt een opgegeven onderregel in plaats van de afgeleide', () => {
    render(MediaCard, {
      props: {
        item: item({ kind: 'episode', index: 3, duration_ms: 1000, user_state: userState(500) }),
        subtitle: 'S2 · E3 · 31m left'
      }
    });
    expect(screen.getByText('S2 · E3 · 31m left')).toBeInTheDocument();
    expect(screen.queryByText('Episode 3')).toBeNull();
  });

  it('geeft wide een 16:9-overlay over een 16:9-beeld', () => {
    const { container } = render(MediaCard, {
      props: { item: item(), shape: 'wide', actions }
    });
    expect(container.querySelector('.card')).toHaveAttribute('data-shape', 'wide');
    expect(container.querySelector('.artwork--wide')).not.toBeNull();
  });
});
