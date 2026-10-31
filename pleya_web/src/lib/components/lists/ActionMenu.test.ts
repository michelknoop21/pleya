import { fireEvent, render, screen, waitFor } from '@testing-library/svelte';
import { describe, expect, it, vi } from 'vitest';
import ActionMenu from './ActionMenu.svelte';

describe('action menu', () => {
  it('walks with the arrows, closes on Escape and returns focus', async () => {
    const edit = vi.fn();
    render(ActionMenu, { props: { label: 'More', actions: [{ label: 'Edit', onselect: edit }, { label: 'Delete', danger: true, onselect: vi.fn() }] } });
    const button = screen.getByRole('button', { name: 'More' });
    await fireEvent.click(button);
    await waitFor(() => expect(document.activeElement).toBe(screen.getByRole('menuitem', { name: 'Edit' })));
    await fireEvent.keyDown(screen.getByRole('menu'), { key: 'ArrowDown' });
    expect(document.activeElement).toBe(screen.getByRole('menuitem', { name: 'Delete' }));
    await fireEvent.keyDown(screen.getByRole('menu'), { key: 'Escape' });
    expect(screen.queryByRole('menu')).toBeNull();
    expect(document.activeElement).toBe(button);
    expect(edit).not.toHaveBeenCalled();
  });

  it('runs the chosen action once', async () => {
    const edit = vi.fn();
    render(ActionMenu, { props: { label: 'More', actions: [{ label: 'Edit', onselect: edit }] } });
    await fireEvent.click(screen.getByRole('button', { name: 'More' }));
    await fireEvent.click(await screen.findByRole('menuitem', { name: 'Edit' }));
    expect(edit).toHaveBeenCalledTimes(1);
    expect(screen.queryByRole('menu')).toBeNull();
  });
});
