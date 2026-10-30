import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import type { Item } from '../../api/types';
import ListReorder from './ListReorder.svelte';

const item = (id: string): Item => ({ id, kind: 'movie', title: `Film ${id}`, added_at: '' });
const items = [item('a'), item('b'), item('c')];
const handle = (id: string) => screen.getByRole('button', { name: new RegExp(`^Film ${id}, position`) });
const titles = () => screen.getAllByRole('listitem').map((row) => row.getAttribute('data-item-id'));

describe('reorder mode', () => {
  it('moves a row with the arrow keys, keeps focus on it and says where it went', async () => {
    render(ListReorder, { props: { items, onsave: vi.fn(), oncancel: vi.fn() } });
    const first = handle('a');
    first.focus();
    await fireEvent.keyDown(first, { key: 'ArrowDown' });
    expect(titles()).toEqual(['b', 'a', 'c']);
    await waitFor(() => expect(document.activeElement).toBe(handle('a')));
    expect(screen.getByRole('status')).toHaveTextContent('Film a moved to position 2 of 3');

    await fireEvent.keyDown(handle('a'), { key: 'End' });
    expect(titles()).toEqual(['b', 'c', 'a']);
    await fireEvent.keyDown(handle('a'), { key: 'Home' });
    expect(titles()).toEqual(['a', 'b', 'c']);
  });

  it('offers buttons for touch and cannot move past an edge', async () => {
    render(ListReorder, { props: { items, onsave: vi.fn(), oncancel: vi.fn() } });
    expect(screen.getByRole('button', { name: 'Move Film a up' })).toBeDisabled();
    expect(screen.getByRole('button', { name: 'Move Film c down' })).toBeDisabled();
    await fireEvent.click(screen.getByRole('button', { name: 'Move Film c up' }));
    expect(titles()).toEqual(['a', 'c', 'b']);
  });

  it('saves nothing until asked, and sends the whole order', async () => {
    const onsave = vi.fn().mockResolvedValue(undefined);
    render(ListReorder, { props: { items, onsave, oncancel: vi.fn() } });
    const save = screen.getByRole('button', { name: 'Save order' });
    expect(save).toBeDisabled();
    await fireEvent.keyDown(handle('c'), { key: 'ArrowUp' });
    expect(onsave).not.toHaveBeenCalled();
    await fireEvent.click(save);
    expect(onsave).toHaveBeenCalledWith(['a', 'c', 'b']);
  });

  it('keeps the new order on screen when saving fails', async () => {
    const onsave = vi.fn().mockRejectedValue(new Error('offline'));
    render(ListReorder, { props: { items, onsave, oncancel: vi.fn() } });
    await fireEvent.keyDown(handle('c'), { key: 'ArrowUp' });
    await fireEvent.click(screen.getByRole('button', { name: 'Save order' }));
    expect(await screen.findByRole('alert')).toBeInTheDocument();
    expect(titles()).toEqual(['a', 'c', 'b']);
    expect(screen.getByRole('button', { name: 'Save order' })).toBeEnabled();
  });
});
