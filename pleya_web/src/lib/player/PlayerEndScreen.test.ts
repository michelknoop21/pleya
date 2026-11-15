/** Het slotscherm: je cijfer gaat via de echte `personalApi` naar PUT en DELETE op `/ratings/{item_id}`. */
import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';

import type { Item } from '../api/types';

const h = vi.hoisted(() => {
  const ok = async () => ({ response: { status: 204 } });
  const raw = { PUT: vi.fn(ok), DELETE: vi.fn(ok) };
  return { raw };
});
vi.mock('../stores/session.svelte', () => ({
  session: {
    capabilities: { ratings: true, favorites: true },
    client: {
      sessionGeneration: 1,
      hub: async () => ({ items: [] }),
      request: async (call: (raw: unknown) => Promise<{ data?: unknown }>) => (await call(h.raw)).data
    }
  }
}));
import PlayerEndScreen from './PlayerEndScreen.svelte';

const item: Item = { id: 'film', kind: 'movie', title: 'Film', added_at: '2026-01-01T00:00:00Z' };
const params = { path: { item_id: 'film' } };

describe('slotscherm: cijfer', () => {
  it('zet een cijfer met PUT en haalt het met dezelfde knop weer weg met DELETE', async () => {
    const onchange = vi.fn();
    const view = render(PlayerEndScreen, { props: { item, heading: 'Film', onchange, onreplay: vi.fn() } });
    await fireEvent.click(screen.getByRole('button', { name: 'Rate 8 out of 10' }));
    await waitFor(() => expect(onchange).toHaveBeenLastCalledWith({ ...item, rating: 8 }));
    expect(h.raw.PUT).toHaveBeenCalledWith('/ratings/{item_id}', { params, body: { rating: 8 } });
    expect(h.raw.DELETE).not.toHaveBeenCalled();

    await view.rerender({ item: { ...item, rating: 8 } });
    expect(screen.getByRole('button', { name: 'Rate 8 out of 10' })).toHaveAttribute('aria-pressed', 'true');
    await fireEvent.click(screen.getByRole('button', { name: 'Rate 8 out of 10' }));
    await waitFor(() => expect(onchange).toHaveBeenLastCalledWith({ ...item, rating: null }));
    expect(h.raw.DELETE).toHaveBeenCalledWith('/ratings/{item_id}', { params });
    expect(h.raw.PUT).toHaveBeenCalledTimes(1);
  });
});
