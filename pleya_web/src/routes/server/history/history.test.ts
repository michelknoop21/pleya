import { fireEvent, render, screen, within } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ history: vi.fn(), favorites: vi.fn(), capabilities: { history: true, favorites: true, ratings: true } as Record<string, boolean> }));
vi.mock('../../../lib/stores/session.svelte.js', () => ({ session: { client: { sessionGeneration: 0 }, get capabilities() { return h.capabilities; } } }));
vi.mock('../../../lib/api/personal', () => ({ personalApi: () => ({ history: h.history, favorites: h.favorites }) }));
import History from './+page.svelte';
const item = (id: string, kind = 'movie', extra = {}) => ({ id, title: id, kind, added_at: '2026-10-30T00:00:00Z', ...extra });
const entry = (id: string, kind = 'movie', extra = {}) => ({ id: `h-${id}`, item: item(id, kind), started_at: '2026-10-30T10:00:00Z', ended_at: '2026-10-30T11:00:00Z', start_position_ms: 0, end_position_ms: 3000, duration_ms: 10000, completed: false, device_name: 'iPad', ...extra });
const page = (items: unknown[], next_cursor: string | null = null) => ({ items, next_cursor });
beforeEach(() => {
  h.capabilities = { history: true, favorites: true, ratings: true };
  h.history.mockReset().mockResolvedValue(page([]));
  h.favorites.mockReset().mockResolvedValue({ items: [], next_cursor: null });
});
describe('watch history route', () => {
  it('lists a session with its progress and walks the cursor', async () => {
    h.history.mockResolvedValueOnce(page([entry('First')], 'n')).mockResolvedValueOnce(page([entry('Second', 'movie', { completed: true })]));
    render(History);
    const row = (await screen.findByText('First')).closest('a')!;
    expect(row).toHaveAttribute('href', '/items/First');
    expect(within(row).getByText('30%')).toBeInTheDocument();
    await fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await screen.findByText('Second');
    expect(h.history).toHaveBeenLastCalledWith({ limit: 50, cursor: 'n' }, expect.any(AbortSignal));
    expect(screen.getByText('watched')).toBeInTheDocument();
  });
  it('filters the loaded rows by kind', async () => {
    h.history.mockResolvedValueOnce(page([entry('Film'), entry('Episode', 'episode')]));
    render(History);
    await screen.findByText('Film');
    await fireEvent.click(screen.getByRole('button', { name: 'Episodes' }));
    expect(screen.queryByText('Film')).toBeNull();
    expect(screen.getByText('Episode')).toBeInTheDocument();
  });
  it('shows favorites and rated titles beside the history, each title once', async () => {
    h.history.mockResolvedValueOnce(page([{ ...entry('Rated'), item: item('Rated', 'movie', { rating: 8 }) }]));
    h.favorites.mockResolvedValueOnce({ items: [item('Rated', 'movie', { rating: 8 })], next_cursor: null, total_estimate: 14 });
    render(History);
    await screen.findByRole('link', { name: 'All 14' });
    expect(screen.getAllByText('8 / 10')).toHaveLength(1);
  });
  it('keeps the history when the favorites panel fails', async () => {
    h.history.mockResolvedValueOnce(page([entry('Stays')]));
    h.favorites.mockRejectedValueOnce(new Error('offline'));
    render(History);
    await screen.findByText('Stays');
    expect(screen.queryByRole('alert')).toBeNull();
  });
  it('retains rows after a failed page and retries it', async () => {
    h.history.mockResolvedValueOnce(page([entry('Kept')], 'n')).mockRejectedValueOnce(new Error('offline')).mockResolvedValueOnce(page([entry('Later')]));
    render(History);
    await screen.findByText('Kept');
    await fireEvent.click(screen.getByRole('button', { name: 'Load more' }));
    await fireEvent.click(await screen.findByRole('button', { name: 'Retry' }));
    await screen.findByText('Later');
    expect(screen.getByText('Kept')).toBeInTheDocument();
  });
  it('asks nothing of a server without history', () => {
    h.capabilities = {};
    render(History);
    expect(h.history).not.toHaveBeenCalled();
    expect(h.favorites).not.toHaveBeenCalled();
    expect(screen.getByRole('link', { name: 'My Pleya' })).toHaveAttribute('href', '/server');
  });
});
