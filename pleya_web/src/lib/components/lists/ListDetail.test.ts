import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import { ApiError } from '../../api/errors';
import type { Item } from '../../api/types';

const h = vi.hoisted(() => ({
  playlist: vi.fn(), items: vi.fn(), readForReorder: vi.fn(), saveOrder: vi.fn()
}));
vi.mock('$app/navigation', () => ({ goto: vi.fn() }));
vi.mock('../../stores/session.svelte', () => ({ session: { client: { sessionGeneration: 1 }, capabilities: { playback_plan: false } } }));
vi.mock('../../api/lists', async (original) => ({
  ...(await original<typeof import('../../api/lists')>()),
  listsApi: () => ({ playlist: h.playlist, items: h.items, readForReorder: h.readForReorder, saveOrder: h.saveOrder })
}));

import ListDetail from './ListDetail.svelte';

const item = (id: string): Item => ({ id, kind: 'movie', title: `Film ${id}`, added_at: '' });
const rows = () => screen.getAllByRole('listitem').map((row) => row.getAttribute('data-item-id'));
const conflict = () => new ApiError({ code: 'library.list_conflict', message: 'changed', status: 409, retryable: false });

beforeEach(() => {
  h.playlist.mockReset().mockResolvedValue({ id: 'p', title: 'Avond', item_count: 2, duration_ms: 0, artwork: [], revision: 3 });
  h.items.mockReset().mockResolvedValue({ items: [item('a'), item('b')], next_cursor: null });
  h.readForReorder.mockReset().mockResolvedValue({ items: [item('a'), item('b')], revision: 3 });
  h.saveOrder.mockReset();
});

describe('reordering a list that changes in the meantime', () => {
  async function reorder() {
    render(ListDetail, { props: { kind: 'playlist', id: 'p' } });
    await fireEvent.click(await screen.findByRole('button', { name: 'Change order' }));
    await fireEvent.click(await screen.findByRole('button', { name: 'Move Film b up' }));
    await fireEvent.click(screen.getByRole('button', { name: 'Save order' }));
  }

  it('saves against the revision the mode opened with', async () => {
    h.saveOrder.mockResolvedValue(true);
    await reorder();
    await waitFor(() => expect(h.saveOrder).toHaveBeenCalledWith('playlist', 'p', ['b', 'a'], 3, expect.anything()));
  });

  it('keeps the chosen order, shows what changed and saves against the new revision', async () => {
    h.saveOrder.mockRejectedValueOnce(conflict()).mockResolvedValue(true);
    h.readForReorder
      .mockResolvedValueOnce({ items: [item('a'), item('b')], revision: 3 })
      .mockResolvedValueOnce({ items: [item('a'), item('b'), item('nieuw')], revision: 4 });
    await reorder();

    expect(await screen.findByRole('alert')).toHaveTextContent('This list changed while you were reordering');
    expect(rows()).toEqual(['b', 'a', 'nieuw']);

    await fireEvent.click(screen.getByRole('button', { name: 'Save order' }));
    await waitFor(() => expect(h.saveOrder).toHaveBeenLastCalledWith('playlist', 'p', ['b', 'a', 'nieuw'], 4, expect.anything()));
  });

  it('shows any other failure in the mode, and changes nothing about it', async () => {
    h.saveOrder.mockRejectedValue(new Error('offline'));
    await reorder();
    await waitFor(() => expect(screen.getByRole('button', { name: 'Save order' })).toBeEnabled());
    expect(h.readForReorder).toHaveBeenCalledTimes(1);
    expect(rows()).toEqual(['b', 'a']);
  });
});
