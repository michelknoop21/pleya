import { fireEvent, render, screen, waitFor, within } from '@testing-library/svelte';
import { beforeEach, describe, expect, it, vi } from 'vitest';
import type { Collection } from '../../api/types';

const h = vi.hoisted(() => ({
  createCollection: vi.fn(), updateCollection: vi.fn(), createPlaylist: vi.fn(), updatePlaylist: vi.fn(), request: vi.fn(),
  canAdminister: false
}));
vi.mock('../../stores/session.svelte', () => ({
  session: { get canAdminister() { return h.canAdminister; }, me: { id: 'me' }, client: { request: h.request } }
}));
vi.mock('../../api/lists', async (original) => ({
  ...(await original<typeof import('../../api/lists')>()),
  listsApi: () => ({ createCollection: h.createCollection, updateCollection: h.updateCollection, createPlaylist: h.createPlaylist, updatePlaylist: h.updatePlaylist })
}));

import ListFormDialog from './ListFormDialog.svelte';

const existing = (over: Partial<Collection> = {}): Collection => ({
  id: 'c', title: 'Set', owner: { id: 'me', username: 'me' }, is_owner: true, visibility: 'private',
  item_count: 0, artwork: [], created_at: '', updated_at: '', ...over
});

beforeEach(() => {
  h.canAdminister = false;
  for (const fn of [h.createCollection, h.updateCollection, h.createPlaylist, h.updatePlaylist, h.request]) fn.mockReset();
  h.createCollection.mockResolvedValue(existing());
  h.updateCollection.mockResolvedValue(existing());
  h.createPlaylist.mockResolvedValue({ id: 'p', title: 'P' });
  h.request.mockResolvedValue({ items: [{ id: 'me', username: 'me' }, { id: 'kids', username: 'kids' }] });
});

describe('list form', () => {
  it('creates a private collection by default', async () => {
    const onsaved = vi.fn();
    render(ListFormDialog, { props: { open: true, kind: 'collection', onsaved } });
    const dialog = await screen.findByRole('dialog');
    await fireEvent.input(within(dialog).getByRole('textbox', { name: /Name/ }), { target: { value: ' Avond ' } });
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Create' }));
    await waitFor(() => expect(onsaved).toHaveBeenCalled());
    expect(h.createCollection).toHaveBeenCalledWith({ title: 'Avond', visibility: 'private' });
  });

  it('does not offer chosen users to a member, who has no list of names', async () => {
    render(ListFormDialog, { props: { open: true, kind: 'collection', onsaved: vi.fn() } });
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).queryByRole('radio', { name: 'Chosen users' })).toBeNull();
    expect(h.request).not.toHaveBeenCalled();
  });

  it('lets an administrator pick recipients, without himself', async () => {
    h.canAdminister = true;
    render(ListFormDialog, { props: { open: true, kind: 'collection', onsaved: vi.fn() } });
    const dialog = await screen.findByRole('dialog');
    await fireEvent.input(within(dialog).getByRole('textbox', { name: /Name/ }), { target: { value: 'Voor de kinderen' } });
    await fireEvent.click(within(dialog).getByRole('radio', { name: 'Chosen users' }));
    await fireEvent.click(await within(dialog).findByRole('checkbox', { name: 'kids' }));
    expect(within(dialog).queryByRole('checkbox', { name: 'me' })).toBeNull();
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Create' }));
    await waitFor(() => expect(h.createCollection).toHaveBeenCalledWith({ title: 'Voor de kinderen', visibility: 'users', shared_with: ['kids'] }));
  });

  it('never sends a visibility it does not know back', async () => {
    const list = existing({ visibility: 'friends' as Collection['visibility'] });
    render(ListFormDialog, { props: { open: true, kind: 'collection', list, onsaved: vi.fn() } });
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).getByText(/does not know/)).toBeInTheDocument();
    await fireEvent.click(within(dialog).getByRole('button', { name: 'Save' }));
    await waitFor(() => expect(h.updateCollection).toHaveBeenCalledWith('c', { title: 'Set' }));
  });

  it('asks a playlist only for its name', async () => {
    render(ListFormDialog, { props: { open: true, kind: 'playlist', onsaved: vi.fn() } });
    const dialog = await screen.findByRole('dialog');
    expect(within(dialog).queryByRole('radio')).toBeNull();
  });
});
