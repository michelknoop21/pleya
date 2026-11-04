import { render, screen } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ watchHistory: vi.fn(), canAdminister: true }));
vi.mock('../stores/session.svelte', () => ({ session: { client: {}, get canAdminister() { return h.canAdminister; } } }));
vi.mock('../api/admin', () => ({ adminApi: () => ({ watchHistory: h.watchHistory }) }));
import WatchedBy from './WatchedBy.svelte';
const row = (user: string, extra = {}) => ({ user_id: user, username: user, item_id: 'movie', item_title: 'x', item_kind: 'movie', watched: true, play_count: 1, updated_at: '2026-10-29T10:00:00Z', ...extra });
const movie = { id: 'movie', kind: 'movie' } as const;
beforeEach(() => {
  h.canAdminister = true;
  h.watchHistory.mockReset().mockResolvedValue({ days: 31, items: [], truncated: false });
});
describe('WatchedBy', () => {
  it('names each viewer of this title once, newest first, over 31 days', async () => {
    h.watchHistory.mockResolvedValueOnce({ days: 31, truncated: false, items: [row('ana'), row('ana'), row('bo'), row('other', { item_id: 'else' })] });
    render(WatchedBy, { item: movie });
    await screen.findByRole('heading', { name: 'Watched by' });
    expect(screen.getAllByRole('listitem').map((li) => li.textContent?.split(' ')[0])).toEqual(['ana', 'bo']);
    expect(h.watchHistory).toHaveBeenCalledWith(31, expect.any(AbortSignal));
    expect(screen.getByText('Last 31 days')).toBeInTheDocument();
  });
  it('counts an episode towards its show and says when the list can be incomplete', async () => {
    h.watchHistory.mockResolvedValueOnce({ days: 31, truncated: true, items: [row('ana', { item_id: 'ep', series_id: 'show' })] });
    render(WatchedBy, { item: { id: 'show', kind: 'show' } });
    await screen.findByText('ana');
    expect(screen.getByText(/can be incomplete/)).toBeInTheDocument();
  });
  it('does not ask for a member or a season, and stays away on failure', async () => {
    h.canAdminister = false;
    render(WatchedBy, { item: movie });
    h.canAdminister = true;
    render(WatchedBy, { item: { id: 's', kind: 'season' } });
    expect(h.watchHistory).not.toHaveBeenCalled();
    h.watchHistory.mockRejectedValueOnce(new Error('404'));
    render(WatchedBy, { item: movie });
    await vi.waitFor(() => expect(h.watchHistory).toHaveBeenCalled());
    expect(screen.queryByRole('heading')).toBeNull();
  });
});
