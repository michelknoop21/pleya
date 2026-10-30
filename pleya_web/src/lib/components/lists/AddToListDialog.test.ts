import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Item } from '../../api/types';

const h = vi.hoisted(() => ({
  collections: vi.fn(), playlists: vi.fn(), addItems: vi.fn(), createCollection: vi.fn(), createPlaylist: vi.fn(),
  caps: { collections: true, playlists: true }
}));
vi.mock('../../stores/session.svelte', () => ({ session: { client: {}, get capabilities() { return h.caps; } } }));
vi.mock('../../api/lists', () => ({
  listsApi: () => ({ collections: h.collections, playlists: h.playlists, addItems: h.addItems, createCollection: h.createCollection, createPlaylist: h.createPlaylist })
}));

import AddToListDialog from './AddToListDialog.svelte';
import { addToList } from '../../stores/addToList.svelte';

const movie: Item = { id: 'm', kind: 'movie', title: 'Dune', added_at: '' };
const show: Item = { id: 's', kind: 'show', title: 'Severance', added_at: '' };

beforeEach(() => {
  h.caps = { collections: true, playlists: true };
  h.collections.mockReset().mockResolvedValue({ items: [{ id: 'c1', title: 'Sciencefiction' }] });
  h.playlists.mockReset().mockResolvedValue({ items: [{ id: 'p1', title: 'Zondag' }] });
  h.addItems.mockReset().mockResolvedValue(true);
  h.createCollection.mockReset().mockResolvedValue({ id: 'c2', title: 'Nieuw' });
  h.createPlaylist.mockReset();
  addToList.close();
  addToList.message = null;
});

async function openFor(item: Item) {
  render(AddToListDialog);
  addToList.open(item);
  return screen.findByRole('dialog');
}

describe('add to list', () => {
  it('adds a title to the chosen lists and reports it after closing', async () => {
    const dialog = await openFor(movie);
    expect(h.collections).toHaveBeenCalledWith(expect.objectContaining({ owned: true }));
    await fireEvent.click(await within(dialog).findByRole('checkbox', { name: 'Sciencefiction' }));
    await fireEvent.click(await within(dialog).findByRole('checkbox', { name: 'Zondag' }));
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Add' }));
    await waitFor(() => expect(h.addItems).toHaveBeenCalledTimes(2));
    expect(h.addItems).toHaveBeenCalledWith('collection', 'c1', ['m']);
    expect(h.addItems).toHaveBeenCalledWith('playlist', 'p1', ['m']);
    await waitFor(() => expect(screen.queryByRole('dialog')).toBeNull());
    expect(await screen.findByRole('status')).toHaveTextContent('Added to Sciencefiction, Zondag');
  });

  it('asks for a choice before it can add', async () => {
    const dialog = await openFor(movie);
    expect(within(dialog).getByRole('button', { name: 'Add' })).toBeDisabled();
  });

  it('offers no playlist for a show, and says why', async () => {
    const dialog = await openFor(show);
    await within(dialog).findByRole('checkbox', { name: 'Sciencefiction' });
    expect(within(dialog).queryByRole('checkbox', { name: 'Zondag' })).toBeNull();
    expect(within(dialog).getByText(/A playlist holds films and episodes/)).toBeInTheDocument();
  });

  it('creates a new list and adds to it', async () => {
    const dialog = await openFor(movie);
    await fireEvent.input(within(dialog).getByRole('textbox', { name: 'New list' }), { target: { value: 'Nieuw' } });
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Add' }));
    await waitFor(() => expect(h.addItems).toHaveBeenCalledWith('collection', 'c2', ['m']));
    expect(h.createCollection).toHaveBeenCalledWith({ title: 'Nieuw' });
  });

  it('stays open and names what failed', async () => {
    h.addItems.mockImplementation((_: string, id: string) => (id === 'p1' ? Promise.reject(new Error('offline')) : Promise.resolve(true)));
    const dialog = await openFor(movie);
    await fireEvent.click(await within(dialog).findByRole('checkbox', { name: 'Sciencefiction' }));
    await fireEvent.click(await within(dialog).findByRole('checkbox', { name: 'Zondag' }));
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Add' }));
    expect(await within(dialog).findByRole('alert')).toHaveTextContent('Added to Sciencefiction, but not to Zondag.');
    expect(screen.getByRole('dialog')).toBeInTheDocument();
  });
});
