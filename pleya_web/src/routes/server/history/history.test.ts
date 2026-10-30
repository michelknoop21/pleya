import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
const h = vi.hoisted(() => ({ history: vi.fn(), favorites: vi.fn(), ratings: vi.fn(), deleteEntry: vi.fn(), clear: vi.fn(), capabilities: { history: true, favorites: true, ratings: true } as Record<string, boolean> }));
vi.mock('../../../lib/stores/session.svelte.js', () => ({ session: { client: { sessionGeneration: 0 }, get capabilities() { return h.capabilities; } } }));
vi.mock('../../../lib/api/personal', () => ({ personalApi: () => ({ history: h.history, favorites: h.favorites, ratings: h.ratings, deleteHistoryEntry: h.deleteEntry, clearHistory: h.clear }) }));
import History from './+page.svelte';
const item = (id: string, kind = 'movie', extra = {}) => ({ id, title: id, kind, added_at: '2026-10-30T00:00:00Z', ...extra });
const entry = (id: string, kind = 'movie', extra = {}) => ({ id: `h-${id}`, item: item(id, kind), started_at: '2026-10-30T10:00:00Z', ended_at: '2026-10-30T11:00:00Z', start_position_ms: 0, end_position_ms: 3000, duration_ms: 10000, completed: false, device_name: 'iPad', ...extra });
const page = (items: unknown[], next_cursor: string | null = null) => ({ items, next_cursor });
beforeEach(() => {
  h.capabilities = { history: true, favorites: true, ratings: true };
  h.history.mockReset().mockResolvedValue(page([]));
  h.favorites.mockReset().mockResolvedValue({ items: [], next_cursor: null });
  h.ratings.mockReset().mockResolvedValue({ items: [], next_cursor: null });
  h.deleteEntry.mockReset().mockResolvedValue(undefined);
  h.clear.mockReset().mockResolvedValue(undefined);
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

  describe('with personal_data', () => {
    beforeEach(() => {
      h.capabilities = { history: true, favorites: true, ratings: true, personal_data: true };
    });
    it('asks the server for one kind and restarts the list', async () => {
      h.history.mockResolvedValueOnce(page([entry('Film'), entry('Episode', 'episode')], 'n')).mockResolvedValueOnce(page([entry('Only', 'episode')]));
      render(History);
      await screen.findByText('Film');
      await fireEvent.click(screen.getByRole('button', { name: 'Episodes' }));
      await screen.findByText('Only');
      expect(screen.queryByText('Film')).toBeNull();
      expect(h.history).toHaveBeenLastCalledWith({ limit: 50, kind: 'episode' }, expect.any(AbortSignal));
    });
    it('keeps the filter reachable when a kind has no lines', async () => {
      h.history.mockResolvedValueOnce(page([entry('Film')])).mockResolvedValueOnce(page([]));
      render(History);
      await screen.findByText('Film');
      await fireEvent.click(screen.getByRole('button', { name: 'Episodes' }));
      await screen.findByText('Nothing of this type in your history.');
      expect(screen.getByRole('button', { name: 'All' })).toBeInTheDocument();
    });
    it('removes one line only after confirmation and keeps the rest', async () => {
      h.history.mockResolvedValueOnce(page([entry('Gone'), entry('Stays')]));
      render(History);
      await fireEvent.click(await screen.findByRole('button', { name: 'Remove Gone from history' }));
      expect(h.deleteEntry).not.toHaveBeenCalled();
      await fireEvent.click(screen.getByRole('button', { name: 'Remove' }));
      expect(h.deleteEntry).toHaveBeenCalledWith('h-Gone');
      await waitFor(() => expect(screen.queryByRole('link', { name: /Gone/ })).toBeNull());
      expect(screen.getByRole('link', { name: /Stays/ })).toBeInTheDocument();
      expect(h.clear).not.toHaveBeenCalled();
    });
    it('keeps the line and says why when removing fails', async () => {
      h.history.mockResolvedValueOnce(page([entry('Stays')]));
      h.deleteEntry.mockRejectedValueOnce(new Error('offline'));
      render(History);
      await fireEvent.click(await screen.findByRole('button', { name: 'Remove Stays from history' }));
      await fireEvent.click(screen.getByRole('button', { name: 'Remove' }));
      await screen.findByRole('alert');
      expect(screen.getByRole('link', { name: /Stays/ })).toBeInTheDocument();
    });
    it('clears everything only after confirmation and shows the empty state', async () => {
      h.history.mockResolvedValueOnce(page([entry('Gone')], 'n'));
      render(History);
      await fireEvent.click(await screen.findByRole('button', { name: 'Clear history' }));
      const dialog = await screen.findByRole('dialog');
      expect(h.clear).not.toHaveBeenCalled();
      await fireEvent.click(within(dialog).getByRole('button', { name: 'Clear history' }));
      expect(h.clear).toHaveBeenCalledOnce();
      await screen.findByText('Nothing watched yet');
      expect(screen.queryByRole('link', { name: /Gone/ })).toBeNull();
    });
    it('fills the ratings panel from the ratings list and pages it', async () => {
      h.history.mockResolvedValueOnce(page([{ ...entry('Unrated') }]));
      h.ratings.mockResolvedValueOnce({ items: [item('Best', 'movie', { rating: 9 })], next_cursor: 'r' }).mockResolvedValueOnce({ items: [item('Next', 'movie', { rating: 4 })], next_cursor: null });
      render(History);
      await screen.findByText('9 / 10');
      expect(h.ratings).toHaveBeenCalledWith({ limit: 6 }, expect.any(AbortSignal));
      expect(screen.queryByText(/Rated titles from your history/)).toBeNull();
      const panelMore = screen.getAllByRole('button', { name: 'Load more' }).at(-1)!;
      await fireEvent.click(panelMore);
      await screen.findByText('4 / 10');
      expect(h.ratings).toHaveBeenLastCalledWith({ limit: 6, cursor: 'r' }, expect.any(AbortSignal));
    });
    it('offers no erasing without the capability', async () => {
      h.capabilities = { history: true, favorites: true, ratings: true };
      h.history.mockResolvedValueOnce(page([entry('Film')]));
      render(History);
      await screen.findByText('Film');
      expect(screen.queryByRole('button', { name: 'Clear history' })).toBeNull();
      expect(screen.queryByRole('button', { name: 'Remove Film from history' })).toBeNull();
      expect(h.ratings).not.toHaveBeenCalled();
    });
  });
});
